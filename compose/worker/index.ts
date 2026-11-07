import { readFileSync } from "node:fs";
import { createClient } from "redis";
import pg from "pg";

const WORKER_ID = process.env.WORKER_ID ?? `worker-${process.pid}`;
const MAX_DELIVERIES = 5;
const CLAIM_IDLE_MS = 30_000;
const BATCH = 10;

const password = readFileSync(process.env.PG_PASSWORD_FILE!, "utf8").trim();
const pool = new pg.Pool({
  host: process.env.PG_HOST,
  user: process.env.PG_USER,
  database: process.env.PG_DB,
  password,
});

const redis = createClient({ url: process.env.REDIS_URL });
await redis.connect();

try {
  await redis.xGroupCreate("events", "workers", "0", { MKSTREAM: true });
} catch (err) {
  if (!String(err).includes("BUSYGROUP")) throw err;
}

while (true) {
  const claimed = await redis.xAutoClaim("events", "workers", WORKER_ID, CLAIM_IDLE_MS, "0", { COUNT: BATCH });
  const fresh = await redis.xReadGroup("workers", WORKER_ID, [{ key: "events", id: ">" }], { COUNT: BATCH, BLOCK: 5000 });

  for (const msg of [...claimed.messages, ...(fresh?.[0]?.messages ?? [])]) {
    if (!msg) continue;

    try {
      await pool.query(
        `INSERT INTO events (idempotency_key, payload, landed_at)
         VALUES ($1, $2, $3::timestamptz)
         ON CONFLICT DO NOTHING`,
        [msg.message.idempotencyKey, msg.message.payload, msg.message.landedAt]
      );
      await redis.xAck("events", "workers", msg.id);
    } catch {
      const [pending] = await redis.xPendingRange("events", "workers", msg.id, msg.id, 1);
      if (pending.deliveriesCounter >= MAX_DELIVERIES) {
        await redis.xAdd("events-dead", "*", msg.message);
        await redis.xAck("events", "workers", msg.id);
      }
    }
  }
}
