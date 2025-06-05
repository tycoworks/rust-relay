use anyhow::{Result};
use futures_util::{SinkExt, StreamExt, TryStreamExt};
use log::{debug, error, info, warn};
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::broadcast;
use tokio::sync::Mutex;
use tokio_postgres::CopyOutStream;
use tokio_tungstenite::tungstenite::Message;
use tokio_tungstenite::WebSocketStream;

#[derive(Clone)]
pub struct Relay {
    clients: Arc<Mutex<HashMap<u64, broadcast::Sender<String>>>>,
    next_client_id: Arc<Mutex<u64>>,
    // Buffer to store the current snapshot for new clients
    snapshot_buffer: Arc<Mutex<Vec<String>>>,
    is_snapshot_complete: Arc<Mutex<bool>>,
}

impl Relay {
    pub fn new() -> Self {
        Self {
            clients: Arc::new(Mutex::new(HashMap::new())),
            next_client_id: Arc::new(Mutex::new(0)),
            snapshot_buffer: Arc::new(Mutex::new(Vec::new())),
            is_snapshot_complete: Arc::new(Mutex::new(false)),
        }
    }

    pub async fn handle_materialize_copy_stream(
        &self,
        stream: CopyOutStream,
    ) -> Result<()> {
        // Pin the stream to handle the PhantomPinned requirement
        tokio::pin!(stream);
        
        let mut is_processing_snapshot = true;
        let mut snapshot_rows = Vec::new();
        let mut rows_received = 0;
        
        while let Some(chunk) = stream.try_next().await? {
            // Convert bytes to string
            let data = String::from_utf8_lossy(&chunk);
            
            // Split by newlines as Materialize sends newline-delimited data
            for line in data.lines() {
                if line.trim().is_empty() {
                    continue;
                }
                
                rows_received += 1;
                debug!("Received line {}: {}", rows_received, line);
                
                // For COPY format, we need a different approach to detect snapshot end
                // Let's assume snapshot is complete after we get some initial rows
                // and then see a different timestamp pattern (indicating real-time updates)
                
                if is_processing_snapshot {
                    snapshot_rows.push(line.to_string());
                    
                    // Simple heuristic: if we've received more than 3 rows and
                    // there's a pause, consider snapshot complete
                    if snapshot_rows.len() >= 3 {
                        // Wait a brief moment to see if more snapshot data comes
                        tokio::time::sleep(tokio::time::Duration::from_millis(100)).await;
                        
                        info!("Treating initial {} rows as snapshot", snapshot_rows.len());
                        
                        // Store the snapshot
                        {
                            let mut buffer = self.snapshot_buffer.lock().await;
                            *buffer = snapshot_rows.clone();
                        }
                        {
                            let mut complete = self.is_snapshot_complete.lock().await;
                            *complete = true;
                        }
                        
                        is_processing_snapshot = false;
                        
                        // Send this row as both part of snapshot and as real-time update
                        self.broadcast_to_clients(line).await;
                        continue;
                    }
                } else {
                    // This is a real-time update, broadcast immediately
                    self.broadcast_to_clients(line).await;
                }
            }
        }
        
        // If we exit the loop and still processing snapshot, complete it
        if is_processing_snapshot && !snapshot_rows.is_empty() {
            info!("Stream ended, treating {} rows as final snapshot", snapshot_rows.len());
            {
                let mut buffer = self.snapshot_buffer.lock().await;
                *buffer = snapshot_rows;
            }
            {
                let mut complete = self.is_snapshot_complete.lock().await;
                *complete = true;
            }
        }
        
        info!("Materialize copy stream ended");
        Ok(())
    }
    
    async fn broadcast_to_clients(&self, message: &str) {
        debug!("Broadcasting update to clients: {}", message);
        let clients = self.clients.lock().await;
        let client_count = clients.len();
        
        if client_count == 0 {
            debug!("No clients connected, skipping broadcast");
            return;
        }
        
        debug!("Broadcasting to {} clients", client_count);
        for (client_id, client) in clients.iter() {
            match client.send(message.to_string()) {
                Ok(_) => debug!("Successfully sent to client {}", client_id),
                Err(e) => error!("Failed to send to client {}: {}", client_id, e),
            }
        }
    }

    pub async fn handle_websocket(
        &self,
        ws_stream: WebSocketStream<tokio::net::TcpStream>,
    ) -> Result<()> {
        let (tx, rx) = broadcast::channel(1000);  // Increased buffer for snapshot
        let client_id = {
            let mut id = self.next_client_id.lock().await;
            let current = *id;
            *id += 1;
            current
        };
        
        info!("Client {} connected", client_id);
        
        {
            let mut clients = self.clients.lock().await;
            clients.insert(client_id, tx.clone());
        }

        let (ws_sink, mut ws_stream) = ws_stream.split();
        let ws_sink = Arc::new(tokio::sync::Mutex::new(ws_sink));
        let ws_sink_clone = ws_sink.clone();
        
        // Send initial snapshot to new client if available
        let snapshot_sent = self.send_initial_snapshot(client_id, &ws_sink).await;
        if !snapshot_sent {
            warn!("Client {} connected before snapshot was ready", client_id);
        }
        
        let send_task = tokio::spawn(async move {
            let mut rx = rx;
            while let Ok(msg) = rx.recv().await {
                let mut sink = ws_sink_clone.lock().await;
                if let Err(e) = sink.send(Message::Text(msg)).await {
                    error!("Failed to send WebSocket message: {}", e);
                    break;
                }
            }
        });

        while let Some(msg) = ws_stream.next().await {
            match msg {
                Ok(Message::Close(_)) => {
                    info!("Client {} disconnected", client_id);
                    break;
                }
                Ok(Message::Ping(data)) => {
                    let mut sink = ws_sink.lock().await;
                    if let Err(e) = sink.send(Message::Pong(data)).await {
                        error!("Failed to send pong: {}", e);
                        break;
                    }
                }
                Ok(_) => {}
                Err(e) => {
                    error!("WebSocket error: {}", e);
                    break;
                }
            }
        }

        {
            let mut clients = self.clients.lock().await;
            clients.remove(&client_id);
        }
        send_task.abort();
        Ok(())
    }
    
    async fn send_initial_snapshot(
        &self, 
        client_id: u64, 
        ws_sink: &Arc<tokio::sync::Mutex<futures_util::stream::SplitSink<WebSocketStream<tokio::net::TcpStream>, Message>>>
    ) -> bool {
        let is_complete = {
            let complete = self.is_snapshot_complete.lock().await;
            *complete
        };
        
        if !is_complete {
            return false;
        }
        
        let snapshot = {
            let buffer = self.snapshot_buffer.lock().await;
            buffer.clone()
        };
        
        info!("Sending initial snapshot to client {} ({} rows)", client_id, snapshot.len());
        
        let mut sink = ws_sink.lock().await;
        for row in snapshot {
            if let Err(e) = sink.send(Message::Text(row)).await {
                error!("Failed to send snapshot row to client {}: {}", client_id, e);
                return false;
            }
        }
        
        info!("Initial snapshot sent to client {}", client_id);
        true
    }
} 