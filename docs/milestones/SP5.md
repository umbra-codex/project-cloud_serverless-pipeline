# SP5: Queue, dead-letter queue, and table

| | |
|---|---|
| **Milestone** | SP5: Queue, dead-letter queue, and table |
| **Branch** | `sp5-queues` |
| **Depends on** | SP4, merged |
| **Files you touch** | `terraform/providers.tf` (new), `terraform/variables.tf` (new), `terraform/queues.tf` (new), `terraform/table.tf` (new), `terraform/outputs.tf` (new) |
| **Check** | Runs in this repo on every push to `sp5-queues`, and locally with `bash .github/scripts/check-local.sh`. Use this exact branch name |

## Goal

Three resources, and the inputs they need. The queue absorbs a burst of events and retries a failed message on its own; the dead-letter queue is where a message goes after five failures, so a person can read it; the table holds one row per event, keyed by the value the conditional write in SP9 will check.

Nothing here is applied yet. SP5 is a plan-only milestone: three resources, zero cost, no AWS calls beyond the plan's own.

## Start your branch

```bash
git checkout main
git pull
git checkout -b sp5-queues
git push -u origin sp5-queues
```

Open a draft pull request at the first checkpoint.

## Part 1: Inputs and the two queues

### providers.tf

#### 1. The provider

**Block Type:** `provider`
**Provider Name:** `aws`

| Argument | Set To |
|---|---|
| `region` | the `region` variable |

**Tags:** providers do not take tags.

