**Project Title:** Materialize View Relay for Real-Time Grid UI

**Overview:**
This project aims to build a lightweight WebSocket relay server that connects to a Materialize view using `SUBSCRIBE`, forwards the streamed row diffs to connected WebSocket clients, and serves as the real-time backend for a Perspective-based grid UI frontend.

This proof-of-concept exists to answer a focused architectural question:

> Can modern stream processors (like Materialize) reliably power real-time front-end applications?

The goal is to build the minimal viable implementation of that data pipe — no full product, no abstractions, just clarity.

---

**Context and Current Architecture:**

* **Market data source:** Alpaca WebSocket → Estuary → Kafka topic
* **Reference data:** Postgres database (Neon or similar), read-only
* **Stream processor:** Materialize (hosted)

  * Joins Alpaca stream and Postgres tables
  * Produces a live view called `live_pnl`
* **Frontend UI:** Perspective grid (in a Vite-based frontend)

  * Needs row-level updates in real time

Currently:

* Ingest is working (via Estuary)
* The live Materialize view `live_pnl` is correct
* There is no working way to **push that data into the frontend grid**

---

**This Project (Relay Server):**

This project will:

* Connect to Materialize via Postgres wire protocol
* Issue a `COPY (SUBSCRIBE TO live_pnl WITH (SNAPSHOT)) TO STDOUT` statement
* Parse streamed row diffs (tab-separated values)
* Buffer initial snapshot for late-joining clients
* Forward each update via WebSocket to any connected frontend clients

---

**Why SUBSCRIBE instead of SINK → Kafka?**

* Lower latency
* Avoids unnecessary infra (Kafka fanout, pub/sub brokers)
* Closer to Hasura-style developer ergonomics

> Note: For large-scale multi-client or multi-region delivery, this would be replaced with a SINK → Kafka → Redis/NATS/etc. fanout path. This project exists to model the initial architecture.

---

**Relay Server Technical Details:**

* **Language:** Rust (mandatory)

  * Use `tokio-postgres` despite limitations
  * If `tokio-postgres` fails to support the required behavior, the relay may need to use `simple_query` mode or invoke `psql` via subprocess as a fallback
* **Target platform:** Railway (already verified to support WebSocket servers)
* **Input:**

  * Connect to Materialize
  * Run `COPY (SUBSCRIBE TO live_pnl WITH (SNAPSHOT)) TO STDOUT`
  * Stream newline-delimited tab-separated values
  * Buffer initial snapshot in memory
* **Output:**

  * WebSocket server that:

    * Accepts connections from Perspective clients
    * Sends initial snapshot to new clients (current state)
    * Pushes each TSV row to all connected clients as real-time updates
    * Optionally batches updates in the future
* **Security:** None for now (PoC); WS endpoint is public

---

**Materialized View Definition:**

```sql
CREATE MATERIALIZED VIEW materialize.public.live_pnl
    IN CLUSTER quickstart
    WITH (REFRESH = ON COMMIT)
    AS
        SELECT
            i.id AS instrument_id,
            i.symbol,
            pg_catalog.sum(t.quantity) AS net_position,
            md."Price" AS latest_price,
            pg_catalog.sum(t.quantity) * md."Price" AS market_value,
            pg_catalog.sum(t.price * t.quantity) / NULLIF (pg_catalog.sum(t.quantity), 0)
                AS avg_cost_basis,
            (pg_catalog.sum(t.quantity) * md."Price") - pg_catalog.sum(t.price * t.quantity)
                AS theoretical_pnl
        FROM
            materialize.public.trades AS t
                JOIN materialize.public.instruments AS i ON i.id = t.instrument_id
                JOIN materialize.public.latest_market_data AS md ON md."Symbol" = i.symbol
        GROUP BY i.id, i.symbol, md."Price";
```

---

**WebSocket Message Format:**

Each row from Materialize will be forwarded as-is to clients as tab-separated values.

**New clients receive:**
1. Initial snapshot (all current rows)
2. Real-time updates (as they occur)

Example:

```
timestamp	diff	instrument_id	symbol	net_position	latest_price	market_value	avg_cost_basis	theoretical_pnl
1749079497592	1	42	AAPL	100	145.25	14525.00	140.00	525.00
```

No batching, wrapping, or transformation is performed.

---

**Implementation Considerations:**

* **TLS Configuration:** Use `tokio-postgres-rustls` with compatible versions to avoid dependency conflicts
* **Late Joining Clients:** Requires snapshot buffering architecture to provide current state to new connections
* **Data Format:** Materialize COPY format outputs TSV, not JSON as initially assumed
* **Streaming Method:** Use `copy_out()` for continuous streaming rather than `simple_query()`

---

**No Reinventing the Wheel**

This is a POC relay. Do not implement:

* Message batching
* Custom diffing logic
* Row filtering
* Application-layer protocols

Use off-the-shelf crates wherever possible:

* `tokio-postgres`
* `tokio-tungstenite`
* `serde_json`
* `dotenv` or `envy` for config

---

**Frontend Assumptions:**

* The Perspective grid will connect to the relay's WS endpoint
* Vite project will:

  * Connect via WebSocket
  * Update grid in real time using row updates

---

**Product Opportunity / Future Work:**

If this relay proves useful:

* Wrap the logic in a GraphQL-like interface

  * One `livePnL` subscription = `SUBSCRIBE TO live_pnl`
  * Automatic schema mapping
* Add role-based row filtering
* Support multiple backends (e.g. RisingWave, ClickHouse, Postgres logical replication)
* Push updates over SSE or gRPC as well
* Serve many concurrent clients using Redis Streams or NATS for pub/sub

This may become an open-source SDK or a managed backend for streaming dashboards.

---

**Cursor Usage Notes:**

* This file (spec.md) should be tracked in Cursor
* Implementation should occur in the same workspace, generating `main.rs`, `Cargo.toml`, `Dockerfile`, and any relay config needed
* Cursor should synthesize the Postgres `SUBSCRIBE` connection and WS push handling
* Avoid overengineering: **no custom protocols, envelopes, filters, or batching logic.**
