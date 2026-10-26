# SP8: Blast-radius caps

| | |
|---|---|
| **Milestone** | SP8: Blast-radius caps |
| **Branch** | `sp8-caps` |
| **Depends on** | SP7, merged |
| **Files you touch** | `terraform/budget.tf` (new), `terraform/variables.tf`, `terraform/ingest.tf`, `terraform/consumer.tf`, `terraform/mapping.tf` |
| **Check** | Runs in this repo on every push to `sp8-caps`, and locally with `bash .github/scripts/check-local.sh`. Use this exact branch name |

## Goal

Three bounds, all in the Terraform and all in place before the first apply: a budget alarm that fires near one dollar, a concurrency cap on the event source mapping, and a `reserved_concurrent_executions` setting on each function.

Only two of the three bound anything by default. The budget and the mapping cap are live from the first apply. The per-function setting ships defaulted to `-1`, which is "no reservation", because this account cannot host one: AWS requires 100 unreserved units to remain, and the account Lambda limit is 10. Part 2 gives you the two ways to change that, and the choice is yours to make and record.

The budget is an alarm, not a ceiling. It costs nothing to exist and it stops nothing: `ACTUAL` figures refresh a few times a day at best, so the notification tells you about spend that has already happened. What bounds a run is the mapping's `maximum_concurrency`, the per-function reservation if you switch it on, and the destroy in SP14.

The interesting part is not the cap but what it does to work that cannot run, and the two caps differ. `maximum_concurrency` stops the poller: SQS holds the messages, no delivery is attempted, no receive count moves, so the default produces no dead-letter traffic. A reservation below the mapping's cap throttles an invocation after the message was received, and that delivery comes back with a higher receive count, which is what can send a healthy message to the dead-letter queue. The project's definition of done asks you to measure the second during the burst and record what you saw, including nothing; SP13 is where you do it, while its burst runs.

## Start your branch

```bash
git checkout main
git pull
git checkout -b sp8-caps
git push -u origin sp8-caps
```

## Part 1: The budget

### budget.tf

#### 1. Three more inputs

Add to `terraform/variables.tf`, leaving the three from SP5 alone:

| Block Type | Variable Name | Arguments |
|---|---|---|
| `variable` | `reserved_concurrency` | `description` = `"Reserved concurrency for each function. -1 means no reservation."`, `type` = `number`, `default` = `-1` |
| `variable` | `maximum_concurrency` | `description` = `"Maximum concurrency the consumer's event source mapping may use."`, `type` = `number`, `default` = `2` |
| `variable` | `budget_limit_usd` | `description` = `"Monthly budget limit, in US dollars, as a string."`, `type` = `string`, `default` = `"1"` |

**Tags:** variables do not take tags.

