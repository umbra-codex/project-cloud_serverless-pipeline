output "main_queue_url" {
  description = "URL of the main queue, the address the ingest function sends each event to."
  value       = aws_sqs_queue.main.url
}

output "main_queue_arn" {
  description = "ARN of the main queue, the resource the consumer's event source mapping reads from."
  value       = aws_sqs_queue.main.arn
}

output "dlq_url" {
  description = "URL of the dead-letter queue, where messages land once the redrive policy gives up on them."
  value       = aws_sqs_queue.dlq.url
}

output "dlq_arn" {
  description = "ARN of the dead-letter queue, the value the main queue's redrive policy points at."
  value       = aws_sqs_queue.dlq.arn
}

output "table_name" {
  description = "Name of the events table, where the consumer writes one row per event."
  value       = aws_dynamodb_table.events.name
}

output "landing_bucket" {
  description = "ID of the landing bucket, the destination SP12's upload commands write objects to."
  value       = aws_s3_bucket.landing.id
}

output "ingest_function_name" {
  description = "Name of the ingest function, the function SP12 invokes to test the S3 path without a bucket upload."
  value       = aws_lambda_function.ingest.function_name
}

output "consumer_function_name" {
  description = "Name of the consumer function, the function SP12 checks the mapping's concurrency cap against and reads the duplicate test's log from."
  value       = aws_lambda_function.consumer.function_name
}
