# SP9: Idempotent writes and partial batch failures

| | |
|---|---|
| **Milestone** | SP9: Idempotent writes and partial batch failures |
| **Branch** | `sp9-idempotency` |
| **Depends on** | SP8, merged |
| **Files you touch** | `src/consumer/handler.ts`, `src/consumer/index.ts`, `src/ingest/handler.ts` |
| **Check** | Runs in this repo on every push to `sp9-idempotency`, and locally with `bash .github/scripts/check-local.sh`. Use this exact branch name |

## Goal

Two behaviors carry the architectural argument, and both are testable without an AWS account.

**The conditional write.** SQS delivers at least once, so the same message will arrive twice. The consumer writes with a condition that the key does not exist, and a duplicate is a success, not an error. A second delivery writes nothing.

**The partial batch report.** The handler returns the ids of the messages that genuinely failed, and nothing else. SQS deletes every message that is not listed, so one poison message stops taking nine healthy ones with it.

This milestone also settles the idempotency key in one place: the ingest function, once per message.

## Start your branch

```bash
git checkout main
git pull
git checkout -b sp9-idempotency
git push -u origin sp9-idempotency
```

## Part 1: The consumer's handler

#### 1. `src/consumer/handler.ts`

**File Type:** `typescript`
**File Name:** `src/consumer/handler.ts`

Exports:

| Export | Shape |
|---|---|
| `DuplicateEventError` | a class that extends `Error`, with `name` set to `"DuplicateEventError"` |
| `ConsumerDeps` | an interface with `writeRow(row): Promise<void>` and `now(): string`. The row is `{ idempotencyKey: string, payload: string, processedAt: string }` |
| `BatchItemFailure` | `{ itemIdentifier: string }` |
| `SqsEvent` | `{ Records: { messageId: string, body: string }[] }` |
| `createHandler(deps)` | takes a `ConsumerDeps` and returns an async handler that takes an `SqsEvent` and returns `{ batchItemFailures }` |

The handler's behavior, for each record in order:

1. Parse `record.body` as JSON.
2. If the parsed body has no `idempotencyKey`, that is a failure, not a duplicate: log the message id, add it to the list, and skip the write. DynamoDB would reject the write anyway, and a key of `undefined` would collapse every such message onto one row.
3. Call `deps.writeRow` with `idempotencyKey` = the parsed body's value, `payload` = `record.body` exactly as received, and `processedAt` = `deps.now()`.
4. If the write succeeds, do nothing else. The message is not listed, so SQS deletes it.
5. If the write rejects with `DuplicateEventError`, or with an error whose `name` is `"ConditionalCheckFailedException"`, treat it as success: the row is already there. Do not list it.
6. Any other error: log the message id and the error, and add `{ itemIdentifier: record.messageId }` to the list.
7. Return `{ batchItemFailures }`, even when the list is empty.

Why `payload` is the raw body and not a re-serialized copy: SP13 reads `landedAt` out of the stored payload, and re-serializing can reorder or reformat it. The row should hold what the queue delivered.

Why the duplicate check looks at `name` as well as the class: the SDK throws its own error class for a failed condition, and the wiring in Part 3 turns that into `DuplicateEventError`. The name check is the second line of defense for a body that reaches the handler some other way.

**✅ Checkpoint: step 1 (consumer handler)**
Save `handler.ts`, then run the check in your terminal before you commit:

```bash
bash .github/scripts/check-local.sh
```

Expected: `SP9 step 1 (consumer)` ✅, with the steps you have not built yet still ❌. If a step is ❌, the `Next:` line names the section to re-read: fix it and run the same command again before committing. Then format, commit, and push:

```bash
tofu fmt -recursive
git add -A && git commit -m "feat(sp9): add the conditional write and the batch report" && git push
gh pr create --fill --draft
```

