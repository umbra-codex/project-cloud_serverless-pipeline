# No AWS account is involved. Every resource type whose ARN or URL another
# resource validates gets a well-formed default, and the policy document's JSON
# is a valid empty policy (the mock's random text is not JSON).
mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "210987654321"
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::210987654321:role/mock-role"
    }
  }

  mock_resource "aws_lambda_function" {
    defaults = {
      arn        = "arn:aws:lambda:us-east-1:210987654321:function:mock-function"
      invoke_arn = "arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-east-1:210987654321:function:mock-function/invocations"
    }
  }

  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:us-east-1:210987654321:log-group:mock"
    }
  }

  mock_resource "aws_s3_bucket" {
    defaults = {
      arn = "arn:aws:s3:::mock-bucket"
    }
  }

  mock_resource "aws_sqs_queue" {
    defaults = {
      arn = "arn:aws:sqs:us-east-1:210987654321:mock-queue"
      url = "https://sqs.us-east-1.amazonaws.com/210987654321/mock-queue"
    }
  }

  mock_resource "aws_dynamodb_table" {
    defaults = {
      arn = "arn:aws:dynamodb:us-east-1:210987654321:table/mock"
    }
  }
}

mock_provider "archive" {}

# SP7 step 1: terraform/consumer.tf builds the consumer function, its role, its
# log group, and the zip that is deployed.
# Brief: docs/milestones/SP7.md

variables {
  alert_email = "alerts@example.com"
  name_prefix = "demo"
}

