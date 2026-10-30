resource "aws_lambda_event_source_mapping" "consumer" {
  event_source_arn        = aws_sqs_queue.main.arn
  function_name           = aws_lambda_function.consumer.arn
  batch_size              = 10
  function_response_types = ["ReportBatchItemFailures"]

  scaling_config {
    maximum_concurrency = var.maximum_concurrency
  }

  tags = {
    Name      = "${var.name_prefix}-consumer-mapping"
    Role      = "consumer-mapping"
    ManagedBy = "terraform"
  }
}
