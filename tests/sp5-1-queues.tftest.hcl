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

run "queues_and_redrive_policy" {
  command = plan

  variables {
    name_prefix = "demo"
  }

  # The mock gives every queue the same ARN and URL, so a policy that pointed at
  # the wrong queue would still pass. Pin a distinct pair for each one.
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

  assert {
    condition     = aws_sqs_queue.dlq.name == "demo-dlq"
    error_message = "The dead-letter queue must be named <name_prefix>-dlq (got ${aws_sqs_queue.dlq.name})."
  }

  assert {
    condition     = aws_sqs_queue.dlq.message_retention_seconds == 1209600
    error_message = "The dead-letter queue must keep messages for 1209600 seconds (14 days, the maximum), so there is time to read them (got ${aws_sqs_queue.dlq.message_retention_seconds})."
  }

  assert {
    condition     = aws_sqs_queue.dlq.sqs_managed_sse_enabled == true
    error_message = "The dead-letter queue must use SQS-managed encryption: sqs_managed_sse_enabled = true."
  }

  assert {
    condition     = aws_sqs_queue.main.name == "demo-main"
    error_message = "The main queue must be named <name_prefix>-main (got ${aws_sqs_queue.main.name})."
  }

  assert {
    condition     = aws_sqs_queue.main.visibility_timeout_seconds == 180
    error_message = "The main queue's visibility timeout must be 180 seconds, six times the consumer's 30 second timeout (got ${aws_sqs_queue.main.visibility_timeout_seconds})."
  }

  assert {
    condition     = aws_sqs_queue.main.sqs_managed_sse_enabled == true
    error_message = "The main queue must use SQS-managed encryption: sqs_managed_sse_enabled = true."
  }

  assert {
    condition     = jsondecode(aws_sqs_queue.main.redrive_policy).deadLetterTargetArn == "arn:aws:sqs:us-east-1:210987654321:demo-dlq"
    error_message = "redrive_policy.deadLetterTargetArn must reference the dead-letter queue's arn, not the main queue's (got ${jsondecode(aws_sqs_queue.main.redrive_policy).deadLetterTargetArn})."
  }

  assert {
    condition     = jsondecode(aws_sqs_queue.main.redrive_policy).maxReceiveCount == 5
    error_message = "redrive_policy.maxReceiveCount must be 5, the number of failed deliveries before a message moves to the dead-letter queue (got ${jsondecode(aws_sqs_queue.main.redrive_policy).maxReceiveCount})."
  }

  assert {
    condition     = lookup(aws_sqs_queue.main.tags, "Name", "") == "demo-main" && lookup(aws_sqs_queue.main.tags, "Role", "") == "queue" && lookup(aws_sqs_queue.main.tags, "ManagedBy", "") == "terraform"
    error_message = "The main queue needs tags Name = <its name>, Role = \"queue\", ManagedBy = \"terraform\" (got ${jsonencode(aws_sqs_queue.main.tags)})."
  }

  assert {
    condition     = lookup(aws_sqs_queue.dlq.tags, "Name", "") == "demo-dlq" && lookup(aws_sqs_queue.dlq.tags, "Role", "") == "dead-letter" && lookup(aws_sqs_queue.dlq.tags, "ManagedBy", "") == "terraform"
    error_message = "The dead-letter queue needs tags Name = <its name>, Role = \"dead-letter\", ManagedBy = \"terraform\" (got ${jsonencode(aws_sqs_queue.dlq.tags)})."
  }
}

run "names_follow_the_prefix" {
  command = plan

  variables {
    name_prefix = "other-stack"
  }

  assert {
    condition     = aws_sqs_queue.main.name == "other-stack-main" && aws_sqs_queue.dlq.name == "other-stack-dlq"
    error_message = "Both queue names must come from the name_prefix variable, not from a typed-in string (got ${aws_sqs_queue.main.name} and ${aws_sqs_queue.dlq.name})."
  }
}
