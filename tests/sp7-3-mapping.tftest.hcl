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

# SP7 step 2: terraform/mapping.tf connects the queue to the consumer, with
# partial-batch reporting on so one bad message does not fail the batch.
# Brief: docs/milestones/SP7.md

variables {
  alert_email = "alerts@example.com"
  name_prefix = "demo"
}

run "event_source_mapping" {
  command = plan

  override_resource {
    target = aws_sqs_queue.main
    values = {
      arn = "arn:aws:sqs:us-east-1:210987654321:demo-main"
      url = "https://sqs.us-east-1.amazonaws.com/210987654321/demo-main"
    }
  }

  override_resource {
    target = aws_lambda_function.consumer
    values = {
      arn = "arn:aws:lambda:us-east-1:210987654321:function:demo-consumer"
    }
  }

  assert {
    condition     = aws_lambda_event_source_mapping.consumer.event_source_arn == "arn:aws:sqs:us-east-1:210987654321:demo-main"
    error_message = "The mapping must read the main queue, by its arn attribute (got ${aws_lambda_event_source_mapping.consumer.event_source_arn})."
  }

  assert {
    condition     = aws_lambda_event_source_mapping.consumer.function_name == "arn:aws:lambda:us-east-1:210987654321:function:demo-consumer"
    error_message = "The mapping must invoke the consumer function, by its arn attribute (got ${aws_lambda_event_source_mapping.consumer.function_name})."
  }

  assert {
    condition     = aws_lambda_event_source_mapping.consumer.batch_size == 10
    error_message = "batch_size must be 10 (got ${aws_lambda_event_source_mapping.consumer.batch_size})."
  }

  assert {
    condition     = toset(aws_lambda_event_source_mapping.consumer.function_response_types) == toset(["ReportBatchItemFailures"])
    error_message = "function_response_types must be [\"ReportBatchItemFailures\"], so the handler's batchItemFailures list decides which messages are retried (got ${jsonencode(aws_lambda_event_source_mapping.consumer.function_response_types)})."
  }
}
