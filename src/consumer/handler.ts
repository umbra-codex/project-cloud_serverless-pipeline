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

export async function handler(
  event: SqsEvent,
): Promise<{ batchItemFailures: BatchItemFailure[] }> {
  console.log(`received ${event.Records.length} message(s)`);
  return { batchItemFailures: [] };
}