**Docs:** [Provider configuration](https://developer.hashicorp.com/terraform/language/providers/configuration) · [aws provider](https://registry.terraform.io/providers/hashicorp/aws/6.69.1/docs)

Add the `aws` provider requirement to the `terraform` block in `terraform/backend.tf`, beside the version pin: `aws = { source = "hashicorp/aws", version = "~> 6.0" }`. The `provider "aws"` block above goes in the new `providers.tf`, which holds configuration only: a second `required_providers` block anywhere in the tree is an error, so the requirement stays where the version pin already is.

### variables.tf

#### 2. Region

**Block Type:** `variable`
**Variable Name:** `region`

| Argument | Set To |
|---|---|
| `description` | `"AWS Region that holds every resource in this stack."` |
| `type` | `string` |
| `default` | `"us-east-1"` |

**Tags:** variables do not take tags.

**Docs:** [Input variables](https://developer.hashicorp.com/terraform/language/values/variables)

#### 3. Name prefix

**Block Type:** `variable`
**Variable Name:** `name_prefix`

| Argument | Set To |
|---|---|
| `description` | `"Prefix for every resource name in this stack."` |
| `type` | `string` |
| `default` | `"serverless-pipeline"` |

**Tags:** variables do not take tags.

**Docs:** [Input variables](https://developer.hashicorp.com/terraform/language/values/variables)

Every resource name is this prefix plus a role, which is why the check runs with `demo` and expects `demo-main`: a typed-in name fails.

#### 4. Alert email

**Block Type:** `variable`
**Variable Name:** `alert_email`

| Argument | Set To |
|---|---|
| `description` | `"Address the budget alert is delivered to. No default: export TF_VAR_alert_email."` |
| `type` | `string` |

**Tags:** variables do not take tags.

**Docs:** [Environment variables for inputs](https://developer.hashicorp.com/terraform/language/values/variables#environment-variables)

No default, on purpose. The budget in SP8 emails this address, and a default would quietly point at a dead mailbox. Locally you supply it with `export TF_VAR_alert_email="you@example.com"`; CI already supplies it as a secret. Until this variable exists, OpenTofu ignores the `TF_VAR_alert_email` CI sets and says nothing about it: there is no warning to wait for, which is why nothing in the SP4 plan log mentions the address. Declaring the variable here is what puts the value to use; SP8 is only where the budget starts reading it.

### queues.tf

#### 5. The dead-letter queue

**Block Type:** `resource`
**Resource Type:** `aws_sqs_queue`
**Resource Name:** `dlq`

| Argument | Set To |
|---|---|
| `name` | the `name_prefix` variable, a hyphen, then `dlq`, using interpolation |
| `message_retention_seconds` | `1209600` |
| `sqs_managed_sse_enabled` | `true` |
| `tags` | `Name` = the same value you gave `name`; `Role` = `"dead-letter"`; `ManagedBy` = `"terraform"` |

**Tags:** yes, through the `tags` argument.

**Docs:** [aws_sqs_queue](https://registry.terraform.io/providers/hashicorp/aws/6.69.1/docs/resources/sqs_queue) · [SQS dead-letter queues](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-dead-letter-queues.html)

`1209600` seconds is 14 days, the longest SQS keeps a message. A dead-letter queue that expires its contents in four days is a queue you will read on the wrong day. Server-side encryption with an SQS-managed key is free and needs no key policy.

The tag says `terraform` although no `terraform` binary ever runs in this build: it names the configuration language, which Terraform and OpenTofu share, and it is the value the check asserts. Leave it spelled that way on every resource.

#### 6. The main queue

**Block Type:** `resource`
**Resource Type:** `aws_sqs_queue`
**Resource Name:** `main`

| Argument | Set To |
|---|---|
| `name` | the `name_prefix` variable, a hyphen, then `main` |
| `visibility_timeout_seconds` | `180` |
| `sqs_managed_sse_enabled` | `true` |
| `redrive_policy` | an expression, not a number: `jsonencode` of an object with `deadLetterTargetArn` = the `arn` of `aws_sqs_queue.dlq`, and `maxReceiveCount` = `5` |
| `tags` | `Name` = the same value you gave `name`; `Role` = `"queue"`; `ManagedBy` = `"terraform"` |

**Tags:** yes, through the `tags` argument.

**Docs:** [aws_sqs_queue](https://registry.terraform.io/providers/hashicorp/aws/6.69.1/docs/resources/sqs_queue) · [Visibility timeout](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-visibility-timeout.html) · [jsonencode](https://developer.hashicorp.com/terraform/language/functions/jsonencode)

Why 180 seconds: AWS asks for a visibility timeout of at least six times the function timeout, plus the batching window when one is set. The function's timeout is 30 seconds in SP7 and there is no batching window here, so 180 is six times 30 with nothing added. The extra time is there so Lambda can retry when the function is throttled; make it shorter and SQS hands the same message to a second invocation while the first is still working, which is the duplicate you did not ask for, on top of the at-least-once delivery you already have.

Why `maxReceiveCount` 5: AWS recommends at least 5 for a Lambda event source, so that one bad moment — a throttle, a cold start that runs long — does not put a message in the dead-letter queue on the first try. Five receives at 180 seconds is also what makes the failure drill in SP12 watchable, about 12 to 15 minutes, but that is the side effect rather than the reason.

**✅ Checkpoint: step 1 (queues)**
Save `providers.tf`, `variables.tf`, and `queues.tf`, then run the check in your terminal before you commit:

```bash
bash .github/scripts/check-local.sh
```

Expected: `SP5 step 1 (queues)` ✅, with the steps you have not built yet still ❌. If a step is ❌, the `Next:` line names the section to re-read: fix it and run the same command again before committing. Then format, commit, and push:

```bash
tofu fmt -recursive
git add -A && git commit -m "feat(sp5): add the queue, the dead-letter queue, and the inputs" && git push
gh pr create --fill --draft
```

The push runs the same check on GitHub, which is the authority and is consulted once per milestone, before `gh pr ready`: [SP1](SP1.md#how-to-see-your-results) explains both tiers. Step 1 turns ✅. Steps 2 and 3 stay ❌ until Parts 2 and 3.

## Part 2: The table

### table.tf

#### 7. The events table

**Block Type:** `resource`
**Resource Type:** `aws_dynamodb_table`
**Resource Name:** `events`

| Argument | Set To |
|---|---|
| `name` | the `name_prefix` variable, a hyphen, then `events` |
| `billing_mode` | `"PAY_PER_REQUEST"` |
| `hash_key` | `"idempotency_key"` |
| `attribute` (nested block) | exactly one block, with `name` = `"idempotency_key"` and `type` = `"S"` |
| `point_in_time_recovery` (nested block) | one block with `enabled` = `true` |
| `server_side_encryption` (nested block) | one block with `enabled` = `true` |
| `tags` | `Name` = the same value you gave `name`; `Role` = `"events"`; `ManagedBy` = `"terraform"` |

**Tags:** yes, through the `tags` argument.

**Docs:** [aws_dynamodb_table](https://registry.terraform.io/providers/hashicorp/aws/6.69.1/docs/resources/dynamodb_table) · [DynamoDB core components](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/HowItWorks.CoreComponents.html) · [Conditional writes](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/WorkingWithItems.html)

The key is the whole design. SP9 writes with a condition that the key does not exist, so a message delivered twice writes one row and the second attempt is a success, not an error. `PAY_PER_REQUEST` is right for a burst that runs for an hour: provisioned capacity would idle for the rest of the month.

Encryption here uses the AWS managed key: `enabled = true` with no `kms_key_arn` selects `alias/aws/dynamodb`, a KMS key that lives in your account and that AWS creates and rotates for you, and whose requests bill per call. That is a fraction of a cent for a table that exists for hours, and it is why `.checkov.yaml` skips `CKV_AWS_119`: a customer managed key bills by the month, table or no table. Anything that would satisfy that check instead of skipping it belongs in a different stack; if you add a customer managed key later, delete the skip in the same commit so the file keeps explaining itself.

Only the partition key is declared. The `payload` and `processed_at` attributes are not in the table definition because DynamoDB, unlike a relational table, does not need one.

**✅ Checkpoint: step 2 (table)**
Save `table.tf`, then run the check in your terminal before you commit:

```bash
bash .github/scripts/check-local.sh
```

Expected: `SP5 step 2 (table)` ✅, with the steps you have not built yet still ❌. If a step is ❌, the `Next:` line names the section to re-read: fix it and run the same command again before committing. Then format, commit, and push:

```bash
tofu fmt -recursive
git add -A && git commit -m "feat(sp5): add the events table" && git push
```

The push runs the same check on GitHub, which is the authority and is consulted once per milestone, before `gh pr ready`: [SP1](SP1.md#how-to-see-your-results) explains both tiers. Step 2 turns ✅. Step 3 is still ❌.

## Part 3: The outputs

### outputs.tf

#### 8. Five values later milestones read

| Block Type | Output Name | `value` set to |
|---|---|---|
| `output` | `main_queue_url` | the `url` of `aws_sqs_queue.main` |
| `output` | `main_queue_arn` | the `arn` of `aws_sqs_queue.main` |
| `output` | `dlq_url` | the `url` of `aws_sqs_queue.dlq` |
| `output` | `dlq_arn` | the `arn` of `aws_sqs_queue.dlq` |
| `output` | `table_name` | the `name` of `aws_dynamodb_table.events` |

Each output also takes a `description` of one sentence. **Tags:** outputs do not take tags.

**Docs:** [Outputs](https://developer.hashicorp.com/terraform/language/values/outputs)

These five are what SP12's commands read with `tofu output -raw`. The names are part of the contract: the scripts in `scripts/` use them, so do not rename one later without changing the script in the same milestone.

**✅ Checkpoint: step 3 (outputs)**
Save `outputs.tf`, then run the check in your terminal before you commit:

```bash
bash .github/scripts/check-local.sh
```

Expected: `SP5 step 3 (outputs)` ✅, and the summary says `👍 SP5 passed.` If a step is ❌, the `Next:` line names the section to re-read: fix it and run the same command again before committing. Then format, commit, and push:

```bash
tofu fmt -recursive
git add -A && git commit -m "feat(sp5): expose the queue and table values" && git push
```

The push runs the same check on GitHub, which is the authority and is consulted once per milestone, before `gh pr ready`: [SP1](SP1.md#how-to-see-your-results) explains both tiers. Step 3 turns ✅, and every row is ✅.

## Check it

Run `bash .github/scripts/check-local.sh` at every checkpoint. What its output means, how to fix a red step, and when GitHub is the authority are explained once, in [SP1](SP1.md#how-to-see-your-results); this brief's own steps and its own failures are below.

### How to see your results


**Locally:** `bash .github/scripts/check-local.sh`, which prints one row per step and `👍 SP5 passed.` at the end.

**On the pull request:** open **Actions**, click the newest run, and read **Summary**.

| Step | Checks |
|---|---|
| 1 (queues) | `queues.tf`: both queue names, the 14-day retention, encryption, the 180 second visibility timeout, `maxReceiveCount = 5`, the policy pointing at the dead-letter queue's ARN, and the tags. Also that both names follow the prefix, by planning again with a different one |
| 2 (table) | `table.tf`: the name, on-demand billing, the partition key and its attribute, point-in-time recovery, encryption, and the tags |
| 3 (outputs) | `outputs.tf`: each of the five outputs carries the right value |

Reading a failure:

- **"The dead-letter queue must be named ..."**: the name has to be built from the variable with interpolation, so `"${var.name_prefix}-dlq"`, not `"serverless-pipeline-dlq"`.
- **"redrive_policy.maxReceiveCount must be 5"**: the number lives inside the `jsonencode` object, not on the queue as a plain argument.
- **"There is no managed resource ..."**: the resource type or name does not match this brief. The check looks for the exact type and name.
- **A formatting row in ❌**: run `tofu fmt -recursive` and push again.

## Done when (plan only, no apply)

This milestone spends nothing, so the check here is a real plan against your real backend, and then no apply. Run it from the repo root:

```bash
export TF_VAR_alert_email="you@example.com"
tofu -chdir=terraform init
tofu -chdir=terraform plan
```

Expected, at the end of the plan:

```
Plan: 3 to add, 0 to change, 0 to destroy.
```

Three resources: two queues and the table. If the count is different, read the plan rather than approving it: a fourth resource means something else got included.

Read the plan's details before you move on. What you should see:

- The main queue's `redrive_policy` names the dead-letter queue.
- `visibility_timeout_seconds` is 180 on the main queue.
- The table's `hash_key` is `idempotency_key`.

Then destroy nothing, because nothing was applied. If you did apply by mistake, `tofu -chdir=terraform destroy` removes all three, and the state bucket keeps the empty state.

## Mark the pull request ready

```bash
printf '%s\n' SP5 >> milestones.txt
git add milestones.txt && git commit -m "chore(sp5): add SP5 to milestones.txt" && git push
```

One last look at the check on GitHub, which is the authority here. It follows the run your last push started, so it needs no new commit and no push:

```bash
bash .github/scripts/remote-check.sh
```

This reads the milestone check only: the `static` and `plan` jobs your `ci.yml` runs are separate required checks, and the pull request's **Checks** tab is where a red one shows.

When it prints `👍 SP5 passed.`, retitle the pull request and mark it ready:

```bash
gh pr edit --title "feat(sp5): add the queue, the dead-letter queue, and the events table"
gh pr ready
```

Paste the plan's last line into the pull request body first. A reviewer reads the diff against this brief, then merges.

## After the merge

Merge the pull request on GitHub, then clean up the branch:

```bash
git switch main && git pull
git branch -d sp5-queues
git fetch --prune
```

`git branch -d` refuses after a squash merge, because the branch's commits are not in `main`; `git branch -D sp5-queues` is the same delete. The remote branch is already gone: `delete_branch_on_merge` removes it when the pull request merges.
