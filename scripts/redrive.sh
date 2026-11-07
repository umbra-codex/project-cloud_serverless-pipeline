#!/usr/bin/env bash
set -euo pipefail

DLQ_URL=$(tofu -chdir=terraform output -raw dlq_url)
DLQ_ARN=$(tofu -chdir=terraform output -raw dlq_arn)
MAIN_ARN=$(tofu -chdir=terraform output -raw main_queue_arn)

count_dlq() {
  aws sqs get-queue-attributes \
    --queue-url "$DLQ_URL" \
    --attribute-names ApproximateNumberOfMessages \
    --query 'Attributes.ApproximateNumberOfMessages' \
    --output text
}

remaining=$(count_dlq)
if [ "$remaining" -eq 0 ]; then
  echo "nothing to move: the dead-letter queue is empty"
  exit 0
fi

echo "moving $remaining message(s) back to the main queue"
aws sqs start-message-move-task \
  --source-arn "$DLQ_ARN" \
  --destination-arn "$MAIN_ARN" >/dev/null

for i in $(seq 1 60); do
  remaining=$(count_dlq)
  echo "poll $i: $remaining left"
  if [ "$remaining" -eq 0 ]; then
    break
  fi
  sleep 2
done

remaining=$(count_dlq)
if [ "$remaining" -ne 0 ]; then
  echo "$remaining message(s) still in the dead-letter queue" >&2
  echo "read them with: aws sqs receive-message --queue-url \"$DLQ_URL\" --max-number-of-messages 10" >&2
  exit 1
fi

echo "redrive complete: 0 message(s) left in the dead-letter queue"
