mod relay;

use anyhow::{Context, Result};
use dotenvy::dotenv;
use log::{error, info};
use serde::{Deserialize, Serialize};
use std::env;
use tokio::net::TcpListener;
use tokio_postgres::{Config as PgConfig};
use tokio_postgres_rustls::MakeRustlsConnect;
use rustls::{ClientConfig, RootCertStore};

use crate::relay::Relay;

#[derive(Debug, Serialize, Deserialize)]
struct PnLRow {
    instrument_id: i32,
    symbol: String,
    net_position: i64,
    latest_price: f64,
    market_value: f64,
    avg_cost_basis: Option<f64>,
    theoretical_pnl: f64,
}

#[derive(Debug)]
struct AppConfig {
    materialize: MaterializeConfig,
    websocket: WebSocketConfig,
}

#[derive(Debug)]
struct MaterializeConfig {
    host: String,
    port: u16,
    dbname: String,
    user: String,
    password: String,
}

#[derive(Debug)]
struct WebSocketConfig {
    host: String,
    port: u16,
}

impl AppConfig {
    fn from_env() -> Result<Self> {
        Ok(AppConfig {
            materialize: MaterializeConfig {
                host: env::var("MATERIALIZE_HOST").unwrap_or_else(|_| "localhost".to_string()),
                port: env::var("MATERIALIZE_PORT")
                    .unwrap_or_else(|_| "6875".to_string())
                    .parse()
                    .context("Invalid MATERIALIZE_PORT")?,
                dbname: env::var("MATERIALIZE_DB").unwrap_or_else(|_| "materialize".to_string()),
                user: env::var("MATERIALIZE_USER").unwrap_or_else(|_| "materialize".to_string()),
                password: env::var("MATERIALIZE_PASSWORD")
                    .context("MATERIALIZE_PASSWORD must be set")?,
            },
            websocket: WebSocketConfig {
                host: env::var("WS_HOST").unwrap_or_else(|_| "0.0.0.0".to_string()),
                port: env::var("WS_PORT")
                    .unwrap_or_else(|_| "8080".to_string())
                    .parse()
                    .context("Invalid WS_PORT")?,
            },
        })
    }
}

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize logging
    env_logger::init();
    
    // Load environment variables
    dotenv().ok();
    
    // Load configuration
    let config = AppConfig::from_env()?;
    info!("Starting relay server with config: {:?}", config);

    // Create relay instance
    let relay = Relay::new();

    // Start WebSocket server
    let addr = format!("{}:{}", config.websocket.host, config.websocket.port);
    let listener = TcpListener::bind(&addr).await?;
    info!("WebSocket server listening on {}", addr);

    // Connect to Materialize with TLS
    let mut pg_config = PgConfig::new();
    pg_config
        .host(&config.materialize.host)
        .port(config.materialize.port)
        .dbname(&config.materialize.dbname)
        .user(&config.materialize.user)
        .password(&config.materialize.password)
        .ssl_mode(tokio_postgres::config::SslMode::Require);

    // Create TLS connector with rustls 0.23 API
    let mut root_cert_store = RootCertStore::empty();
    root_cert_store.extend(webpki_roots::TLS_SERVER_ROOTS.iter().cloned());
    
    let tls_config = ClientConfig::builder()
        .with_root_certificates(root_cert_store)
        .with_no_client_auth();
        
    let tls = MakeRustlsConnect::new(tls_config);

    let (client, connection) = pg_config
        .connect(tls)
        .await
        .context("Failed to connect to Materialize")?;

    // Spawn connection handling task
    tokio::spawn(async move {
        if let Err(e) = connection.await {
            error!("Materialize connection error: {}", e);
        }
    });

    // Start subscription using copy_out for streaming
    let copy_stream = client
        .copy_out("COPY (SUBSCRIBE TO live_pnl WITH (SNAPSHOT)) TO STDOUT")
        .await
        .context("Failed to start subscription stream")?;

    // Spawn Materialize stream handling
    let relay_clone = relay.clone();
    tokio::spawn(async move {
        if let Err(e) = relay_clone.handle_materialize_copy_stream(copy_stream).await {
            error!("Materialize stream error: {}", e);
        }
    });

    // Handle WebSocket connections
    while let Ok((stream, _)) = listener.accept().await {
        let ws_stream = tokio_tungstenite::accept_async(stream)
            .await
            .context("Failed to accept WebSocket connection")?;
        
        let relay_clone = relay.clone();
        tokio::spawn(async move {
            if let Err(e) = relay_clone.handle_websocket(ws_stream).await {
                error!("WebSocket error: {}", e);
            }
        });
    }

    Ok(())
}
