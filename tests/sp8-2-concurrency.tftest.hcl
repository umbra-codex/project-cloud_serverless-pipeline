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

# SP8 step 2: both functions carry the reserved-concurrency cap, and the value
# comes from a variable so it can be turned off.
# Brief: docs/milestones/SP8.md

variables {
  alert_email = "alerts@example.com"
  name_prefix = "demo"
}

run "reserved_concurrency_set" {
  command = plan

  variables {
    reserved_concurrency = 5
  }

  assert {
    condition     = aws_lambda_function.ingest.reserved_concurrent_executions == 5
    error_message = "The ingest function must carry reserved_concurrency: reserved_concurrent_executions = var.reserved_concurrency (got ${aws_lambda_function.ingest.reserved_concurrent_executions})."
  }

  assert {
    condition     = aws_lambda_function.consumer.reserved_concurrent_executions == 5
    error_message = "The consumer function must carry reserved_concurrency too (got ${aws_lambda_function.consumer.reserved_concurrent_executions})."
  }
}

run "reserved_concurrency_off_by_default" {
  command = plan

  assert {
    condition     = aws_lambda_function.ingest.reserved_concurrent_executions == -1 && aws_lambda_function.consumer.reserved_concurrent_executions == -1
    error_message = "reserved_concurrency must default to -1, which means no reservation. An account whose Lambda limit is 10 cannot reserve concurrency at all (got ${aws_lambda_function.ingest.reserved_concurrent_executions} and ${aws_lambda_function.consumer.reserved_concurrent_executions})."
  }
}
