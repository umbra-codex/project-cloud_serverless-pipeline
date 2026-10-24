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

variables {
  alert_email = "alerts@example.com"
  name_prefix = "demo"
}

run "queue_and_table_outputs" {
  command = plan

  override_resource {
    target = aws_sqs_queue.main
    values = {
      arn = "arn:aws:sqs:us-east-1:210987654321:demo-main"
      url = "https://sqs.us-east-1.amazonaws.com/210987654321/demo-main"
    }
  }

  override_resource {
    target = aws_sqs_queue.dlq
    values = {
      arn = "arn:aws:sqs:us-east-1:210987654321:demo-dlq"
      url = "https://sqs.us-east-1.amazonaws.com/210987654321/demo-dlq"
    }
  }

  override_resource {
    target = aws_dynamodb_table.events
    values = {
      arn = "arn:aws:dynamodb:us-east-1:210987654321:table/demo-events"
    }
  }

  assert {
    condition     = output.main_queue_url == "https://sqs.us-east-1.amazonaws.com/210987654321/demo-main"
    error_message = "output.main_queue_url must be the main queue's url (got ${output.main_queue_url})."
  }

  assert {
    condition     = output.main_queue_arn == "arn:aws:sqs:us-east-1:210987654321:demo-main"
    error_message = "output.main_queue_arn must be the main queue's arn (got ${output.main_queue_arn})."
  }

  assert {
    condition     = output.dlq_url == "https://sqs.us-east-1.amazonaws.com/210987654321/demo-dlq"
    error_message = "output.dlq_url must be the dead-letter queue's url (got ${output.dlq_url})."
  }

  assert {
    condition     = output.dlq_arn == "arn:aws:sqs:us-east-1:210987654321:demo-dlq"
    error_message = "output.dlq_arn must be the dead-letter queue's arn (got ${output.dlq_arn})."
  }

  assert {
    condition     = output.table_name == "demo-events"
    error_message = "output.table_name must be the table's name (got ${output.table_name})."
  }
}
