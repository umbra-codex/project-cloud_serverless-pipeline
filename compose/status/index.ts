import { createServer } from "node:http";
import { readFileSync } from "node:fs";
import { createClient } from "redis";
import pg from "pg";

const redis = createClient({ url: process.env.REDIS_URL });
await redis.connect();

const password = readFileSync(process.env.PG_PASSWORD_FILE!, "utf8").trim();
const pool = new pg.Pool({
  host: process.env.PG_HOST,
  user: process.env.PG_USER,
  database: process.env.PG_DB,
  password,
});

createServer(async (req, res) => {
  if (req.method !== "GET") {
    res.writeHead(405);
    res.end();
    return;
  }

  const [{ rows }, depth] = await Promise.all([
    pool.query("SELECT count(*)::int AS n FROM events"),
    redis.xLen("events-dead"),
  ]);

  res.writeHead(200, { "content-type": "application/json" });
  res.end(JSON.stringify({ processed: rows[0].n, deadLetterDepth: depth }));
}).listen(8080);
