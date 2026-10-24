# The bootstrap module as the root of its own test run: no child module, no
# provider download beyond the one this repository already locks.
mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  mock_resource "aws_s3_bucket" {
    defaults = {
      arn = "arn:aws:s3:::demo-state-bucket"
      id  = "demo-state-bucket"
    }
  }
}

run "bucket" {
  command = plan

  variables {
    region       = "us-east-1"
    state_bucket = "demo-state-bucket"
  }
  assert {
    condition     = aws_s3_bucket.state.bucket == "demo-state-bucket"
    error_message = "the bucket name must come from var.state_bucket, not a literal"
  }

  assert {
    condition     = aws_s3_bucket_versioning.state.versioning_configuration[0].status == "Enabled"
    error_message = "versioning must be Enabled, or a corrupted state has no previous version"
  }

  assert {
    condition     = one([for r in aws_s3_bucket_server_side_encryption_configuration.state.rule : r.apply_server_side_encryption_by_default[0].sse_algorithm]) == "AES256"
    error_message = "the bucket must set SSEAlgorithm AES256"
  }

  assert {
    condition = (
      aws_s3_bucket_public_access_block.state.block_public_acls == true &&
      aws_s3_bucket_public_access_block.state.block_public_policy == true &&
      aws_s3_bucket_public_access_block.state.ignore_public_acls == true &&
      aws_s3_bucket_public_access_block.state.restrict_public_buckets == true
    )
    error_message = "all four public-access settings must be true"
  }
}

# The same configuration with different inputs: if the bucket name were a
# literal equal to the first run's value, this run would still report the first
# name and the assert below would fail.
run "bucket_follows_the_variable" {
  command = plan

  variables {
    region       = "eu-west-1"
    state_bucket = "another-account-state"
  }

  assert {
    condition     = aws_s3_bucket.state.bucket == "another-account-state"
    error_message = "the bucket name must follow var.state_bucket across two runs, not a literal"
  }
}