**Docs:** [Input variables](https://developer.hashicorp.com/terraform/language/values/variables)

`budget_limit_usd` is a string because the provider takes the limit as one. A number is converted for you, so there is no type error to fix. Declaring the type as `string` with a `"1"` default keeps the plan showing `"1"`, and keeps the value that reaches Budgets the one you can read in the file.

#### 2. The budget

**Block Type:** `resource`
**Resource Type:** `aws_budgets_budget`
**Resource Name:** `guard`

| Argument | Set To |
|---|---|
| `name` | `<name_prefix>-guard` |
| `budget_type` | `"COST"` |
| `limit_amount` | the `budget_limit_usd` variable |
| `limit_unit` | `"USD"` |
| `time_unit` | `"MONTHLY"` |
| `cost_types` (nested block) | one block with `include_credit` = `false` |
| `notification` (nested block) | one block with `comparison_operator` = `"GREATER_THAN"`, `threshold` = `80`, `threshold_type` = `"PERCENTAGE"`, `notification_type` = `"ACTUAL"`, `subscriber_email_addresses` = `[var.alert_email]` |

**Tags:** this resource type takes tags, and this milestone sets none. The budget is not something you tag or filter; skip them rather than inventing a scheme.

**Docs:** [aws_budgets_budget](https://registry.terraform.io/providers/hashicorp/aws/6.69.1/docs/resources/budgets_budget) · [Budgets and alerts](https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-managing-costs.html)

`include_credit = false` is the setting that makes the alert work on this account. With credits counted, net spend on a credit-funded account reads about zero, and an 80 percent threshold never fires. This is the one line in the milestone a reviewer should ask you about.

`ACTUAL` rather than `FORECASTED`: a forecast alerts on a guess, and this stack runs for hours.

**✅ Checkpoint: step 1 (budget)**
Save `variables.tf` and `budget.tf`, then run the check in your terminal before you commit:

```bash
bash .github/scripts/check-local.sh
```

Expected: `SP8 step 1 (budget)` ✅, with the steps you have not built yet still ❌. If a step is ❌, the `Next:` line names the section to re-read: fix it and run the same command again before committing. Then format, commit, and push:

```bash
tofu fmt -recursive
git add -A && git commit -m "feat(sp8): add the budget alert" && git push
gh pr create --fill --draft
```

The push runs the same check on GitHub, which is the authority and is consulted once per milestone, before `gh pr ready`: [SP1](SP1.md#how-to-see-your-results) explains both tiers. Step 1 turns ✅. Steps 2 and 3 stay ❌.

## Part 2: Reserved concurrency

#### 3. One line on each function

Add the same argument to both `aws_lambda_function.ingest` and `aws_lambda_function.consumer`:

| Argument | Set To |
|---|---|
| `reserved_concurrent_executions` | the `reserved_concurrency` variable |

That is the whole part. The default is `-1`, which means no reservation, and the variable exists so the cap can be switched on the day the account's limit allows it.

**Docs:** [Reserved concurrency](https://docs.aws.amazon.com/lambda/latest/dg/configuration-concurrency.html)

Why the default is off: AWS only allows a reservation while at least 100 units of the account's concurrency limit stay unreserved. Read this account's own limit before you decide anything:

```bash
aws lambda get-account-settings --query 'AccountLimit.UnreservedConcurrentExecutions'
```

Reservations come out of the account's limit and AWS keeps at least 100 units unreserved, so two functions reserving 5 each need a limit of 110. This account prints 10, so any positive reservation fails the apply with a message about the minimum unreserved concurrency, and the honest answer is to keep the setting in the code, defaulted off, and say why. A quota increase is a request, not a switch: ask for 1,000, expect it in a support thread rather than instantly, and note that Service Quotas may decline a large jump from a small limit in one step.

The check plans twice: once with `reserved_concurrency = 5` and once with the default, so a hard-coded number fails and a missing line fails too.

**Your decision.** There are two honest ways to finish this part, and the guide leaves the choice to you:

1. **Take a real per-function cap.** Raise the account Lambda concurrency quota in Service Quotas from 10 to 1000 (it is free), then carry the cap on the command line at the one apply that sets it: SP12's plan and apply both take the prefix, `TF_VAR_reserved_concurrency=5 tofu -chdir=terraform plan -out=build/sp12.tfplan` and then `TF_VAR_reserved_concurrency=5 tofu -chdir=terraform apply build/sp12.tfplan`, and SP12's expected output changes from "absent or -1" to your number. Do not `export` it: an exported value also reaches the check's plan tests, whose second plan asserts the default is `-1`. Do **not** change the variable's default either: a positive default fails the same step.
2. **Keep the mapping cap and the budget as the bounds.** Leave the default at -1, write the reason in `DECISIONS.md` and in the README blast-radius section, and say plainly that this account cannot host a per-function reservation. The definition-of-done line about a cap on each function is then met in spirit and amended on the record.

Either way, do not leave the code claiming a cap it does not have. The variable stays in both versions, so switching later is one apply.

**✅ Checkpoint: step 2 (concurrency)**
Save both files, then run the check in your terminal before you commit:

```bash
bash .github/scripts/check-local.sh
```

Expected: `SP8 step 2 (concurrency)` ✅, with the steps you have not built yet still ❌. If a step is ❌, the `Next:` line names the section to re-read: fix it and run the same command again before committing. Then format, commit, and push:

```bash
tofu fmt -recursive
git add -A && git commit -m "feat(sp8): add reserved concurrency to both functions" && git push
```

The push runs the same check on GitHub, which is the authority and is consulted once per milestone, before `gh pr ready`: [SP1](SP1.md#how-to-see-your-results) explains both tiers. Step 2 turns ✅. Step 3 is still ❌.

## Part 3: The mapping's own cap

#### 4. A scaling block on the mapping

Add one nested block to `aws_lambda_event_source_mapping.consumer`:

| Nested block | Set To |
|---|---|
| `scaling_config` | one block with `maximum_concurrency` = the `maximum_concurrency` variable |

**Docs:** [aws_lambda_event_source_mapping](https://registry.terraform.io/providers/hashicorp/aws/6.69.1/docs/resources/lambda_event_source_mapping) · [SQS scaling and concurrency](https://docs.aws.amazon.com/lambda/latest/dg/services-sqs-scaling.html)

This is the cap that matters for the consumer. Reserved concurrency on the function caps how many invocations run, and the mapping's maximum concurrency caps how many it will ask for, so the queue stops handing over work the function cannot start. AWS accepts a value from 2 to 1000, and the default here is 2.

**✅ Checkpoint: step 3 (mapping cap)**
Save `mapping.tf`, then run the check in your terminal before you commit:

```bash
bash .github/scripts/check-local.sh
```

Expected: `SP8 step 3 (mapping-cap)` ✅, and the summary says `👍 SP8 passed.` If a step is ❌, the `Next:` line names the section to re-read: fix it and run the same command again before committing. Then format, commit, and push:

```bash
tofu fmt -recursive
git add -A && git commit -m "feat(sp8): cap the mapping's concurrency" && git push
```

The push runs the same check on GitHub, which is the authority and is consulted once per milestone, before `gh pr ready`: [SP1](SP1.md#how-to-see-your-results) explains both tiers. Step 3 turns ✅, and every row is ✅.

## Check it

Run `bash .github/scripts/check-local.sh` at every checkpoint. What its output means, how to fix a red step, and when GitHub is the authority are explained once, in [SP1](SP1.md#how-to-see-your-results); this brief's own steps and its own failures are below.

### How to see your results


The check prints one row per step, in the order the parts appear, and a step is green only when its file is in place and every assertion in it passes. A red row prints the reason underneath it, naming the file, the value, or the attribute that is wrong. CI prints the same rows in the job summary, so the local run and the remote run read identically.


**Locally:** `bash .github/scripts/check-local.sh`. **On the pull request:** **Actions**, newest run, **Summary**.

| Step | Checks |
|---|---|
| 1 (budget) | the name, `COST` and `MONTHLY`, the limit from the variable, `include_credit = false`, and one notification at 80 percent of actual spend pointing at the alert address. It also plans again with a different limit, so a typed-in number fails |
| 2 (concurrency) | both functions carry `reserved_concurrent_executions`, the value follows the variable, and the default is `-1` |
| 3 (mapping cap) | `scaling_config` holds one block, its value follows the variable, and the default is 2 |

Reading a failure:

- **"cost_types must set include_credit = false"**: the block is missing or the value is true. This is the line that makes the alert fire on a credit-funded account.
- **"reserved concurrency must default to -1"**: a default of 0 means "no invocations at all", which is a very quiet outage.
- **"The mapping needs scaling_config"**: the block goes inside the mapping, not on the function.

## Done when (plan only, no apply)

```bash
export TF_VAR_alert_email="you@example.com"
tofu -chdir=terraform init
tofu -chdir=terraform plan
```

Expected: `Plan: 19 to add, 0 to change, 0 to destroy.` SP7's eighteen plus the budget.

Then read two sections of the plan:

- The budget: `limit_amount` is `1`, `include_credit` is false, and the notification names your email.
- The mapping: `scaling_config` has `maximum_concurrency = 2`.

Finally, prove the variable drives the cap without applying anything:

```bash
TF_VAR_alert_email="you@example.com" TF_VAR_maximum_concurrency=4 \
  tofu -chdir=terraform plan
```

Expected: the mapping now shows `maximum_concurrency = 4`. A number that does not move is a typed-in value.

## Mark the pull request ready

```bash
printf '%s\n' SP8 >> milestones.txt
git add milestones.txt && git commit -m "chore(sp8): add SP8 to milestones.txt" && git push
```

One last look at the check on GitHub, which is the authority here. It follows the run your last push started, so it needs no new commit and no push:

```bash
bash .github/scripts/remote-check.sh
```

This reads the milestone check only: the `static` and `plan` jobs your `ci.yml` runs are separate required checks, and the pull request's **Checks** tab is where a red one shows.

When it prints `👍 SP8 passed.`, retitle the pull request and mark it ready:

```bash
gh pr edit --title "feat(sp8): cap the blast radius with a budget and two concurrency limits"
gh pr ready
```

Paste the plan's last line into the pull request body, and add the `DECISIONS.md` line for the cap while the reasoning is fresh.

## After the merge

Merge the pull request on GitHub, then clean up the branch:

```bash
git switch main && git pull
git branch -d sp8-caps
git fetch --prune
```

`git branch -d` refuses after a squash merge, because the branch's commits are not in `main`; `git branch -D sp8-caps` is the same delete. The remote branch is already gone: `delete_branch_on_merge` removes it when the pull request merges.
