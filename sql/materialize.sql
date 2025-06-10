-- 🔌 Connections

CREATE CONNECTION materialize.public.csr_estuary_connection
TO CONFLUENT SCHEMA REGISTRY (
  PASSWORD = SECRET materialize.public.estuary_api_token,
  URL = 'https://dekaf.estuary-data.com',
  USER = '[user]'
);

CREATE CONNECTION materialize.public.estuary_connection
TO KAFKA (
  BROKER = 'dekaf.estuary-data.com',
  SASL MECHANISMS = 'PLAIN',
  SASL PASSWORD = SECRET materialize.public.estuary_api_token,
  SASL USERNAME = '[user]',
  SECURITY PROTOCOL = 'SASL_SSL'
);

CREATE CONNECTION materialize.public.neon_conn
TO POSTGRES (
  DATABASE = 'neondb',
  HOST = '[host]',
  PASSWORD = SECRET materialize.public.neon_password,
  PORT = 5432,
  SSL MODE = 'require',
  USER = 'neondb_owner'
);

-- 📦 Sources

CREATE SOURCE materialize.public.market_data
IN CLUSTER quickstart
FROM KAFKA CONNECTION materialize.public.estuary_connection (TOPIC = 'sip')
FORMAT AVRO USING CONFLUENT SCHEMA REGISTRY CONNECTION materialize.public.csr_estuary_connection
  SEED KEY SCHEMA '{
    "name": "root.Key",
    "type": "record",
    "fields": [{
      "name": "_flow_key",
      "type": {
        "name": "root.Key.Parts",
        "type": "record",
        "fields": [
          { "name": "p1", "type": "long" },
          { "name": "p2", "type": "string" },
          { "name": "p3", "type": "string" },
          { "name": "p4", "type": "long" }
        ]
      }
    }]
  }'
  VALUE SCHEMA '{
    "name": "root",
    "type": "record",
    "fields": [
      { "name": "ID", "type": "long" },
      { "name": "Symbol", "type": "string" },
      { "name": "Exchange", "type": "string" },
      { "name": "Timestamp", "type": "long" },
      { "name": "Conditions", "type": { "type": "array", "items": "string" } },
      { "name": "Price", "type": "double" },
      { "name": "Size", "type": "long" },
      { "name": "Tape", "type": "string" },
      { "name": "flow_published_at", "type": [
        {
          "name": "root.flow_published_at.RawJSON",
          "type": "record",
          "fields": [{ "name": "json", "type": "string" }]
        },
        "null"
      ]}
    ]
  }'
ENVELOPE UPSERT
EXPOSE PROGRESS AS materialize.public.market_data_progress;

CREATE SOURCE materialize.public.neon_source
IN CLUSTER quickstart
FROM POSTGRES CONNECTION materialize.public.neon_conn (PUBLICATION = 'mz_pub')
FOR TABLES (
  neondb.public.instruments AS materialize.public.instruments,
  neondb.public.trades AS materialize.public.trades
)
EXPOSE PROGRESS AS materialize.public.neon_source_progress;

-- 🧩 Subsources

CREATE SUBSOURCE materialize.public.instruments (
  id pg_catalog.int4 NOT NULL,
  symbol pg_catalog.text NOT NULL,
  name pg_catalog.text,
  CONSTRAINT instruments_pkey PRIMARY KEY (id)
) OF SOURCE materialize.public.neon_source
WITH (EXTERNAL REFERENCE = neondb.public.instruments);

CREATE SUBSOURCE materialize.public.trades (
  id pg_catalog.int4 NOT NULL,
  instrument_id pg_catalog.int4,
  quantity pg_catalog.int4 NOT NULL,
  price pg_catalog.numeric NOT NULL,
  executed_at pg_catalog.timestamp NOT NULL,
  CONSTRAINT trades_pkey PRIMARY KEY (id)
) OF SOURCE materialize.public.neon_source
WITH (EXTERNAL REFERENCE = neondb.public.trades);

CREATE SUBSOURCE materialize.public.market_data_progress (
  partition pg_catalog.numrange NOT NULL,
  "offset" mz_catalog.uint8
) WITH (PROGRESS = true);

CREATE SUBSOURCE materialize.public.neon_source_progress (
  partition pg_catalog.numrange NOT NULL,
  "offset" mz_catalog.uint8
) WITH (PROGRESS = true);

-- 👓 Materialized Views

CREATE MATERIALIZED VIEW materialize.public.latest_market_data
IN CLUSTER quickstart
WITH (REFRESH = ON COMMIT)
AS
  SELECT DISTINCT ON ("Symbol") "Symbol", "Price", "Timestamp"
  FROM materialize.public.market_data
  ORDER BY "Symbol", "Timestamp" DESC;

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
    pg_catalog.sum(t.price * t.quantity) / NULLIF (pg_catalog.sum(t.quantity), 0) AS avg_cost_basis,
    (pg_catalog.sum(t.quantity) * md."Price") - pg_catalog.sum(t.price * t.quantity) AS theoretical_pnl
  FROM materialize.public.trades AS t
  JOIN materialize.public.instruments AS i ON i.id = t.instrument_id
  JOIN materialize.public.latest_market_data AS md ON md."Symbol" = i.symbol
  GROUP BY i.id, i.symbol, md."Price";