The push runs the same check on GitHub, which is the authority and is consulted once per milestone, before `gh pr ready`: [SP1](SP1.md#how-to-see-your-results) explains both tiers. Step 1 turns ✅. Steps 2 and 3 stay ❌ until Parts 2 and 3.

## Part 2: The key, settled once

#### 2. `src/ingest/handler.ts`, one line

Inside the object that the handler sends, after the parsed body is spread in, add:

| Field | Set To |
|---|---|
| `idempotencyKey` | the parsed body's `idempotencyKey` when it has one, otherwise the decoded object key |

**Docs:** [Nullish coalescing](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Operators/Nullish_coalescing) · [DynamoDB conditional writes](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/WorkingWithItems.html)

This is the only place the key is derived. The consumer reads it, the duplicate test depends on it, and the Compose ingest service does the same thing.

A re-upload to the same key produces the same key, so the second delivery is a duplicate and writes nothing. Uploading identical bytes under a different key is a different event and legitimately writes a second row. That is why SP12's duplicate test uploads to the same key.

**What the key cannot see.** The key is the object key, so re-uploading *different* bytes to the same key counts as a duplicate and the new content is dropped. S3 versioning keeps that version, and the event carries `s3.object.versionId` and `s3.object.sequencer`, but neither is in the key here because the duplicate test depends on a re-upload being a duplicate. If you ever need content-addressed deduplication, add the ETag or the version id to the key and change SP12's test to re-upload identical bytes instead.

**✅ Checkpoint: step 2 (ingest key)**
Save the file, then run the check in your terminal before you commit:

```bash
bash .github/scripts/check-local.sh
```

Expected: `SP9 step 2 (ingest-key)` ✅, with the steps you have not built yet still ❌. If a step is ❌, the `Next:` line names the section to re-read: fix it and run the same command again before committing. Then format, commit, and push:

```bash
tofu fmt -recursive
git add -A && git commit -m "feat(sp9): settle the idempotency key in the ingest function" && git push
```

The push runs the same check on GitHub, which is the authority and is consulted once per milestone, before `gh pr ready`: [SP1](SP1.md#how-to-see-your-results) explains both tiers. Step 2 turns ✅. Step 3 depends on Part 3.

## Part 3: The consumer's entry point

#### 3. `src/consumer/index.ts`

**File Type:** `typescript`
**File Name:** `src/consumer/index.ts`

It builds the table client, wires it into the factory, and exports the result. The SDK calls, with their arguments:

| Call | Arguments |
|---|---|
| `new DynamoDBClient` | an empty object |
| `new PutItemCommand` | `TableName` = `process.env.TABLE_NAME`, `Item` with `idempotency_key` = `{ S: row.idempotencyKey }`, `payload` = `{ S: row.payload }`, `processed_at` = `{ S: row.processedAt }`, and `ConditionExpression` = `"attribute_not_exists(idempotency_key)"` |
| `ddb.send` | the command, inside a `try` |
| the `catch` | if the error is the SDK's `ConditionalCheckFailedException`, throw a `DuplicateEventError`; otherwise rethrow |
| `now` | a function returning `new Date().toISOString()` |

Import `ConditionalCheckFailedException` from the DynamoDB client package next to `DynamoDBClient` and `PutItemCommand`.

**Docs:** [PutItem](https://docs.aws.amazon.com/amazondynamodb/latest/APIReference/API_PutItem.html) · [DynamoDB SDK v3 client](https://docs.aws.amazon.com/AWSJavaScriptSDK/v3/latest/client/dynamodb/) ·

The condition is the whole mechanism: `attribute_not_exists` on the partition key makes DynamoDB reject the write when the key is present, and the error tells the handler "already written". The alternative, a read followed by a write, has a race between them and no way to close it.

**✅ Checkpoint: step 3 (wiring)**
Save `index.ts`, then run the check in your terminal before you commit:

```bash
bash .github/scripts/check-local.sh
```

Expected: `SP9 step 3 (wiring)` ✅, and the summary says `👍 SP9 passed.` If a step is ❌, the `Next:` line names the section to re-read: fix it and run the same command again before committing. Then format, commit, and push:

```bash
tofu fmt -recursive
git add -A && git commit -m "feat(sp9): write rows with a conditional put" && git push
```

The push runs the same check on GitHub, which is the authority and is consulted once per milestone, before `gh pr ready`: [SP1](SP1.md#how-to-see-your-results) explains both tiers. Step 3 turns ✅, and every row is ✅.

## Check it

Run `bash .github/scripts/check-local.sh` at every checkpoint. What its output means, how to fix a red step, and when GitHub is the authority are explained once, in [SP1](SP1.md#how-to-see-your-results); this brief's own steps and its own failures are below.

### How to see your results


The check prints one row per step, in the order the parts appear, and a step is green only when its file is in place and every assertion in it passes. A red row prints the reason underneath it, naming the file, the value, or the attribute that is wrong. CI prints the same rows in the job summary, so the local run and the remote run read identically.


**Locally:** `bash .github/scripts/check-local.sh`. The two handler steps run with `bun test` and stub clients, so there is no account and no network. **On the pull request:** **Actions**, newest run, **Summary**.

| Step | Checks |
|---|---|
| 1 (consumer) | with stub writers: one row per message with the body verbatim and the injected clock, a duplicate reported as success, the SDK's own error name treated the same way, only the genuinely failed message listed, and an empty batch reported empty |
| 2 (ingest-key) | the body's key kept when present, the object key used when not, and the same object key twice producing the same key |
| 3 (wiring) | the conditional expression, the three item attributes, the error class, and `TABLE_NAME` |

Reading a failure:

- **`expect(rows).toEqual([...])` fails on `payload`**: the handler stored `JSON.stringify(parsed)` instead of `record.body`.
- **A duplicate lands in `batchItemFailures`**: the duplicate check has to `continue` before the failure list is appended to.
- **Step 3 ❌ on `ConditionExpression`**: the condition goes inside the `PutItemCommand` input, spelled exactly `attribute_not_exists(idempotency_key)`.

## Done when (still no apply)

The check proves the logic. The plan proves nothing broke on the way:

```bash
export TF_VAR_alert_email="you@example.com"
(cd src/ingest && npm ci && npm run build)
(cd src/consumer && npm ci && npm run build)
tofu -chdir=terraform init
tofu -chdir=terraform plan
```

Expected: `Plan: 19 to add, 0 to change, 0 to destroy.` Nothing exists yet, so every resource is an add; on both functions the `source_code_hash` is the one this build produced, and it changes on the next build whenever the code does.

Then answer one question in `DECISIONS.md`, in one sentence (append it to the file SP4 created): what happens when SQS delivers the same message twice. The sentence has to mention a condition expression.

## Mark the pull request ready

```bash
printf '%s\n' SP9 >> milestones.txt
git add milestones.txt && git commit -m "chore(sp9): add SP9 to milestones.txt" && git push
```

One last look at the check on GitHub, which is the authority here. It follows the run your last push started, so it needs no new commit and no push:

```bash
bash .github/scripts/remote-check.sh
```

This reads the milestone check only: the `static` and `plan` jobs your `ci.yml` runs are separate required checks, and the pull request's **Checks** tab is where a red one shows.

When it prints `👍 SP9 passed.`, retitle the pull request and mark it ready:

```bash
gh pr edit --title "feat(sp9): write idempotently and report partial batch failures"
gh pr ready
```

## After the merge

Merge the pull request on GitHub, then clean up the branch:

```bash
git switch main && git pull
git branch -d sp9-idempotency
git fetch --prune
```

`git branch -d` refuses after a squash merge, because the branch's commits are not in `main`; `git branch -D sp9-idempotency` is the same delete. The remote branch is already gone: `delete_branch_on_merge` removes it when the pull request merges.
