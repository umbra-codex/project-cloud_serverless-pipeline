resource "aws_sqs_queue" "dlq" {
  name                      = "${var.name_prefix}-dlq"
  message_retention_seconds = 1209600
  sqs_managed_sse_enabled   = true

  tags = {
    Name      = "${var.name_prefix}-dlq"
    Role      = "dead-letter"
    ManagedBy = "terraform"
  }
}

resource "aws_sqs_queue" "main" {
  name                       = "${var.name_prefix}-main"
  visibility_timeout_seconds = 180
  sqs_managed_sse_enabled    = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn,
    maxReceiveCount     = 5,
  })

  tags = {
    Name      = "${var.name_prefix}-main"
    Role      = "queue"
    ManagedBy = "terraform"
  }
}
