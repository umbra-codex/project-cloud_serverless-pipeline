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

# SP8 step 1: terraform/budget.tf adds the alert that fires long before the
# credits could run out.
# Brief: docs/milestones/SP8.md

variables {
  alert_email = "alerts@example.com"
  name_prefix = "demo"
}

run "budget_alert" {
  command = plan

  assert {
    condition     = aws_budgets_budget.guard.name == "demo-guard"
    error_message = "The budget must be named <name_prefix>-guard (got ${aws_budgets_budget.guard.name})."
  }

  assert {
    condition     = aws_budgets_budget.guard.budget_type == "COST" && aws_budgets_budget.guard.time_unit == "MONTHLY"
    error_message = "The budget must be a monthly COST budget (got ${aws_budgets_budget.guard.budget_type} per ${aws_budgets_budget.guard.time_unit})."
  }

  assert {
    condition     = aws_budgets_budget.guard.limit_amount == "1" && aws_budgets_budget.guard.limit_unit == "USD"
    error_message = "The limit must be the budget_limit_usd variable, 1 USD by default (got ${aws_budgets_budget.guard.limit_amount} ${aws_budgets_budget.guard.limit_unit})."
  }

  assert {
    condition     = length(aws_budgets_budget.guard.cost_types) == 1 && one(aws_budgets_budget.guard.cost_types).include_credit == false
    error_message = "cost_types must set include_credit = false. With credits counted, a credit-funded account reads about 0 and the alert never fires."
  }

  assert {
    condition     = length(aws_budgets_budget.guard.notification) == 1
    error_message = "The budget needs exactly one notification block."
  }

  assert {
    condition = length([
      for n in aws_budgets_budget.guard.notification : n
      if n.threshold == 80 && n.threshold_type == "PERCENTAGE" && n.notification_type == "ACTUAL" && toset(n.subscriber_email_addresses) == toset(["alerts@example.com"])
    ]) == 1
    error_message = "The notification must fire at 80 percent of actual spend and email the alert_email value (got ${jsonencode(aws_budgets_budget.guard.notification)})."
  }
}

run "limit_follows_the_variable" {
  command = plan

  variables {
    budget_limit_usd = "5"
  }

  assert {
    condition     = aws_budgets_budget.guard.limit_amount == "5"
    error_message = "limit_amount must come from the budget_limit_usd variable, not a typed-in number (got ${aws_budgets_budget.guard.limit_amount})."
  }
}
