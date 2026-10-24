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

# SP6 step 2: terraform/trigger.tf gives S3 permission to invoke the function and
# adds the bucket notification that makes it happen.
# Brief: docs/milestones/SP6.md

variables {
  alert_email = "alerts@example.com"
  name_prefix = "demo"
}

run "s3_can_invoke_the_function" {
  command = plan

  override_resource {
    target = aws_s3_bucket.landing
    values = {
      id  = "demo-landing-210987654321"
      arn = "arn:aws:s3:::demo-landing-210987654321"
    }
  }

  override_resource {
    target = aws_lambda_function.ingest
    values = {
      arn = "arn:aws:lambda:us-east-1:210987654321:function:demo-ingest"
    }
  }

  assert {
    condition     = aws_lambda_permission.s3_invoke.statement_id == "AllowS3Invoke"
    error_message = "The permission's statement_id must be AllowS3Invoke (got ${aws_lambda_permission.s3_invoke.statement_id})."
  }

  assert {
    condition     = aws_lambda_permission.s3_invoke.action == "lambda:InvokeFunction"
    error_message = "The permission must allow lambda:InvokeFunction (got ${aws_lambda_permission.s3_invoke.action})."
  }

  assert {
    condition     = aws_lambda_permission.s3_invoke.principal == "s3.amazonaws.com"
    error_message = "The permission's principal must be s3.amazonaws.com (got ${aws_lambda_permission.s3_invoke.principal})."
  }

  assert {
    condition     = aws_lambda_permission.s3_invoke.source_arn == "arn:aws:s3:::demo-landing-210987654321"
    error_message = "The permission's source_arn must be the landing bucket's arn, so only this bucket may invoke the function (got ${aws_lambda_permission.s3_invoke.source_arn})."
  }

  assert {
    condition     = aws_lambda_permission.s3_invoke.function_name == "demo-ingest"
    error_message = "The permission must name the ingest function, from the function's function_name attribute (got ${aws_lambda_permission.s3_invoke.function_name})."
  }

  assert {
    condition     = length(aws_s3_bucket_notification.landing.lambda_function) == 1
    error_message = "The notification needs exactly one lambda_function block."
  }

  assert {
    condition     = one(aws_s3_bucket_notification.landing.lambda_function).lambda_function_arn == "arn:aws:lambda:us-east-1:210987654321:function:demo-ingest"
    error_message = "The notification must invoke the ingest function's arn attribute (got ${one(aws_s3_bucket_notification.landing.lambda_function).lambda_function_arn})."
  }

  assert {
    condition     = toset(one(aws_s3_bucket_notification.landing.lambda_function).events) == toset(["s3:ObjectCreated:*"])
    error_message = "The notification must fire on s3:ObjectCreated:* (got ${jsonencode(one(aws_s3_bucket_notification.landing.lambda_function).events)})."
  }

  assert {
    condition     = aws_s3_bucket_notification.landing.bucket == "demo-landing-210987654321"
    error_message = "The notification must reference the bucket's id attribute (got ${aws_s3_bucket_notification.landing.bucket})."
  }
}
