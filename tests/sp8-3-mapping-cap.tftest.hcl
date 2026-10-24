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

# SP8 step 3: the event source mapping has its own concurrency cap, which is the
# cap that actually throttles how much work the queue hands the consumer.
# Brief: docs/milestones/SP8.md

variables {
  alert_email = "alerts@example.com"
  name_prefix = "demo"
}

run "mapping_cap" {
  command = plan

  assert {
    condition     = length(aws_lambda_event_source_mapping.consumer.scaling_config) == 1 && one(aws_lambda_event_source_mapping.consumer.scaling_config).maximum_concurrency == 2
    error_message = "The mapping needs scaling_config { maximum_concurrency = var.maximum_concurrency }, which defaults to 2 (got ${jsonencode(aws_lambda_event_source_mapping.consumer.scaling_config)})."
  }
}

run "mapping_cap_follows_the_variable" {
  command = plan

  variables {
    maximum_concurrency = 4
  }

  assert {
    condition     = one(aws_lambda_event_source_mapping.consumer.scaling_config).maximum_concurrency == 4
    error_message = "maximum_concurrency must come from the variable, not a typed-in number (got ${jsonencode(aws_lambda_event_source_mapping.consumer.scaling_config)})."
  }
}
