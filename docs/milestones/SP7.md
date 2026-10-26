# SP7: Consumer function and event source mapping

| | |
|---|---|
| **Milestone** | SP7: Consumer function and event source mapping |
| **Branch** | `sp7-consumer` |
| **Depends on** | SP6, merged |
| **Files you touch** | `terraform/consumer.tf`, `terraform/mapping.tf`, `terraform/outputs.tf`, `src/consumer/package.json`, `src/consumer/tsconfig.json`, `src/consumer/handler.ts`, `src/consumer/index.ts` |
| **Check** | Runs in this repo on every push to `sp7-consumer`, and locally with `bash .github/scripts/check-local.sh`. Use this exact branch name |

## Goal

The second function, and the mapping that feeds it. The mapping is where at-least-once delivery becomes manageable: with `ReportBatchItemFailures`, the handler tells SQS which messages failed, and only those come back. One poison message stops poisoning a batch of ten.

The handler at this stage is a skeleton. SP9 writes the conditional put and the partial-failure report; SP7 proves the wiring, the role, and the mapping.

## Start your branch

```bash
git checkout main
git pull
git checkout -b sp7-consumer
git push -u origin sp7-consumer
```

## Part 1: The consumer

### consumer.tf

Six blocks: the log group, the role, the permissions, the inline policy, the zip, and the function. The trust policy document from SP6 is reused as it is; a second copy would drift.

#### 1. The log group

**Block Type:** `resource`
**Resource Type:** `aws_cloudwatch_log_group`
**Resource Name:** `consumer`

| Argument | Set To |
|---|---|
| `name` | `/aws/lambda/` then `<name_prefix>-consumer` |
| `retention_in_days` | `14` |
| `tags` | `Name` = `<name_prefix>-consumer`; `Role` = `"consumer"`; `ManagedBy` = `"terraform"` |

**Tags:** yes, with the `tags` argument.

