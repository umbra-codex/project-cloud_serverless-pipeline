import { createServer } from "node:http";
import { createClient } from "redis";

const redis = createClient({ url: process.env.REDIS_URL });
await redis.connect();

createServer(async (req, res) => {
  if (req.method !== "POST") {
    res.writeHead(405);
    res.end();
    return;
  }

  let raw = "";
  for await (const chunk of req) raw += chunk;

  let body: any;
  try {
    body = JSON.parse(raw);
  } catch {
    res.writeHead(400);
    res.end();
    return;
  }

  if (typeof body?.idempotencyKey !== "string") {
    res.writeHead(400);
    res.end();
    return;
  }

  await redis.xAdd("events", "*", {
    idempotencyKey: body.idempotencyKey,
    payload: raw,
    landedAt: new Date().toISOString(),
  });

  res.writeHead(202);
  res.end();
}).listen(8081);