run "consumer_function" {
  command = plan

  override_resource {
    target = aws_sqs_queue.main
    values = {
      arn = "arn:aws:sqs:us-east-1:210987654321:demo-main"
      url = "https://sqs.us-east-1.amazonaws.com/210987654321/demo-main"
    }
  }

  override_resource {
    target = aws_dynamodb_table.events
    values = {
      arn = "arn:aws:dynamodb:us-east-1:210987654321:table/demo-events"
    }
  }

  override_resource {
    target = aws_iam_role.consumer
    values = {
      id  = "mock-consumer-role-id"
      arn = "arn:aws:iam::210987654321:role/demo-consumer"
    }
  }

  override_resource {
    target = aws_cloudwatch_log_group.consumer
    values = {
      arn = "arn:aws:logs:us-east-1:210987654321:log-group:/aws/lambda/demo-consumer"
    }
  }

  assert {
    condition     = aws_cloudwatch_log_group.consumer.name == "/aws/lambda/demo-consumer"
    error_message = "The log group must be named /aws/lambda/<name_prefix>-consumer (got ${aws_cloudwatch_log_group.consumer.name})."
  }

  assert {
    condition     = aws_cloudwatch_log_group.consumer.retention_in_days == 14
    error_message = "The log group must keep logs for 14 days: retention_in_days = 14 (got ${aws_cloudwatch_log_group.consumer.retention_in_days})."
  }

  assert {
    condition     = aws_iam_role.consumer.name == "demo-consumer"
    error_message = "The role must be named <name_prefix>-consumer (got ${aws_iam_role.consumer.name})."
  }

  assert {
    condition     = aws_iam_role.consumer.assume_role_policy == data.aws_iam_policy_document.lambda_assume.json
    error_message = "The consumer role must reuse the shared trust policy, not declare its own."
  }

  assert {
    condition     = length(data.aws_iam_policy_document.consumer_permissions.statement) == 3
    error_message = "The permissions document must have exactly three statements (WriteRows, ReadQueue, WriteLogs). Least privilege: nothing else."
  }

  assert {
    condition = length([
      for st in data.aws_iam_policy_document.consumer_permissions.statement : st
      if st.sid == "WriteRows" && st.effect == "Allow" && toset(st.actions) == toset(["dynamodb:PutItem"]) && toset(st.resources) == toset(["arn:aws:dynamodb:us-east-1:210987654321:table/demo-events"])
    ]) == 1
    error_message = "WriteRows must allow dynamodb:PutItem on the events table's arn only. No UpdateItem or DeleteItem: the handler only writes."
  }

  assert {
    condition = length([
      for st in data.aws_iam_policy_document.consumer_permissions.statement : st
      if st.sid == "ReadQueue" && st.effect == "Allow" && toset(st.actions) == toset(["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]) && toset(st.resources) == toset(["arn:aws:sqs:us-east-1:210987654321:demo-main"])
    ]) == 1
    error_message = "ReadQueue must allow sqs:ReceiveMessage, sqs:DeleteMessage, and sqs:GetQueueAttributes on the main queue. The event source mapping polls with this role."
  }

  assert {
    condition = length([
      for st in data.aws_iam_policy_document.consumer_permissions.statement : st
      if st.sid == "WriteLogs" && st.effect == "Allow" && toset(st.actions) == toset(["logs:CreateLogStream", "logs:PutLogEvents"]) && toset(st.resources) == toset(["arn:aws:logs:us-east-1:210987654321:log-group:/aws/lambda/demo-consumer:*"])
    ]) == 1
    error_message = "WriteLogs must allow logs:CreateLogStream and logs:PutLogEvents on the consumer's own log group, arn followed by :*."
  }

  assert {
    condition     = aws_iam_role_policy.consumer.name == "demo-consumer" && aws_iam_role_policy.consumer.role == "mock-consumer-role-id"
    error_message = "The inline policy must be named <name_prefix>-consumer and attach to the role by its id."
  }

  assert {
    condition     = data.archive_file.consumer.type == "zip" && data.archive_file.consumer.source_dir == "${path.module}/../src/consumer/dist" && data.archive_file.consumer.output_path == "${path.module}/build/consumer.zip"
    error_message = "The zip must be built from ../src/consumer/dist into build/consumer.zip, relative to the Terraform folder."
  }

  assert {
    condition     = aws_lambda_function.consumer.function_name == "demo-consumer"
    error_message = "The function must be named <name_prefix>-consumer (got ${aws_lambda_function.consumer.function_name})."
  }

  assert {
    condition     = aws_lambda_function.consumer.role == "arn:aws:iam::210987654321:role/demo-consumer"
    error_message = "The function's role must be the consumer role's arn (got ${aws_lambda_function.consumer.role})."
  }

  assert {
    condition     = aws_lambda_function.consumer.handler == "index.handler" && aws_lambda_function.consumer.runtime == "nodejs24.x" && toset(aws_lambda_function.consumer.architectures) == toset(["arm64"])
    error_message = "The consumer must use handler index.handler, runtime nodejs24.x, and architecture arm64."
  }

  assert {
    condition     = aws_lambda_function.consumer.memory_size == 256 && aws_lambda_function.consumer.timeout == 30
    error_message = "memory_size must be 256 MB and timeout must be 30 seconds, which the queue's 180 second visibility timeout is six times (got ${aws_lambda_function.consumer.memory_size} MB and ${aws_lambda_function.consumer.timeout} s)."
  }

  assert {
    condition     = aws_lambda_function.consumer.filename == data.archive_file.consumer.output_path && aws_lambda_function.consumer.source_code_hash == data.archive_file.consumer.output_base64sha256
    error_message = "The function must deploy the consumer archive's output_path and source_code_hash."
  }

  assert {
    condition     = length(aws_lambda_function.consumer.environment) == 1 && one(aws_lambda_function.consumer.environment).variables["TABLE_NAME"] == "demo-events"
    error_message = "The consumer needs TABLE_NAME set to the events table's name (got ${jsonencode(aws_lambda_function.consumer.environment)})."
  }

  assert {
    condition     = length(aws_lambda_function.consumer.logging_config) == 1 && one(aws_lambda_function.consumer.logging_config).log_format == "JSON" && one(aws_lambda_function.consumer.logging_config).log_group == "/aws/lambda/demo-consumer"
    error_message = "logging_config must set log_format = \"JSON\" and log_group to the consumer log group's name."
  }

  assert {
    condition     = lookup(aws_lambda_function.consumer.tags, "Role", "") == "consumer" && lookup(aws_lambda_function.consumer.tags, "ManagedBy", "") == "terraform"
    error_message = "The function needs tags Name = <its name>, Role = \"consumer\", ManagedBy = \"terraform\" (got ${jsonencode(aws_lambda_function.consumer.tags)})."
  }
}
