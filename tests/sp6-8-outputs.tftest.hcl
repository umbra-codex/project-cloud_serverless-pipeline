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

# SP6 step 8: the two values the SP12 commands read with tofu output.
# Brief: docs/milestones/SP6.md

variables {
  alert_email = "alerts@example.com"
  name_prefix = "demo"
}

run "bucket_and_function_outputs" {
  command = plan

  override_resource {
    target = aws_s3_bucket.landing
    values = {
      id  = "demo-landing-210987654321"
      arn = "arn:aws:s3:::demo-landing-210987654321"
    }
  }

  assert {
    condition     = output.landing_bucket == "demo-landing-210987654321"
    error_message = "output.landing_bucket must be the bucket's id (got ${output.landing_bucket})."
  }

  assert {
    condition     = output.ingest_function_name == "demo-ingest"
    error_message = "output.ingest_function_name must be the ingest function's name (got ${output.ingest_function_name})."
  }
}
