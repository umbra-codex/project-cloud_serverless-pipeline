export class DuplicateEventError extends Error {
  constructor() {
    super("the idempotency key already exists");
    this.name = "DuplicateEventError";
  }
}

export interface ConsumerDeps {
  writeRow(row: { idempotencyKey: string; payload: string; processedAt: string }): Promise<void>;
  now(): string;
}

export interface SqsRecord {
  messageId: string;
  body: string;
}

export interface SqsEvent {
  Records: SqsRecord[];
}

export interface BatchItemFailure {
  itemIdentifier: string;
}

export function createHandler(deps: ConsumerDeps) {
  return async (event: SqsEvent): Promise<{ batchItemFailures: BatchItemFailure[] }> => {
    const batchItemFailures: BatchItemFailure[] = [];

    for (const record of event.Records) {
      try {
        const body = JSON.parse(record.body);

        if (!body.idempotencyKey) {
          console.error("missing idempotencyKey", record.messageId);
          batchItemFailures.push({ itemIdentifier: record.messageId });
          continue;
        }

        await deps.writeRow({
          idempotencyKey: body.idempotencyKey,
          payload: record.body,
          processedAt: deps.now(),
        });
      } catch (err) {
        if (isDuplicate(err)) continue;
        console.error("failed record", record.messageId, err);
        batchItemFailures.push({ itemIdentifier: record.messageId });
      }
    }

    return { batchItemFailures };
  };
}

function isDuplicate(err: unknown): boolean {
  if (err instanceof DuplicateEventError) return true;
  return (err as { name?: string } | null)?.name === "ConditionalCheckFailedException";
}
