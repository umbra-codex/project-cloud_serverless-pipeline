import { GetObjectCommand, S3Client } from "@aws-sdk/client-s3";
import { SendMessageCommand, SQSClient } from "@aws-sdk/client-sqs";

import { createHandler } from "./handler";

const QUEUE_URL = process.env.QUEUE_URL ?? "";

const s3 = new S3Client({});
const sqs = new SQSClient({});

export const handler = createHandler({
  async getObject(bucket, key) {
    const out = await s3.send(new GetObjectCommand({ Bucket: bucket, Key: key }));
    return out.Body!.transformToString();
  },
  async sendMessage(body) {
    await sqs.send(new SendMessageCommand({ QueueUrl: QUEUE_URL, MessageBody: body }));
  },
});
