resource "aws_cloudwatch_log_group" "consumer" {
  name              = "/aws/lambda/${var.name_prefix}-consumer"
  retention_in_days = 14

  tags = {
    Name      = "${var.name_prefix}-consumer"
    Role      = "consumer"
    ManagedBy = "terraform"
  }
}

resource "aws_iam_role" "consumer" {
  name               = "${var.name_prefix}-consumer"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json

  tags = {
    Name      = "${var.name_prefix}-consumer"
    Role      = "consumer"
    ManagedBy = "terraform"
  }
}

data "aws_iam_policy_document" "consumer_permissions" {
  statement {
    sid       = "WriteRows"
    effect    = "Allow"
    actions   = ["dynamodb:PutItem"]
    resources = [aws_dynamodb_table.events.arn]
  }

  statement {
    sid       = "ReadQueue"
    effect    = "Allow"
    actions   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
    resources = [aws_sqs_queue.main.arn]
  }

  statement {
    sid       = "WriteLogs"
    effect    = "Allow"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.consumer.arn}:*"]
  }
}

resource "aws_iam_role_policy" "consumer" {
  name   = "${var.name_prefix}-consumer"
  role   = aws_iam_role.consumer.id
  policy = data.aws_iam_policy_document.consumer_permissions.json
}

data "archive_file" "consumer" {
  type        = "zip"
  source_dir  = "${path.module}/../src/consumer/dist"
  output_path = "${path.module}/build/consumer.zip"
}

resource "aws_lambda_function" "consumer" {
  function_name                  = "${var.name_prefix}-consumer"
  role                           = aws_iam_role.consumer.arn
  handler                        = "index.handler"
  runtime                        = "nodejs24.x"
  architectures                  = ["arm64"]
  memory_size                    = 256
  timeout                        = 30
  filename                       = data.archive_file.consumer.output_path
  source_code_hash               = data.archive_file.consumer.output_base64sha256
  reserved_concurrent_executions = var.reserved_concurrency


  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.events.name
    }
  }

  logging_config {
    log_format = "JSON"
    log_group  = aws_cloudwatch_log_group.consumer.name
  }

  depends_on = [aws_iam_role_policy.consumer]

  tags = {
    Name      = "${var.name_prefix}-consumer"
    Role      = "consumer"
    ManagedBy = "terraform"
  }
}