**Docs:** [aws_cloudwatch_log_group](https://registry.terraform.io/providers/hashicorp/aws/6.69.1/docs/resources/cloudwatch_log_group)

#### 2. The role

**Block Type:** `resource`
**Resource Type:** `aws_iam_role`
**Resource Name:** `consumer`

| Argument | Set To |
|---|---|
| `name` | `<name_prefix>-consumer` |
| `assume_role_policy` | the `json` of `data.aws_iam_policy_document.lambda_assume`, the one SP6 wrote |
| `tags` | `Name` = `<name_prefix>-consumer`; `Role` = `"consumer"`; `ManagedBy` = `"terraform"` |

**Tags:** yes, with the `tags` argument.

**Docs:** [aws_iam_role](https://registry.terraform.io/providers/hashicorp/aws/6.69.1/docs/resources/iam_role)

#### 3. What the consumer may do

**Block Type:** `data`
**Data Source Type:** `aws_iam_policy_document`
**Data Source Name:** `consumer_permissions`

Three statements:

| Statement `sid` | `actions` | `resources` |
|---|---|---|
| `WriteRows` | `["dynamodb:PutItem"]` | the `arn` of `aws_dynamodb_table.events` |
| `ReadQueue` | `["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]` | the `arn` of `aws_sqs_queue.main` |
| `WriteLogs` | `["logs:CreateLogStream", "logs:PutLogEvents"]` | the `arn` of `aws_cloudwatch_log_group.consumer`, then `:*` |

**Tags:** data sources do not take tags.

**Docs:** [IAM policies](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies.html) · [SQS and Lambda IAM](https://docs.aws.amazon.com/lambda/latest/dg/with-sqs.html)

The three queue actions are not for the handler: the event source mapping polls, receives, and deletes using the function's own role. AWS checks the role when the mapping is created, so a role without `sqs:ReceiveMessage` fails the mapping with an access-denied error instead of producing one that sits idle. The policy also has to exist first: IAM changes take a few seconds to propagate, which is why the function names it in `depends_on` in item 5.

`dynamodb:PutItem` only. No update, no delete, no query: the handler writes one row and does nothing else.

#### 4. The inline policy

**Block Type:** `resource`
**Resource Type:** `aws_iam_role_policy`
**Resource Name:** `consumer`

| Argument | Set To |
|---|---|
| `name` | `<name_prefix>-consumer` |
| `role` | the `id` of `aws_iam_role.consumer` |
| `policy` | the `json` of `data.aws_iam_policy_document.consumer_permissions` |

**Tags:** not supported by this resource type.

**Docs:** [aws_iam_role_policy](https://registry.terraform.io/providers/hashicorp/aws/6.69.1/docs/resources/iam_role_policy)

#### 5. The zip and the function

**Block Type:** `data`, then `resource` **Data Source / Resource Names:** `archive_file.consumer`, then `aws_lambda_function.consumer`

| Argument | Set To |
|---|---|
| `archive_file.consumer.type` | `"zip"` |
| `archive_file.consumer.source_dir` | the path module, then `/../src/consumer/dist` |
| `archive_file.consumer.output_path` | the path module, then `/build/consumer.zip` |
| `function.function_name` | `<name_prefix>-consumer` |
| `function.role` | the `arn` of `aws_iam_role.consumer` |
| `function.handler` | `"index.handler"` |
| `function.runtime` | `"nodejs24.x"` |
| `function.architectures` | `["arm64"]` |
| `function.memory_size` | `256` |
| `function.timeout` | `30` |
| `function.filename` | the `output_path` of `data.archive_file.consumer` |
| `function.source_code_hash` | the `output_base64sha256` of `data.archive_file.consumer` |
| `function.environment` (nested) | `variables` = an object with `TABLE_NAME` = the `name` of `aws_dynamodb_table.events` |
| `function.logging_config` (nested) | `log_format` = `"JSON"`, `log_group` = the `name` of `aws_cloudwatch_log_group.consumer` |
| `function.depends_on` | `[aws_iam_role_policy.consumer]`, written on one line, so the function is not created before its inline policy exists |
| `function.tags` | `Name` = `<name_prefix>-consumer`; `Role` = `"consumer"`; `ManagedBy` = `"terraform"` |

**Tags:** the function takes tags; the archive data source does not.

**Docs:** [aws_lambda_function](https://registry.terraform.io/providers/hashicorp/aws/6.69.1/docs/resources/lambda_function) · [archive_file](https://registry.terraform.io/providers/hashicorp/archive/2.8.1/docs/data-sources/file)

The timeout is 30 seconds, and the queue's visibility timeout is 180, which is six times it. If you change one, change the other in the same commit.

### `src/consumer/` at this stage

Four files, with the same layout as `src/ingest/`:

| File | Set To |
|---|---|
| `package.json` | `name` `"consumer"`, `private` true, `scripts.build` `"tsc"`, devDependencies `@aws-sdk/client-dynamodb` `^3.0.0`, `@types/node` `^24.0.0`, `typescript` `^5.0.0` |
| `tsconfig.json` | the same compiler options as `src/ingest/tsconfig.json`, with `include` `["index.ts", "handler.ts"]` |
| `handler.ts` | exports `SqsEvent` and a `handler` that logs the batch size and returns `{ batchItemFailures: [] }` |
| `index.ts` | exports the handler: `export { handler } from "./handler";` |

This is a skeleton, and SP9 replaces both TypeScript files. It exists so the zip is real and the mapping has something to invoke. The log line is what a tester reads to see that the mapping delivers at all.

**Docs:** [Event source mappings](https://docs.aws.amazon.com/lambda/latest/dg/invocation-eventsourcemapping.html) · [Partial batch responses](https://docs.aws.amazon.com/lambda/latest/dg/services-sqs-errorhandling.html)

Build it before the checkpoint, because `plan` zips `../src/consumer/dist` and CI plans on every push:

`npm install` here downloads the DynamoDB client and the TypeScript compiler into `src/consumer/node_modules/`. That is an install, so approve it before the block:

```bash
cd src/consumer && npm install && npm run build && cd ../..
ls src/consumer/dist
```

Expected: `index.js` and `handler.js`. `npm install` writes `package-lock.json`; commit it, because CI runs `npm ci`.

**✅ Checkpoint: steps 1 and 2 (consumer)**
Save `consumer.tf`, the four files under `src/consumer/`, and the build output, then run the check in your terminal before you commit:

```bash
bash .github/scripts/check-local.sh
```

Expected: `SP7 step 1 (consumer)` and `SP7 step 2 (references)` ✅, with the steps you have not built yet still ❌. If a step is ❌, the `Next:` line names the section to re-read: fix it and run the same command again before committing. Then format, commit, and push:

```bash
tofu fmt -recursive
git add -A && git commit -m "feat(sp7): add the consumer function and its role" && git push
gh pr create --fill --draft
```

The push runs the same check on GitHub, which is the authority and is consulted once per milestone, before `gh pr ready`: [SP1](SP1.md#how-to-see-your-results) explains both tiers. Steps 1 and 2 turn ✅. Steps 3 and 4 stay ❌.

## Part 2: The mapping

### mapping.tf

#### 6. The event source mapping

**Block Type:** `resource`
**Resource Type:** `aws_lambda_event_source_mapping`
**Resource Name:** `consumer`

| Argument | Set To |
|---|---|
| `event_source_arn` | the `arn` of `aws_sqs_queue.main` |
| `function_name` | the `arn` of `aws_lambda_function.consumer` |
| `batch_size` | `10` |
| `function_response_types` | `["ReportBatchItemFailures"]` |
| `tags` | `Name` = `<name_prefix>-consumer-mapping`; `Role` = `"consumer-mapping"`; `ManagedBy` = `"terraform"` |

**Tags:** yes, with the `tags` argument.

**Docs:** [aws_lambda_event_source_mapping](https://registry.terraform.io/providers/hashicorp/aws/6.69.1/docs/resources/lambda_event_source_mapping) · [SQS batch handling](https://docs.aws.amazon.com/lambda/latest/dg/services-sqs-errorhandling.html)

`ReportBatchItemFailures` is the setting the whole failure story depends on. Without it, a handler that throws sends the whole batch back, and nine messages that were fine are redelivered because one was not. With it, the handler returns the failed message ids and SQS deletes the rest.

`batch_size` 10 is a ceiling, not a quota: SQS hands over as many as are waiting, up to ten, so an invocation can receive one message or ten. It is small on purpose, because the duplicate test in SP12 uploads a handful of events and a batch that carries several of them at once is what exercises the partial-failure report.

No `scaling_config` yet. SP8 adds it, and the cap belongs there.

**✅ Checkpoint: step 3 (mapping)**
Save `mapping.tf`, then run the check in your terminal before you commit:

```bash
bash .github/scripts/check-local.sh
```

Expected: `SP7 step 3 (mapping)` ✅, with the steps you have not built yet still ❌. If a step is ❌, the `Next:` line names the section to re-read: fix it and run the same command again before committing. Then format, commit, and push:

```bash
tofu fmt -recursive
git add -A && git commit -m "feat(sp7): connect the queue to the consumer" && git push
```

The push runs the same check on GitHub, which is the authority and is consulted once per milestone, before `gh pr ready`: [SP1](SP1.md#how-to-see-your-results) explains both tiers. Step 3 turns ✅. Step 4 is still ❌.

## Part 3: The output

#### 7. Add to `outputs.tf`

| Block Type | Output Name | `value` set to |
|---|---|---|
| `output` | `consumer_function_name` | the `function_name` of `aws_lambda_function.consumer` |

One sentence of `description`. Leave the other seven outputs alone.

**✅ Checkpoint: step 4 (outputs)**
Save `outputs.tf`, then run the check in your terminal before you commit:

```bash
bash .github/scripts/check-local.sh
```

Expected: `SP7 step 4 (outputs)` ✅, and the summary says `👍 SP7 passed.` If a step is ❌, the `Next:` line names the section to re-read: fix it and run the same command again before committing. Then format, commit, and push:

```bash
tofu fmt -recursive
git add -A && git commit -m "feat(sp7): expose the consumer function name" && git push
```

The push runs the same check on GitHub, which is the authority and is consulted once per milestone, before `gh pr ready`: [SP1](SP1.md#how-to-see-your-results) explains both tiers. Step 4 turns ✅, and every row is ✅.

## Check it

Run `bash .github/scripts/check-local.sh` at every checkpoint. What its output means, how to fix a red step, and when GitHub is the authority are explained once, in [SP1](SP1.md#how-to-see-your-results); this brief's own steps and its own failures are below.

### How to see your results


The check prints one row per step, in the order the parts appear, and a step is green only when its file is in place and every assertion in it passes. A red row prints the reason underneath it, naming the file, the value, or the attribute that is wrong. CI prints the same rows in the job summary, so the local run and the remote run read identically.


**Locally:** `bash .github/scripts/check-local.sh`. **On the pull request:** **Actions**, newest run, **Summary**.

| Step | Checks |
|---|---|
| 1 (consumer) | the log group and retention, the role reusing the shared trust policy, the three statements with exact actions and resources, the archive paths, and every function setting |
| 2 (references) | `assume_role_policy`, `policy`, and `source_code_hash`, which the mock cannot evaluate |
| 3 (mapping) | the queue and function references, `batch_size` 10, and `ReportBatchItemFailures` |
| 4 (outputs) | `consumer_function_name` |

Reading a failure:

- **"The consumer role must reuse the shared trust policy"**: reference `data.aws_iam_policy_document.lambda_assume.json`. A second trust document is the failure this check exists for.
- **"ReadQueue must allow ..."**: all three queue actions, on the main queue's ARN. `sqs:SendMessage` belongs to the ingest role, not this one.
- **Step 3 ❌ on `function_response_types`**: the value is a list with one exact string, and the spelling is `ReportBatchItemFailures`.

## Done when (plan only, no apply)

```bash
export TF_VAR_alert_email="you@example.com"
(cd src/consumer && npm install && npm run build)
tofu -chdir=terraform init
tofu -chdir=terraform plan
```

Expected: `Plan: 18 to add, 0 to change, 0 to destroy.` That is SP6's thirteen plus five here: the log group, the role, the inline policy, the function, and the mapping.

Read the mapping's section in the plan: `batch_size` 10, `function_response_types` holds `ReportBatchItemFailures`, and `enabled` is true. Then confirm both zips exist:

```bash
ls terraform/build
```

Expected: `consumer.zip` and `ingest.zip`. A missing one means the build above did not run, and `plan` would have failed before this point.

Do not apply. SP8 adds the caps, and SP12 is the first apply.

## Mark the pull request ready

```bash
printf '%s\n' SP7 >> milestones.txt
git add milestones.txt && git commit -m "chore(sp7): add SP7 to milestones.txt" && git push
```

One last look at the check on GitHub, which is the authority here. It follows the run your last push started, so it needs no new commit and no push:

```bash
bash .github/scripts/remote-check.sh
```

This reads the milestone check only: the `static` and `plan` jobs your `ci.yml` runs are separate required checks, and the pull request's **Checks** tab is where a red one shows.

When it prints `👍 SP7 passed.`, retitle the pull request and mark it ready:

```bash
gh pr edit --title "feat(sp7): add the consumer function and the event source mapping"
gh pr ready
```

Paste the plan's last line into the pull request body.

## After the merge

Merge the pull request on GitHub, then clean up the branch:

```bash
git switch main && git pull
git branch -d sp7-consumer
git fetch --prune
```

`git branch -d` refuses after a squash merge, because the branch's commits are not in `main`; `git branch -D sp7-consumer` is the same delete. The remote branch is already gone: `delete_branch_on_merge` removes it when the pull request merges.
