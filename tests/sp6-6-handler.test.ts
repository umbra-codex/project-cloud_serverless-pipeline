// SP6 step 6: the ingest handler, run with stub AWS clients. No account, no
// network. Brief: docs/milestones/SP6.md
import { expect, test } from "bun:test";

import { createHandler } from "../src/ingest/handler";

const BUCKET = "demo-landing-210987654321";

function build(objects: Record<string, string>) {
  const sent: string[] = [];
  const reads: { bucket: string; key: string }[] = [];

  const handler = createHandler({
    async getObject(bucket, key) {
      reads.push({ bucket, key });
      const body = objects[key];
      if (body === undefined) throw new Error(`no stub object for ${key}`);
      return body;
    },
    async sendMessage(body) {
      sent.push(body);
    },
  });

  return { handler, sent, reads };
}

function s3Event(key: string, eventTime = "2026-10-01T12:00:00.000Z") {
  return { Records: [{ eventTime, s3: { bucket: { name: BUCKET }, object: { key } } }] };
}

test("stamps the landing time the event carries, not the clock", async () => {
  const { handler, sent } = build({ "evt-1.json": '{"payload":"hello"}' });

  await handler(s3Event("evt-1.json"));

  expect(sent).toHaveLength(1);
  const message = JSON.parse(sent[0]!);
  expect(message.landedAt).toBe("2026-10-01T12:00:00.000Z");
  expect(message.payload).toBe("hello");
});

test("reads the object with the key the event names, decoded", async () => {
  const { handler, reads } = build({ "bench/evt 1.json": '{"payload":"hello"}' });

  await handler(s3Event("bench%2Fevt+1.json"));

  expect(reads).toEqual([{ bucket: BUCKET, key: "bench/evt 1.json" }]);
});

test("sends one message per record and reports how many", async () => {
  const { handler, sent } = build({
    "a.json": '{"payload":"a"}',
    "b.json": '{"payload":"b"}',
  });

  const result = await handler({
    Records: [
      { eventTime: "2026-10-01T12:00:00.000Z", s3: { bucket: { name: BUCKET }, object: { key: "a.json" } } },
      { eventTime: "2026-10-01T12:00:01.000Z", s3: { bucket: { name: BUCKET }, object: { key: "b.json" } } },
    ],
  });

  expect(sent).toHaveLength(2);
  expect(result).toEqual({ sent: 2 });
  expect(JSON.parse(sent[1]!).landedAt).toBe("2026-10-01T12:00:01.000Z");
});

test("rejects a body that is not a JSON object", async () => {
  const { handler, sent } = build({
    "list.json": "[1,2]",
    "text.json": '"hello"',
    "null.json": "null",
  });

  await expect(handler(s3Event("list.json"))).rejects.toThrow();
  await expect(handler(s3Event("text.json"))).rejects.toThrow();
  await expect(handler(s3Event("null.json"))).rejects.toThrow();
  expect(sent).toHaveLength(0);
});
