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

# SP6 step 4: terraform/ingest.tf builds the ingest function, its role, its log
# group, and the zip that is deployed.
# Brief: docs/milestones/SP6.md

variables {
  alert_email = "alerts@example.com"
  name_prefix = "demo"
}

run "ingest_function" {
  command = plan

  override_resource {
    target = aws_s3_bucket.landing
    values = {
      id  = "demo-landing-210987654321"
      arn = "arn:aws:s3:::demo-landing-210987654321"
    }
  }

  override_resource {
    target = aws_sqs_queue.main
    values = {
      arn = "arn:aws:sqs:us-east-1:210987654321:demo-main"
      url = "https://sqs.us-east-1.amazonaws.com/210987654321/demo-main"
    }
  }

  override_resource {
    target = aws_iam_role.ingest
    values = {
      id  = "mock-ingest-role-id"
      arn = "arn:aws:iam::210987654321:role/demo-ingest"
    }
  }

  override_resource {
    target = aws_cloudwatch_log_group.ingest
    values = {
      arn = "arn:aws:logs:us-east-1:210987654321:log-group:/aws/lambda/demo-ingest"
    }
  }

  # Both documents would otherwise get the same mocked JSON, so a reference to
  # the wrong one would pass. Pin a distinct JSON for each.
  override_data {
    target = data.aws_iam_policy_document.lambda_assume
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"MockAssume\"}]}"
    }
  }

  override_data {
    target = data.aws_iam_policy_document.ingest_permissions
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"MockIngestPermissions\"}]}"
    }
  }

  assert {
    condition     = aws_cloudwatch_log_group.ingest.name == "/aws/lambda/demo-ingest"
    error_message = "The log group must be named /aws/lambda/<name_prefix>-ingest (got ${aws_cloudwatch_log_group.ingest.name})."
  }

  assert {
    condition     = aws_cloudwatch_log_group.ingest.retention_in_days == 14
    error_message = "The log group must keep logs for 14 days: retention_in_days = 14 (got ${aws_cloudwatch_log_group.ingest.retention_in_days})."
  }

  assert {
    condition = length(data.aws_iam_policy_document.lambda_assume.statement) == 1 && alltrue([
      for st in data.aws_iam_policy_document.lambda_assume.statement :
      st.effect == "Allow" && toset(st.actions) == toset(["sts:AssumeRole"]) &&
      length(st.principals) == 1 && alltrue([for p in st.principals : p.type == "Service" && toset(p.identifiers) == toset(["lambda.amazonaws.com"])])
    ])
    error_message = "The trust policy needs one statement: Allow sts:AssumeRole for principal type Service with identifier lambda.amazonaws.com."
  }

  assert {
    condition     = aws_iam_role.ingest.name == "demo-ingest"
    error_message = "The role must be named <name_prefix>-ingest (got ${aws_iam_role.ingest.name})."
  }

  assert {
    condition     = aws_iam_role.ingest.assume_role_policy == data.aws_iam_policy_document.lambda_assume.json
    error_message = "The role's assume_role_policy must be the lambda_assume document's json, not the permissions document."
  }

  assert {
    condition     = length(data.aws_iam_policy_document.ingest_permissions.statement) == 3
    error_message = "The permissions document must have exactly three statements (ReadLanding, SendEvents, WriteLogs). Least privilege: nothing else."
  }

  assert {
    condition = length([
      for st in data.aws_iam_policy_document.ingest_permissions.statement : st
      if st.sid == "ReadLanding" && st.effect == "Allow" && toset(st.actions) == toset(["s3:GetObject"]) && toset(st.resources) == toset(["arn:aws:s3:::demo-landing-210987654321/*"])
    ]) == 1
    error_message = "ReadLanding must allow s3:GetObject on the landing bucket's arn followed by /*, and nothing broader."
  }

  assert {
    condition = length([
      for st in data.aws_iam_policy_document.ingest_permissions.statement : st
      if st.sid == "SendEvents" && st.effect == "Allow" && toset(st.actions) == toset(["sqs:SendMessage"]) && toset(st.resources) == toset(["arn:aws:sqs:us-east-1:210987654321:demo-main"])
    ]) == 1
    error_message = "SendEvents must allow sqs:SendMessage on the main queue's arn only."
  }

  assert {
    condition = length([
      for st in data.aws_iam_policy_document.ingest_permissions.statement : st
      if st.sid == "WriteLogs" && st.effect == "Allow" && toset(st.actions) == toset(["logs:CreateLogStream", "logs:PutLogEvents"]) && toset(st.resources) == toset(["arn:aws:logs:us-east-1:210987654321:log-group:/aws/lambda/demo-ingest:*"])
    ]) == 1
    error_message = "WriteLogs must allow logs:CreateLogStream and logs:PutLogEvents on the function's own log group, arn followed by :*."
  }

  assert {
    condition     = aws_iam_role_policy.ingest.name == "demo-ingest" && aws_iam_role_policy.ingest.role == "mock-ingest-role-id"
    error_message = "The inline policy must be named <name_prefix>-ingest and attach to the role by its id."
  }

  assert {
    condition     = data.archive_file.ingest.type == "zip" && data.archive_file.ingest.source_dir == "${path.module}/../src/ingest/dist" && data.archive_file.ingest.output_path == "${path.module}/build/ingest.zip"
    error_message = "The zip must be built from ../src/ingest/dist into build/ingest.zip, relative to the Terraform folder."
  }

  assert {
    condition     = aws_lambda_function.ingest.function_name == "demo-ingest"
    error_message = "The function must be named <name_prefix>-ingest (got ${aws_lambda_function.ingest.function_name})."
  }

  assert {
    condition     = aws_lambda_function.ingest.role == "arn:aws:iam::210987654321:role/demo-ingest"
    error_message = "The function's role must be the ingest role's arn (got ${aws_lambda_function.ingest.role})."
  }

  assert {
    condition     = aws_lambda_function.ingest.handler == "index.handler"
    error_message = "The handler must be index.handler, the file tsc writes from index.ts (got ${aws_lambda_function.ingest.handler})."
  }

  assert {
    condition     = aws_lambda_function.ingest.runtime == "nodejs24.x"
    error_message = "The runtime must be nodejs24.x. Never nodejs20.x: Lambda deprecated it on 2026-04-30 (got ${aws_lambda_function.ingest.runtime})."
  }

  assert {
    condition     = toset(aws_lambda_function.ingest.architectures) == toset(["arm64"])
    error_message = "The function must run on arm64 (got ${jsonencode(aws_lambda_function.ingest.architectures)})."
  }

  assert {
    condition     = aws_lambda_function.ingest.memory_size == 256 && aws_lambda_function.ingest.timeout == 30
    error_message = "memory_size must be 256 MB and timeout must be 30 seconds (got ${aws_lambda_function.ingest.memory_size} MB and ${aws_lambda_function.ingest.timeout} s)."
  }

  assert {
    condition     = aws_lambda_function.ingest.filename == data.archive_file.ingest.output_path && aws_lambda_function.ingest.source_code_hash == data.archive_file.ingest.output_base64sha256
    error_message = "The function must deploy the archive's output_path and source_code_hash, so a code change produces a new deployment."
  }

  assert {
    condition     = length(aws_lambda_function.ingest.environment) == 1 && one(aws_lambda_function.ingest.environment).variables["QUEUE_URL"] == "https://sqs.us-east-1.amazonaws.com/210987654321/demo-main"
    error_message = "The function needs QUEUE_URL set to the main queue's url (got ${jsonencode(aws_lambda_function.ingest.environment)})."
  }

  assert {
    condition     = length(aws_lambda_function.ingest.logging_config) == 1 && one(aws_lambda_function.ingest.logging_config).log_format == "JSON" && one(aws_lambda_function.ingest.logging_config).log_group == "/aws/lambda/demo-ingest"
    error_message = "logging_config must set log_format = \"JSON\" and log_group to the log group's name, which is also what orders the function after the group."
  }

  assert {
    condition     = lookup(aws_lambda_function.ingest.tags, "Role", "") == "ingest" && lookup(aws_lambda_function.ingest.tags, "ManagedBy", "") == "terraform"
    error_message = "The function needs tags Name = <its name>, Role = \"ingest\", ManagedBy = \"terraform\" (got ${jsonencode(aws_lambda_function.ingest.tags)})."
  }
}
