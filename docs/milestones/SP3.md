# SP3: GitHub OIDC role

| | |
|---|---|
| **Milestone** | SP3: GitHub OIDC role |
| **Branch** | `sp3-oidc` |
| **Depends on** | SP2, merged, with the bucket holding the bootstrap state |
| **Files you touch** | `terraform/bootstrap/variables.tf`, `terraform/bootstrap/oidc.tf` (new), `terraform/bootstrap/outputs.tf` (new), `.github/workflows/oidc-check.yaml` (new) |
| **Check** | Runs in this repo on every push to `sp3-oidc`, and locally with `.github/scripts/check.sh SP3`. Use this exact branch name |

## Goal

A role that a GitHub Actions run can assume with no stored secret, whose trust
policy names this repository and nothing else. Once it exists, CI can read the
state bucket and plan against it, and there is no access key anywhere in the
repository or its settings.

This is the single most interview-relevant thing in the repo. A junior candidate
puts an access key in GitHub secrets. You are going to explain, from a file, why
you did not.

The role lives in `terraform/bootstrap/`, not in the pipeline configuration,
because SP14 destroys the pipeline and this role outlives it. IAM is free, so
this apply costs nothing, and it is the second of the two applies before SP12.

## Start your branch

```bash
git checkout main
git pull
git checkout -b sp3-oidc
git push -u origin sp3-oidc
```

## Part 1: The provider and the trust policy

### variables.tf

Add four inputs beside `region` and `state_bucket`. None is a secret; all four
are public identifiers.

| Block Type | Variable | Type | Default |
|---|---|---|---|
| `variable` | `github_owner` | `string` | your GitHub user or organization, lowercase |
| `variable` | `github_owner_id` | `string` | the numeric ID of that owner |
| `variable` | `github_repo` | `string` | `"serverless-pipeline"` |
| `variable` | `github_repo_id` | `string` | the numeric ID of the repository |

The two numeric IDs look redundant next to the names, and they are the point of
this milestone: GitHub puts them in the OIDC subject now, and a trust policy
written against the older two-part form does not match. Look both up with the
GitHub CLI rather than typing them from memory:

```bash
gh api users/YOUR_GITHUB_OWNER --jq .id
gh api repos/YOUR_GITHUB_OWNER/project-cloud_serverless-pipeline --jq .id
```

Both print a number. The second needs the repository from SP0, which exists.

### oidc.tf

Three blocks make the identity and describe who may become it.

| Block Type | Type | Name |
|---|---|---|
| `resource` | `aws_iam_openid_connect_provider` | `github` |
| `resource` | `aws_iam_role` | `ci_plan` |
| `data` | `aws_iam_policy_document` | `ci_plan_trust` |

| Resource | Argument | Set To |
|---|---|---|
| `aws_iam_openid_connect_provider.github` | `url` | `"https://token.actions.githubusercontent.com"` |
| `aws_iam_openid_connect_provider.github` | `client_id_list` | `["sts.amazonaws.com"]` |
| `aws_iam_role.ci_plan` | `name` | `"github-ci-plan"` |
| `aws_iam_role.ci_plan` | `assume_role_policy` | `data.aws_iam_policy_document.ci_plan_trust.json` — Terraform renders the trust document below into JSON for you |

`assume_role_policy` takes a policy document as a JSON string: that is what `.json` produces. It is not an ARN, not a file path, and not HCL you paste in. Terraform reads the `data` block and renders its statements to JSON at plan time, so writing that block below the role changes nothing about the order it is evaluated in. This is the trust policy: who may *become* the role. What the role may then *do* comes later, with a permissions policy attached to it.

The trust document has one `statement` with three parts:

| Part | Set To |
|---|---|
| `actions` | `["sts:AssumeRoleWithWebIdentity"]` |
| `principals` (nested block) | `type = "Federated"`, `identifiers = [aws_iam_openid_connect_provider.github.arn]`. `identifiers` is a list, and that `arn` is an attribute the provider resource above creates, not an argument you supply: `arn:aws:iam::<account-id>:oidc-provider/token.actions.githubusercontent.com` |
| `condition` (first) | `test = "StringEquals"`, `variable = "token.actions.githubusercontent.com:aud"`, `values = ["sts.amazonaws.com"]` |
| `condition` (second) | `test = "StringEquals"`, `variable = "token.actions.githubusercontent.com:sub"`, with exactly the two values below |

The two subject values, no wildcard, with the owner and repository names and both
numeric IDs:

```
repo:${var.github_owner}@${var.github_owner_id}/${var.github_repo}@${var.github_repo_id}:pull_request
repo:${var.github_owner}@${var.github_owner_id}/${var.github_repo}@${var.github_repo_id}:ref:refs/heads/main
```

