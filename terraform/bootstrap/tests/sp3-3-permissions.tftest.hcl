# Step 3 of SP3: the role's permissions. Planned, not executed, so the account
# is never touched; the policy document's contents are asserted by the text
# check beside this file, because a mocked data source has no real JSON.
mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  mock_resource "aws_iam_openid_connect_provider" {
    defaults = {
      arn = "arn:aws:iam::111122223333:oidc-provider/token.actions.githubusercontent.com"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::111122223333:role/github-ci-plan"
      id  = "AROADEMOROLE"
    }
  }
}

run "permissions" {
  command = plan

  variables {
    region          = "us-east-1"
    state_bucket    = "demo-state-bucket"
    github_owner    = "demo-owner"
    github_owner_id = "11111111"
    github_repo     = "demo-repo"
    github_repo_id  = "22222222"
  }

  assert {
    condition     = aws_iam_role_policy_attachment.ci_plan_read_only.policy_arn == "arn:aws:iam::aws:policy/ReadOnlyAccess"
    error_message = "the plan job needs the managed read-only policy attached"
  }

  assert {
    condition     = aws_iam_role_policy.ci_plan_state.name == "state-bucket"
    error_message = "the inline state policy must be named state-bucket"
  }
}
