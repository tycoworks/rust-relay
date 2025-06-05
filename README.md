# Materialize View Relay

A lightweight WebSocket relay server that connects to a Materialize view using `COPY (SUBSCRIBE)`, forwards the streamed row diffs to connected WebSocket clients, and serves as the real-time backend for a Perspective-based grid UI frontend.

## Features

- Connects to Materialize via Postgres wire protocol
- Subscribes to a view using `COPY (SUBSCRIBE TO live_pnl WITH (SNAPSHOT)) TO STDOUT`
- Buffers initial snapshot for late-joining clients
- Forwards row updates to connected WebSocket clients
- Handles client connections and disconnections gracefully
- Supports multiple concurrent WebSocket clients
- Configurable via environment variables

## Prerequisites

- Rust 1.76 or later
- Materialize instance with the `live_pnl` view
- Docker (optional, for containerized deployment)

## Configuration

The relay server is configured using environment variables:

```env
# Materialize connection
MATERIALIZE_HOST=localhost
MATERIALIZE_PORT=6875
MATERIALIZE_DB=materialize
MATERIALIZE_USER=materialize
MATERIALIZE_PASSWORD=materialize

# WebSocket server
WS_HOST=0.0.0.0
WS_PORT=8080

# Logging
RUST_LOG=info
```

## Building

```bash
# Build the binary
cargo build --release

# Or build using Docker
docker build -t rust-relay .
```

## Running

```bash
# Run directly
cargo run --release

# Or run using Docker
docker run -p 8080:8080 \
  -e MATERIALIZE_HOST=your-materialize-host \
  -e MATERIALIZE_PASSWORD=your-password \
  rust-relay
```

## WebSocket Client

The relay server accepts WebSocket connections on the configured port. 

**Upon connection, clients receive:**
1. **Initial Snapshot**: All current rows from the `live_pnl` view
2. **Real-time Updates**: New changes as they occur

**Data Format**: Tab-separated values (TSV), one row per WebSocket message:

```
# Format: timestamp	diff	instrument_id	symbol	net_position	latest_price	market_value	avg_cost_basis	theoretical_pnl
1749079497592	1	42	AAPL	100	145.25	14525.00	140.00	525.00
1749079500000	-1	42	AAPL	100	145.25	14525.00	140.00	525.00
1749079500000	1	42	AAPL	150	145.30	21795.00	143.50	262.50
```

## Building a UI Client

To integrate with a frontend grid (e.g., Perspective):

1. **Connect to WebSocket**: `ws://localhost:8080`
2. **Parse TSV data**: Split each message by tabs to get field values
3. **Handle initial snapshot**: First messages populate the grid's initial state
4. **Process updates**: Subsequent messages update existing rows based on `instrument_id`

**JavaScript Example:**
```javascript
const ws = new WebSocket('ws://localhost:8080');

ws.onmessage = (event) => {
  const fields = event.data.split('\t');
  const [timestamp, diff, instrument_id, symbol, net_position, 
         latest_price, market_value, avg_cost_basis, theoretical_pnl] = fields;
  
  // Update your grid with this row data
  updateGrid({
    instrument_id: parseInt(instrument_id),
    symbol,
    net_position: parseInt(net_position),
    latest_price: parseFloat(latest_price),
    market_value: parseFloat(market_value),
    avg_cost_basis: parseFloat(avg_cost_basis),
    theoretical_pnl: parseFloat(theoretical_pnl)
  });
};
```

## Development

```bash
# Run with debug logging
RUST_LOG=debug cargo run

# Run tests
cargo test
```

## License

MIT 