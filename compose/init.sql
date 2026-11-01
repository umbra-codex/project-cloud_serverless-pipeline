CREATE TABLE IF NOT EXISTS events (
    idempotency_key TEXT PRIMARY KEY,
    payload JSONB NOT NULL,
    landed_at TIMESTAMPTZ NOT NULL,
    processed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
