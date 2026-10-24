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

# SP6 step 1: terraform/s3.tf builds the bucket that receives the events, with
# versioning, encryption, and every public-access block on.
# Brief: docs/milestones/SP6.md

variables {
  alert_email = "alerts@example.com"
  name_prefix = "demo"
}

run "landing_bucket" {
  command = plan

  # Pin the bucket's identifiers so a typed-in name or a reference to the wrong
  # attribute fails instead of matching by luck.
  override_resource {
    target = aws_s3_bucket.landing
    values = {
      id  = "demo-landing-210987654321"
      arn = "arn:aws:s3:::demo-landing-210987654321"
    }
  }

  assert {
    condition     = aws_s3_bucket.landing.bucket == "demo-landing-210987654321"
    error_message = "The bucket must be named <name_prefix>-landing-<account id>, with the account id read from the caller-identity data source (got ${aws_s3_bucket.landing.bucket})."
  }

  assert {
    condition     = aws_s3_bucket.landing.force_destroy == true
    error_message = "Set force_destroy = true: this is a demo stack, so destroy must be able to remove objects it still holds."
  }

  assert {
    condition     = length(aws_s3_bucket_versioning.landing.versioning_configuration) == 1 && one(aws_s3_bucket_versioning.landing.versioning_configuration).status == "Enabled"
    error_message = "Versioning must be on: versioning_configuration { status = \"Enabled\" }."
  }

  assert {
    condition     = aws_s3_bucket_versioning.landing.bucket == "demo-landing-210987654321"
    error_message = "The versioning block must reference the bucket's id attribute, not a typed-in bucket name (got ${aws_s3_bucket_versioning.landing.bucket})."
  }

  assert {
    condition     = length(aws_s3_bucket_server_side_encryption_configuration.landing.rule) == 1 && one(one(aws_s3_bucket_server_side_encryption_configuration.landing.rule).apply_server_side_encryption_by_default).sse_algorithm == "AES256"
    error_message = "Encryption must be SSE-S3: rule { apply_server_side_encryption_by_default { sse_algorithm = \"AES256\" } }."
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.landing.block_public_acls == true && aws_s3_bucket_public_access_block.landing.block_public_policy == true && aws_s3_bucket_public_access_block.landing.ignore_public_acls == true && aws_s3_bucket_public_access_block.landing.restrict_public_buckets == true
    error_message = "All four public-access settings must be true (got ${jsonencode(aws_s3_bucket_public_access_block.landing)})."
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.landing.bucket == "demo-landing-210987654321"
    error_message = "The public-access block must reference the bucket's id attribute (got ${aws_s3_bucket_public_access_block.landing.bucket})."
  }

  assert {
    condition     = lookup(aws_s3_bucket.landing.tags, "Role", "") == "landing" && lookup(aws_s3_bucket.landing.tags, "ManagedBy", "") == "terraform" && lookup(aws_s3_bucket.landing.tags, "Name", "") == "demo-landing-210987654321"
    error_message = "The bucket needs tags Name = <its name>, Role = \"landing\", ManagedBy = \"terraform\" (got ${jsonencode(aws_s3_bucket.landing.tags)})."
  }
}

run "bucket_name_follows_the_prefix" {
  command = plan

  variables {
    name_prefix = "other-stack"
  }

  assert {
    condition     = aws_s3_bucket.landing.bucket == "other-stack-landing-210987654321"
    error_message = "The bucket name must be built from the name_prefix variable and the account id, never typed in (got ${aws_s3_bucket.landing.bucket})."
  }
}
