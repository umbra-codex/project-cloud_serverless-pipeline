// SP9 step 2: the ingest handler settles the idempotency key once, before the
// message reaches the queue. Brief: docs/milestones/SP9.md
import { expect, test } from "bun:test";

import { createHandler } from "../src/ingest/handler";

const BUCKET = "demo-landing-210987654321";

function build(body: string) {
  const sent: string[] = [];
  const handler = createHandler({
    async getObject() {
      return body;
    },
    async sendMessage(message) {
      sent.push(message);
    },
  });
  return { handler, sent };
}

function event(key: string) {
  return { Records: [{ eventTime: "2026-10-01T12:00:00.000Z", s3: { bucket: { name: BUCKET }, object: { key } } }] };
}

test("uses the object key when the body has no idempotency key", async () => {
  const { handler, sent } = build('{"payload":"hello"}');

  await handler(event("uploads/evt-1.json"));

  expect(JSON.parse(sent[0]!).idempotencyKey).toBe("uploads/evt-1.json");
});

test("keeps the key the body carries", async () => {
  const { handler, sent } = build('{"payload":"hello","idempotencyKey":"evt-001"}');

  await handler(event("uploads/anything.json"));

  expect(JSON.parse(sent[0]!).idempotencyKey).toBe("evt-001");
});

test("the same object key twice produces the same idempotency key", async () => {
  const { handler, sent } = build('{"payload":"hello"}');

  await handler(event("evt-1.json"));
  await handler(event("evt-1.json"));

  const keys = sent.map((m) => JSON.parse(m).idempotencyKey);
  expect(keys).toEqual(["evt-1.json", "evt-1.json"]);
});
