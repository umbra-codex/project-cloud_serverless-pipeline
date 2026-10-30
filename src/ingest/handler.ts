export interface IngestDeps {
  getObject(bucket: string, key: string): Promise<string>;
  sendMessage(body: string): Promise<void>;
}

export interface S3Event {
  Records: { eventTime: string; s3: { bucket: { name: string }; object: { key: string } } }[];
}

export function createHandler(deps: IngestDeps) {
  return async (event: S3Event): Promise<{ sent: number }> => {
    let sent = 0;

    for (const record of event.Records) {
      const bucket = record.s3.bucket.name;
      const key = decodeURIComponent(record.s3.object.key.replace(/\+/g, " "));

      const body = await deps.getObject(bucket, key);
      const parsed: unknown = JSON.parse(body);

      if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) {
        throw new Error(`object s3://${bucket}/${key} is not a JSON object`);
      }

      await deps.sendMessage(
        JSON.stringify({ ...(parsed as Record<string, unknown>), landedAt: record.eventTime }),
      );
      sent += 1;
    }

    return { sent };
  };
}