**Docs:** [iam_openid_connect_provider](https://registry.terraform.io/providers/hashicorp/aws/6.69.1/docs/resources/iam_openid_connect_provider) · [iam_role](https://registry.terraform.io/providers/hashicorp/aws/6.69.1/docs/resources/iam_role) · [GitHub OIDC subject claims](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect)

**Tags:** IAM roles take `tags`; put `Name` on the role and nothing else.

**The `sub` condition is the whole security boundary.** Without it, any GitHub
repository in the world can assume this role, because the provider is shared by
every GitHub workflow everywhere. The condition is what narrows it to yours.

**Why the numeric IDs.** A subject written without them does not match a token
that carries them, and the run fails with `Not authorized to perform
sts:AssumeRoleWithWebIdentity` even though everything looks right. That is the
failure the old pattern produces, and it is worth reading twice before you apply.

**Why exact subjects and not a wildcard.** A trailing wildcard matches every
workflow context in the repository. This role only needs a plan on a pull request
and a plan on `main`, so those two are named, with `StringEquals`.

**What that does not buy you.** Every `pull_request` run has the same subject
whether the PR came from a branch or a fork, so this condition does not
distinguish a fork. What protects the role is that a run needs `id-token: write`
to get a token at all, and GitHub does not grant that to a fork's pull request.
The repository setting *Send write tokens to workflows from pull requests* must
stay off; check it. The conditions buy scope, and the fork boundary is GitHub's.

**The provider is per account, not per repository.** A second
`aws_iam_openid_connect_provider` for the same URL in the same account fails with
`EntityAlreadyExists`, and this account may already have one: the template build
made one, and so does every other repository on this program. Two routes, and the
first is the honest one:

1. Look first. `aws iam list-open-id-connect-providers` prints the ARNs. If one
   for `token.actions.githubusercontent.com` is there, do not create another:
   import it with `tofu import aws_iam_openid_connect_provider.github <arn>` and
   leave the block as it is.
2. If the import is not what you want, do not delete the existing provider
   either: other repositories trust it. Take the ARN from the list and put it in
   a variable, then drop the resource block.

**This role is per repository.** Its trust names `serverless-pipeline` and no
other, so repository 3 and repository 5 cannot assume it. The program's "build the
role once and reuse it" line is met two ways: they add their own subject line to
this trust policy and apply it from their own repository, or they make a sibling
role next to this one. Say which you chose in `DECISIONS.md`.

**No `thumbprint_list`.** The argument is optional in this provider version and
the issuer does not need it. Older examples set it; leave it out.

> **✅ Checkpoint: steps 1 and 2 (provider and trust)**
> Save `variables.tf` and `oidc.tf`, then run the check in your terminal before you commit:
> ```bash
> bash .github/scripts/check-local.sh
> ```
> Expected: `SP3 step 1 (oidc)` and `SP3 step 2 (trust)` ✅, with the steps you have not built yet still ❌. If a step is ❌, the `Next:` line under the summary names the brief section to re-read and what the check looked for: fix the file and run the same command again, with no commit and no push.
> Then format, commit, and push:
> ```bash
> tofu fmt -recursive
> git add -A && git commit -m "feat(sp3): add the OIDC provider and the role trust policy" && git push
> gh pr create --fill --draft
> ```
> The push runs the same check on GitHub, which is the authority and is consulted once per milestone, before `gh pr ready`: [SP1](SP1.md#how-to-see-your-results) explains both tiers.
> Steps 1 and 2 turn ✅: the provider and the role from step 1's plan, and the two
> subject values read out of the file in step 2. Step 3 stays ❌.

## Part 2: Permissions

Three more blocks: one attaches a policy AWS publishes, and two make and attach
an inline policy for the state bucket.

| Block Type | Type | Name |
|---|---|---|
| `resource` | `aws_iam_role_policy_attachment` | `ci_plan_read_only` |
| `data` | `aws_iam_policy_document` | `ci_plan_state` |
| `resource` | `aws_iam_role_policy` | `ci_plan_state` |

| Resource | Argument | Set To |
|---|---|---|
| `aws_iam_role_policy_attachment.ci_plan_read_only` | `role` | the `name` of the role |
| `aws_iam_role_policy_attachment.ci_plan_read_only` | `policy_arn` | `"arn:aws:iam::aws:policy/ReadOnlyAccess"` — the AWS-managed policy, so `aws` sits where an account ID would |
| `aws_iam_role_policy.ci_plan_state` | `name` | `"state-bucket"` |
| `aws_iam_role_policy.ci_plan_state` | `role` | the `id` of the role |
| `aws_iam_role_policy.ci_plan_state` | `policy` | the `.json` of the second policy document |

`aws_iam_role_policy_attachment` attaches a policy that already exists; it does not create one. `policy_arn` names that policy — an AWS-managed ARN here, or a customer-managed one if you had built it yourself. It is not the role's ARN and not a JSON document: inline JSON is what `aws_iam_role_policy` takes, the third block below, which writes a policy instead of referencing one. `role` takes the role's name, and `ReadOnlyAccess` is account-independent, so this line is identical in every account.

Those two statements belong in the **`data` block** — `data.aws_iam_policy_document.ci_plan_state` — not in the resource. The resource `aws_iam_role_policy.ci_plan_state` holds no statements at all: it holds `name = "state-bucket"`, `role` = the role's `id`, and `policy = data.aws_iam_policy_document.ci_plan_state.json`. One block authors the document, the other attaches it to the role.

| Statement | `actions` | `resources` |
|---|---|---|
| 1 | `["s3:ListBucket"]` | the bucket ARN: `arn:aws:s3:::`, then `var.state_bucket` in its own interpolation |
| 2 | `["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]` | the same ARN, then `/*` |

**Docs:** [iam_role_policy](https://registry.terraform.io/providers/hashicorp/aws/6.69.1/docs/resources/iam_role_policy) · [iam_role_policy_attachment](https://registry.terraform.io/providers/hashicorp/aws/6.69.1/docs/resources/iam_role_policy_attachment)

**Why write access on a job that never applies.** `plan` takes the state lock,
which is an object written next to the state file and deleted after the run. A
role with only `s3:GetObject` gets a plan that fails on the lock, with a message
about `PutObject` that reads like a permissions bug in the wrong place.

**Why the managed read-only policy and not a narrow list.** You do not yet know
which read calls the stack needs, and a policy written from imagination will be
wrong. Write down every `AccessDenied` you meet: adding one action to this role
and applying again is the correct move, and that list is the raw material if you
ever replace the managed policy with your own. SP15 publishes the two execution
policies, which are fully known by then; it does not narrow this one, because the
policy this role needs is whatever the plan calls, and the plan keeps changing.

## Part 3: Apply, output, and the variable

| Block Type | Output | Value |
|---|---|---|
| `output` | `ci_role_arn` | the `arn` of `aws_iam_role.ci_plan` |

From the repository root, hand the five inputs to OpenTofu, using the two numbers
the `gh api` commands printed and the names you already know:

```bash
export TF_VAR_state_bucket="tfstate-YOUR_ACCOUNT_ID-serverless"
export TF_VAR_github_owner="YOUR_GITHUB_OWNER"
export TF_VAR_github_owner_id="THE_OWNER_ID"
export TF_VAR_github_repo="serverless-pipeline"
export TF_VAR_github_repo_id="THE_REPO_ID"
cd terraform/bootstrap
tofu init
tofu apply
cd ../..
```

The bucket variable is the one SP2 set from your account ID, and it is not
optional here. Its default in `variables.tf` is a placeholder string, so a plan
without the export reads a different name and proposes to replace the bucket that
is holding this very state. Read the plan for that replacement before you type
`yes`; if it appears, the export is missing or names a different account.

Expected: the plan lists the provider, the role, the attachment and the inline
policy from this milestone, plus anything the bucket's own settings still owe.
Read it before you type `yes`; if it wants to create the bucket again, the
backend from SP2 is not the one you are applying into.

Then hand the ARN to GitHub. This is a repository variable, not a secret: an ARN
is an identifier, and a secret would only make it unreadable in logs.

```bash
gh variable set AWS_CI_ROLE_ARN --body "$(tofu -chdir=terraform/bootstrap output -raw ci_role_arn)"
gh variable list
```

Expected: `AWS_CI_ROLE_ARN` listed with the role's ARN.

> **✅ Checkpoint: step 3 (permissions)**
> Save the policy blocks and the output, then run the check in your terminal before you commit:
> ```bash
> bash .github/scripts/check-local.sh
> ```
> Expected: `SP3 step 3 (permissions)` ✅, and the summary says `👍 SP3 passed.` If a step is ❌, the `Next:` line under the summary names the brief section to re-read and what the check looked for: fix the file and run the same command again, with no commit and no push.
> Then format, commit, and push:
> ```bash
> tofu fmt -recursive
> git add -A && git commit -m "feat(sp3): give the CI role its permissions and its ARN output" && git push
> printf '%s\n' SP3 >> milestones.txt
> 
> git add milestones.txt && git commit -m "chore(sp3): add SP3 to milestones.txt" && git push
> ```
> The push runs the same check on GitHub, which is the authority and is consulted once per milestone, before `gh pr ready`: [SP1](SP1.md#how-to-see-your-results) explains both tiers.
> Step 3 turns ✅: the attachment, both statements of the state policy, and the
> ARN output.

## Part 4: Prove it, with a workflow you will delete

One job, one action, one command. It reads the role ARN from the repository
variable, assumes it through OIDC, and prints who it became.

**File Type:** `workflow`
**File Name:** `.github/workflows/oidc-check.yaml`

| Setting | Set To |
|---|---|
| `name` | `oidc-check` |
| `on` | `workflow_dispatch` only. A workflow on the default branch gets a Run button; one on a feature branch does not |
| `permissions` | `id-token: write` and `contents: read`. Without `id-token`, GitHub mints no token and the step fails with a credentials error that does not mention permissions |
| job `whoami` → `runs-on` | `ubuntu-latest` |
| job `whoami` → step 1 | the GitHub-to-AWS credentials action, with `role-to-assume` set to the repository variable `AWS_CI_ROLE_ARN`, and `aws-region: us-east-1` |
| job `whoami` → step 2 | `run: aws sts get-caller-identity` |

The file in full — this is the whole workflow, nothing to add:

```yaml
name: oidc-check

on:
  workflow_dispatch:

permissions:
  id-token: write   # lets the runner ask GitHub for a token; without it the step fails on credentials
  contents: read

jobs:
  whoami:
    runs-on: ubuntu-latest
    steps:
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ vars.AWS_CI_ROLE_ARN }}
          aws-region: us-east-1
      - run: aws sts get-caller-identity
```

The workflow has to be on the default branch before GitHub shows its Run button,
and this branch must not be pushed there: it carries the provider, the role and
the permissions, and those belong to the pull request. So finish the milestone
first, then add the workflow on `main`:

```bash
gh pr edit --title "feat(sp3): add the GitHub OIDC role and prove it"
gh pr ready
gh pr merge --squash
git switch main && git pull
git add .github/workflows/oidc-check.yaml
git commit -m "ci(sp3): add the throwaway role check"
git push
```

Branch protection arrives in SP4. Until then a commit straight to `main` is
allowed, which is the only reason this one is not a pull request of its own.
Then run it from **Actions → oidc-check → Run workflow**.

Expected: the log ends with an assumed-role ARN naming `github-ci-plan`. No secret
was created, and there is nothing in the repository settings to leak.

If it fails with `Not authorized to perform sts:AssumeRoleWithWebIdentity`, the
subject does not match. Compare the token's `sub`, printed by the failing step,
with the two values in the trust policy, character by character. If it fails with
`Credentials could not be loaded`, `id-token: write` is missing.

SP4 deletes this workflow, once the real CI can plan.

> **Note, not a checkpoint.** Nothing new turns green here: the workflow is the
> proof you run, and the check has nothing to read until SP4 asserts it is gone.
> Save it, then follow the four commands above once this milestone is merged.

## Check it

Run `bash .github/scripts/check-local.sh` at every checkpoint. What its output means, how to fix a red step, and when GitHub is the authority are explained once, in [SP1](SP1.md#how-to-see-your-results); this brief's own steps and its own failures are below.

### How to see your results


The steps read the configuration as text. The trust assertions are written so
that a typed-in value fails them: the subject line has to contain
`var.github_owner`, `var.github_owner_id`, `var.github_repo`, and
`var.github_repo_id` in that order, which a literal cannot satisfy.

| Step | Checks |
|---|---|
| 1 (oidc) | two rows: a text read of the provider and role, and a mocked plan run twice with two different owners, repositories and ID pairs |
| 2 (trust) | the subject condition, both subject values with their variable interpolations, and the two ID inputs |
| 3 (permissions) | two rows: a text read of the policy's five actions, and a mocked plan of the attachment and the policy's name |

Reading a failure:

- **Step 1 ❌ on the second run**: a value is typed in. The subject must read
  `var.github_owner`, `var.github_owner_id`, `var.github_repo`, and
  `var.github_repo_id`, each in its own interpolation.
- **Step 2 ❌ on `github_owner_id`**: a value is typed in. The subject must read
  `var.github_owner`, `var.github_owner_id`, `var.github_repo`, and
  `var.github_repo_id`, each in its own interpolation.
- **Step 3 ❌ on `s3:PutObject`**: the state policy is read-only, so a plan in CI
  will fail when it tries to take the lock.

## Done when (things only AWS and GitHub can show)

1. `aws iam get-role --role-name github-ci-plan` prints the role, and its trust
   policy shows the two subjects with your numeric IDs.
2. `aws iam list-role-policies --role-name github-ci-plan` prints `state-bucket`.
3. The `oidc-check` run on `main` is green, and its log shows an assumed-role ARN.
4. `gh variable list` shows `AWS_CI_ROLE_ARN`, and the repository has no
   access-key secret of any kind.
5. The repository setting *Send write tokens to workflows from pull requests* is
   off.

## Mark the pull request ready

There is nothing left to run: Part 4 merged the pull request. If you change
anything after the merge, open a small follow-up pull request rather than pushing
to `main`.

If you push a fix after that merge, GitHub's run for the push is the authority, and this follows it:

```bash
bash .github/scripts/remote-check.sh
```
