// SP9 step 1: the consumer handler, run with a stub writer. No account, no
// network. Brief: docs/milestones/SP9.md
import { expect, test } from "bun:test";

import { createHandler, DuplicateEventError } from "../src/consumer/handler";

const NOW = "2026-10-01T12:00:05.000Z";

type Row = { idempotencyKey: string; payload: string; processedAt: string };

function build(behavior: { failOn?: string[]; duplicateOn?: string[]; sdkDuplicateOn?: string[] } = {}) {
  const rows: Row[] = [];

  const handler = createHandler({
    async writeRow(row) {
      if (behavior.duplicateOn?.includes(row.idempotencyKey)) throw new DuplicateEventError();
      if (behavior.sdkDuplicateOn?.includes(row.idempotencyKey)) {
        // The AWS SDK v3 sets the service error's name to the modelled code.
        const err = new Error("The conditional request failed");
        err.name = "ConditionalCheckFailedException";
        throw err;
      }
      if (behavior.failOn?.includes(row.idempotencyKey)) throw new Error("the table is unavailable");
      rows.push(row);
    },
    now: () => NOW,
  });

  return { handler, rows };
}

function record(messageId: string, idempotencyKey: string) {
  return { messageId, body: JSON.stringify({ idempotencyKey, payload: `payload of ${idempotencyKey}` }) };
}

test("writes one row per message, with the message body kept verbatim", async () => {
  const { handler, rows } = build();

  const result = await handler({ Records: [record("m1", "evt-1"), record("m2", "evt-2")] });

  expect(rows).toEqual([
    {
      idempotencyKey: "evt-1",
      payload: JSON.stringify({ idempotencyKey: "evt-1", payload: "payload of evt-1" }),
      processedAt: NOW,
    },
    {
      idempotencyKey: "evt-2",
      payload: JSON.stringify({ idempotencyKey: "evt-2", payload: "payload of evt-2" }),
      processedAt: NOW,
    },
  ]);
  expect(result).toEqual({ batchItemFailures: [] });
});

test("a duplicate is a success: it is not reported as a failure", async () => {
  const { handler, rows } = build({ duplicateOn: ["evt-1"] });

  const result = await handler({ Records: [record("m1", "evt-1"), record("m2", "evt-2")] });

  expect(result).toEqual({ batchItemFailures: [] });
  expect(rows.map((r) => r.idempotencyKey)).toEqual(["evt-2"]);
});

test("the SDK's own duplicate error name is treated the same way", async () => {
  const { handler, rows } = build({ sdkDuplicateOn: ["evt-1"] });

  const result = await handler({ Records: [record("m1", "evt-1")] });

  expect(result).toEqual({ batchItemFailures: [] });
  expect(rows).toHaveLength(0);
});

test("only the message that genuinely failed is reported", async () => {
  const { handler, rows } = build({ failOn: ["evt-2"] });

  const result = await handler({ Records: [record("m1", "evt-1"), record("m2", "evt-2"), record("m3", "evt-3")] });

  expect(result).toEqual({ batchItemFailures: [{ itemIdentifier: "m2" }] });
  expect(rows.map((r) => r.idempotencyKey)).toEqual(["evt-1", "evt-3"]);
});

test("an empty batch reports nothing", async () => {
  const { handler } = build();

  expect(await handler({ Records: [] })).toEqual({ batchItemFailures: [] });
});
