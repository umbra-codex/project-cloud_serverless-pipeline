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
}

run "events_table" {
  command = plan

  variables {
    name_prefix = "demo"
  }

  assert {
    condition     = aws_dynamodb_table.events.name == "demo-events"
    error_message = "The table must be named <name_prefix>-events (got ${aws_dynamodb_table.events.name})."
  }

  assert {
    condition     = aws_dynamodb_table.events.billing_mode == "PAY_PER_REQUEST"
    error_message = "The table must use on-demand billing: billing_mode = \"PAY_PER_REQUEST\" (got ${aws_dynamodb_table.events.billing_mode})."
  }

  assert {
    condition     = aws_dynamodb_table.events.hash_key == "idempotency_key"
    error_message = "The partition key must be idempotency_key, the value the conditional write checks (got ${aws_dynamodb_table.events.hash_key})."
  }

  assert {
    condition     = length(aws_dynamodb_table.events.attribute) == 1 && one(aws_dynamodb_table.events.attribute).name == "idempotency_key" && one(aws_dynamodb_table.events.attribute).type == "S"
    error_message = "The table needs exactly one attribute definition: name = \"idempotency_key\", type = \"S\"."
  }

  assert {
    condition     = length(aws_dynamodb_table.events.point_in_time_recovery) == 1 && one(aws_dynamodb_table.events.point_in_time_recovery).enabled == true
    error_message = "Point-in-time recovery must be on: point_in_time_recovery { enabled = true }."
  }

  assert {
    condition     = length(aws_dynamodb_table.events.server_side_encryption) == 1 && one(aws_dynamodb_table.events.server_side_encryption).enabled == true
    error_message = "Server-side encryption must be on: server_side_encryption { enabled = true }."
  }

  assert {
    condition     = lookup(aws_dynamodb_table.events.tags, "Name", "") == "demo-events" && lookup(aws_dynamodb_table.events.tags, "Role", "") == "events" && lookup(aws_dynamodb_table.events.tags, "ManagedBy", "") == "terraform"
    error_message = "The table needs tags Name = <its name>, Role = \"events\", ManagedBy = \"terraform\" (got ${jsonencode(aws_dynamodb_table.events.tags)})."
  }
}

run "table_name_follows_the_prefix" {
  command = plan

  variables {
    name_prefix = "other-stack"
  }

  assert {
    condition     = aws_dynamodb_table.events.name == "other-stack-events"
    error_message = "The table name must come from the name_prefix variable, not from a typed-in string (got ${aws_dynamodb_table.events.name})."
  }
}
