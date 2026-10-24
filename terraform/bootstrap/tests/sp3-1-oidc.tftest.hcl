# Two plans with two different owners, repositories and numeric IDs. The trust
# document itself is a mocked data source, so its content is asserted by the
# text check beside this file; what this proves is that the module plans under
# more than one set of repository inputs.
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

run "alpha" {
  command = plan

  variables {
    region          = "us-east-1"
    state_bucket    = "demo-state-bucket"
    github_owner    = "alpha-owner"
    github_owner_id = "11111111"
    github_repo     = "alpha-repo"
    github_repo_id  = "22222222"
  }

  assert {
    condition     = aws_iam_openid_connect_provider.github.url == "https://token.actions.githubusercontent.com"
    error_message = "the provider URL must be the GitHub token issuer"
  }

  assert {
    condition     = contains(aws_iam_openid_connect_provider.github.client_id_list, "sts.amazonaws.com")
    error_message = "the audience must be sts.amazonaws.com, which the trust condition also requires"
  }

  assert {
    condition     = aws_iam_role.ci_plan.name == "github-ci-plan"
    error_message = "the role name must be github-ci-plan"
  }


}

run "beta" {
  command = plan

  variables {
    region          = "us-east-1"
    state_bucket    = "demo-state-bucket"
    github_owner    = "beta-owner"
    github_owner_id = "33333333"
    github_repo     = "beta-repo"
    github_repo_id  = "44444444"
  }

  assert {
    condition     = aws_iam_role.ci_plan.name == "github-ci-plan"
    error_message = "the role name is constant; only the trust subjects change with the inputs"
  }

}
