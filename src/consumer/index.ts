import {
  ConditionalCheckFailedException,
  DynamoDBClient,
  PutItemCommand,
} from "@aws-sdk/client-dynamodb";

import { createHandler, DuplicateEventError } from "./handler";

const ddb = new DynamoDBClient({});
const TABLE_NAME = process.env.TABLE_NAME!;

export const handler = createHandler({
  async writeRow(row) {
    try {
      await ddb.send(
        new PutItemCommand({
          TableName: TABLE_NAME,
          Item: {
            idempotency_key: { S: row.idempotencyKey },
            payload: { S: row.payload },
            processed_at: { S: row.processedAt },
          },
          ConditionExpression: "attribute_not_exists(idempotency_key)",
        }),
      );
    } catch (err) {
      if (err instanceof ConditionalCheckFailedException) throw new DuplicateEventError();
      throw err;
    }
  },

  now: () => new Date().toISOString(),
});
