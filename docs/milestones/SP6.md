# SP6: Ingest function and S3 trigger

| | |
|---|---|
| **Milestone** | SP6: Ingest function and S3 trigger |
| **Branch** | `sp6-ingest` |
| **Depends on** | SP5, merged |
| **Files you touch** | `terraform/s3.tf`, `terraform/ingest.tf`, `terraform/trigger.tf`, `terraform/backend.tf` (one provider added), `.gitignore`, `terraform/outputs.tf`, and four new files under `src/ingest/` |
| **Check** | Runs in this repo on every push to `sp6-ingest`, and locally with `.github/scripts/check.sh SP6`. Use this exact branch name |

## Goal

An object lands in a bucket, S3 invokes a function once per object, and the
function turns each object into one queue message that carries the time S3 saw it
land. That landing time is the clock every latency number in this project starts
from, so it comes from the event, never from the function's own clock.

You also build the packaging path here: TypeScript in `src/ingest/`, compiled to
`dist/`, zipped by the archive provider, deployed by the function resource. Both
later functions and the Compose services follow the same layout.

## Before step 1: two installs, and they are yours to approve

This milestone installs npm packages into `src/ingest/` and downloads one
Terraform provider, `hashicorp/archive`. Both are installs, so both need a yes
from you before Part 2:

- `npm install` writes `src/ingest/node_modules/` and `package-lock.json` from the
  manifest in Part 4. Nothing is installed globally, and the SDK stays a
  devDependency because the `nodejs24.x` runtime already ships SDK v3.
- `tofu init` downloads `hashicorp/archive` from the registry, exactly as it
  already downloaded `hashicorp/aws` in SP4.

Nothing in this milestone spends money or touches AWS: it is plan-only.

## Start your branch

```bash
git checkout main
git pull
git checkout -b sp6-ingest
git push -u origin sp6-ingest
```

## Part 1: The landing bucket

### s3.tf

#### 1. Your account ID

**Block Type:** `data`
**Data Source Type:** `aws_caller_identity`
**Data Source Name:** `current`

| Argument | Set To |
|---|---|
| (none) | this source takes no arguments. Its `account_id` attribute is the account you are signed in to |

**Tags:** data sources do not take tags.

**Docs:** [aws_caller_identity](https://registry.terraform.io/providers/hashicorp/aws/6.69.1/docs/data-sources/caller_identity) · [Data sources](https://developer.hashicorp.com/terraform/language/data-sources)

#### 2. The landing bucket

**Block Type:** `resource`
**Resource Type:** `aws_s3_bucket`
**Resource Name:** `landing`

| Argument | Set To |
|---|---|
| `bucket` | the `name_prefix` variable, `-landing-`, then the `account_id` of `data.aws_caller_identity.current`, using interpolation |
| `force_destroy` | `true` |
| `tags` | `Name` = the same value you gave `bucket`; `Role` = `"landing"`; `ManagedBy` = `"terraform"` |

**Tags:** yes, through the `tags` argument.

**Docs:** [aws_s3_bucket](https://registry.terraform.io/providers/hashicorp/aws/6.69.1/docs/resources/s3_bucket) · [Bucket naming rules](https://docs.aws.amazon.com/AmazonS3/latest/userguide/bucketnamingrules.html)

Bucket names are global across every account, so the account id is what keeps
yours from colliding with a stranger's. `force_destroy` is a demo-stack choice:
SP14 destroys this stack the same day, and a bucket that refuses to empty itself
turns a five-minute destroy into an afternoon.

#### 3. Versioning

**Block Type:** `resource`
**Resource Type:** `aws_s3_bucket_versioning`
**Resource Name:** `landing`

| Argument | Set To |
|---|---|
| `bucket` | the `id` of `aws_s3_bucket.landing` |
| `versioning_configuration` (nested block) | one block with `status` = `"Enabled"` |

**Tags:** not supported by this resource type.

**Docs:** [aws_s3_bucket_versioning](https://registry.terraform.io/providers/hashicorp/aws/6.69.1/docs/resources/s3_bucket_versioning)

Versioning is what makes the duplicate test honest: re-uploading an object to the
same key makes a second version, and the event still names the same key. It also
gives you the previous version of anything you overwrite by accident.

#### 4. Encryption

**Block Type:** `resource`
**Resource Type:** `aws_s3_bucket_server_side_encryption_configuration`
**Resource Name:** `landing`

| Argument | Set To |
|---|---|
| `bucket` | the `id` of `aws_s3_bucket.landing` |
| `rule` (nested block) | one block, containing the block below |
| `rule` → `apply_server_side_encryption_by_default` | one block with `sse_algorithm` = `"AES256"` |

**Tags:** not supported by this resource type.

**Docs:** [aws_s3_bucket_server_side_encryption_configuration](https://registry.terraform.io/providers/hashicorp/aws/6.69.1/docs/resources/s3_bucket_server_side_encryption_configuration)

`AES256` is SSE-S3, which costs nothing. SSE-KMS is the alternative and it adds a
charge per request plus a key policy to maintain, for a bucket that exists for a
day.

#### 5. Public access blocked

**Block Type:** `resource`
**Resource Type:** `aws_s3_bucket_public_access_block`
**Resource Name:** `landing`

| Argument | Set To |
|---|---|
| `bucket` | the `id` of `aws_s3_bucket.landing` |
| `block_public_acls` | `true` |
| `block_public_policy` | `true` |
| `ignore_public_acls` | `true` |
| `restrict_public_buckets` | `true` |

**Tags:** not supported by this resource type.

**Docs:** [aws_s3_bucket_public_access_block](https://registry.terraform.io/providers/hashicorp/aws/6.69.1/docs/resources/s3_bucket_public_access_block)

All four, not one. The four settings close four different paths, and a bucket
with three of them is a bucket somebody can still make public by accident.

> **✅ Checkpoint: step 1 (s3)**
> Save `s3.tf`, then run the check in your terminal before you commit:
> ```bash
> bash .github/scripts/check-local.sh
> ```
> Expected: `SP6 step 1 (s3)` ✅, with the steps you have not built yet still ❌. If a step is ❌, the `Next:` line under the summary names the brief section to re-read and what the check looked for: fix the file and run the same command again, with no commit and no push.
> Then format, commit, and push:
> ```bash
> tofu fmt -recursive
> git add -A && git commit -m "feat(sp6): add the landing bucket" && git push
> gh pr create --fill --draft
> ```
> The push runs the same check on GitHub, which is the authority and is consulted once per milestone, before `gh pr ready`: [SP1](SP1.md#how-to-see-your-results) explains both tiers.
> Step 1 turns ✅. Steps 2 to 8 stay ❌.

## Part 2: The ingest function

### `backend.tf`: the archive provider

`archive_file` comes from a second provider, so the existing
`required_providers` block gains one entry. A second `required_providers` block
is an error, so this goes in the file that already has one.

| Block Type | Block | Entry to add |
|---|---|---|
| `terraform` | `required_providers` | `archive = { source = "hashicorp/archive", version = "~> 2.0" }`, beside the existing `aws` entry |

**Docs:** [archive provider](https://registry.terraform.io/providers/hashicorp/archive/2.8.1/docs)

`tofu init` after this edit rewrites `.terraform.lock.hcl` with the archive
provider's checksums. Commit that file with the change: the lock file is tracked
in this repository, locally and in CI, and an uncommitted lock is how a plan job
and this machine end up resolving different providers.

### First, a source directory that builds

`archive_file` plans against `../src/ingest/dist`. A plan fails when that
directory is missing, and CI plans on every push, so the directory and a build
have to exist before this part's checkpoint.

Write `src/ingest/package.json` and `src/ingest/tsconfig.json` from the two tables
in Part 4 now (they are the same files; Part 4 does not repeat them), add one
placeholder `index.ts`, and build:

```bash
mkdir -p src/ingest
cd src/ingest
printf 'export const handler = async () => ({ sent: 0 });\n' > index.ts
npm install
npm run build
cd ../..
ls src/ingest/dist
```

Expected: `index.js`. This is the checkpoint that introduces `npm install`, the
lock file, and the build. From here on, CI's `npm ci` has a lock file to read and
`plan` has a directory to zip. Part 4 replaces the placeholder with the real
handler and the SDK wiring, then rebuilds.

### ingest.tf

Seven blocks: a log group, a trust policy document, the role, the role's
permissions, the inline policy, the zip, and the function itself. Write them in
that order; the function refers to all of them.

#### 6. The log group

**Block Type:** `resource`
**Resource Type:** `aws_cloudwatch_log_group`
**Resource Name:** `ingest`

| Argument | Set To |
|---|---|
| `name` | `/aws/lambda/` then the `name_prefix` variable and `-ingest` |
| `retention_in_days` | `14` |
| `tags` | `Name` = `<name_prefix>-ingest`; `Role` = `"ingest"`; `ManagedBy` = `"terraform"` |

**Tags:** yes, with the `tags` argument.

**Docs:** [aws_cloudwatch_log_group](https://registry.terraform.io/providers/hashicorp/aws/6.69.1/docs/resources/cloudwatch_log_group) · [Log retention](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/Working-with-log-groups-and-streams.html)

Terraform owns the group so that it has a retention period and dies with the
stack. A group Lambda makes for itself has neither, and it outlives the destroy.

#### 7. The trust policy

**Block Type:** `data`
**Data Source Type:** `aws_iam_policy_document`
**Data Source Name:** `lambda_assume`

| Argument | Set To |
|---|---|
| `statement` (nested block) | one block, with the four settings below |
| `statement` → `effect` | `"Allow"` |
| `statement` → `actions` | `["sts:AssumeRole"]` |
| `statement` → `principals` (nested block) | one block with `type` = `"Service"` and `identifiers` = `["lambda.amazonaws.com"]` |

**Tags:** data sources do not take tags.

**Docs:** [aws_iam_policy_document](https://registry.terraform.io/providers/hashicorp/aws/6.69.1/docs/data-sources/iam_policy_document) · [Role terms](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_terms-and-concepts.html)

A trust policy says who may become the role. This one names the Lambda service
and nothing else, so no person and no other service can use these permissions.
SP7's role reuses this document rather than declaring a second copy.

#### 8. The role

**Block Type:** `resource`
**Resource Type:** `aws_iam_role`
**Resource Name:** `ingest`

| Argument | Set To |
|---|---|
| `name` | `<name_prefix>-ingest`, using interpolation |
| `assume_role_policy` | the `json` of `data.aws_iam_policy_document.lambda_assume` |
| `tags` | `Name` = the same value you gave `name`; `Role` = `"ingest"`; `ManagedBy` = `"terraform"` |

**Tags:** yes, with the `tags` argument.

**Docs:** [aws_iam_role](https://registry.terraform.io/providers/hashicorp/aws/6.69.1/docs/resources/iam_role)

#### 9. What the function may do

**Block Type:** `data`
**Data Source Type:** `aws_iam_policy_document`
**Data Source Name:** `ingest_permissions`

Three statements, each with a `sid`, an `effect` of `"Allow"`, `actions`, and
`resources`:

| Statement `sid` | `actions` | `resources` |
|---|---|---|
| `ReadLanding` | `["s3:GetObject"]` | the `arn` of `aws_s3_bucket.landing`, then `/*`, using interpolation |
| `SendEvents` | `["sqs:SendMessage"]` | the `arn` of `aws_sqs_queue.main` |
| `WriteLogs` | `["logs:CreateLogStream", "logs:PutLogEvents"]` | the `arn` of `aws_cloudwatch_log_group.ingest`, then `:*`, using interpolation |

**Tags:** data sources do not take tags.

**Docs:** [IAM policies](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies.html) · [Lambda execution role](https://docs.aws.amazon.com/lambda/latest/dg/lambda-intro-execution-role.html)

Three statements and no wildcards, because the handler makes exactly three kinds
of call: read one object, send one message, write its own logs. `s3:GetObject`
on `/*` without `s3:ListBucket` means the function can read the object the event
names and cannot go looking for others. The log statements are on this function's
own group, not on `*`: the broad version is what
`AWSLambdaBasicExecutionRole` grants, and it is unnecessary once Terraform owns
the group.

#### 10. The inline policy

**Block Type:** `resource`
**Resource Type:** `aws_iam_role_policy`
**Resource Name:** `ingest`

| Argument | Set To |
|---|---|
| `name` | `<name_prefix>-ingest` |
| `role` | the `id` of `aws_iam_role.ingest` |
| `policy` | the `json` of `data.aws_iam_policy_document.ingest_permissions` |

**Tags:** not supported by this resource type.

**Docs:** [aws_iam_role_policy](https://registry.terraform.io/providers/hashicorp/aws/6.69.1/docs/resources/iam_role_policy)

Inline, not attached: this policy exists for one role and has no life of its own,
and inline policies die with the role instead of lingering as orphans.

#### 11. The zip

**Block Type:** `data`
**Data Source Type:** `archive_file`
**Data Source Name:** `ingest`

| Argument | Set To |
|---|---|
| `type` | `"zip"` |
| `source_dir` | the path module, then `/../src/ingest/dist`, using interpolation |
| `output_path` | the path module, then `/build/ingest.zip`, using interpolation |

**Tags:** data sources do not take tags.

**Docs:** [archive_file](https://registry.terraform.io/providers/hashicorp/archive/2.8.1/docs/data-sources/file) · [path.module](https://developer.hashicorp.com/terraform/language/expressions/references)

The archive provider zips the folder at plan time, so the folder has to exist
before the plan. That is why the build comes before `plan` in this milestone and
in CI. `dist/` and `build/` are ignored by git in this milestone.

#### 12. The function

**Block Type:** `resource`
**Resource Type:** `aws_lambda_function`
**Resource Name:** `ingest`

| Argument | Set To |
|---|---|
| `function_name` | `<name_prefix>-ingest` |
| `role` | the `arn` of `aws_iam_role.ingest` |
| `handler` | `"index.handler"` |
| `runtime` | `"nodejs24.x"` |
| `architectures` | `["arm64"]` |
| `memory_size` | `256` |
| `timeout` | `30` |
| `filename` | the `output_path` of `data.archive_file.ingest` |
| `source_code_hash` | the `output_base64sha256` of `data.archive_file.ingest` |
| `environment` (nested block) | one block, `variables` = an object with `QUEUE_URL` = the `url` of `aws_sqs_queue.main` |
| `logging_config` (nested block) | one block, `log_format` = `"JSON"`, `log_group` = the `name` of `aws_cloudwatch_log_group.ingest` |
| `tags` | `Name` = `<name_prefix>-ingest`; `Role` = `"ingest"`; `ManagedBy` = `"terraform"` |

**Tags:** yes, with the `tags` argument.

**Docs:** [aws_lambda_function](https://registry.terraform.io/providers/hashicorp/aws/6.69.1/docs/resources/lambda_function) · [Node.js runtime](https://docs.aws.amazon.com/lambda/latest/dg/lambda-nodejs.html) · [JSON log format](https://docs.aws.amazon.com/lambda/latest/dg/monitoring-cloudwatchlogs-logformat.html)

Why `nodejs24.x` and never `nodejs20.x`: Lambda deprecated Node 20 on
2026-04-30, and every older example still says `nodejs20.x`. A function on a
deprecated runtime keeps working until the day it does not.

Why `logging_config` names the log group instead of using `depends_on`: that
attribute is what orders the function after the group, so the function cannot
make a group of the same name first and then fail because it already exists. It
also gives every record as JSON, so a field passed to the logger arrives as a key
instead of a substring.

Why `source_code_hash`: without it, a rebuilt zip keeps the same key in S3 and
the function never updates. The hash changes when the code changes.

> **✅ Checkpoint: step 2 (ingest function)**
> Save `ingest.tf`, the `archive` entry in `backend.tf`, the updated
> `.terraform.lock.hcl`, and the built `src/ingest/`, then run the check in your terminal before you commit:
> ```bash
> bash .github/scripts/check-local.sh
> ```
> Expected: `SP6 step 2 (ingest)` ✅, with the steps you have not built yet still ❌. If a step is ❌, the `Next:` line under the summary names the brief section to re-read and what the check looked for: fix the file and run the same command again, with no commit and no push.
> Then format, commit, and push:
> ```bash
> tofu fmt -recursive
> git add -A && git commit -m "feat(sp6): add the ingest function, its role, and its log group" && git push
> ```
> The push runs the same check on GitHub, which is the authority and is consulted once per milestone, before `gh pr ready`: [SP1](SP1.md#how-to-see-your-results) explains both tiers.
> Steps 2 and 3 turn ✅: the function's shape, and the three references the mock
> provider cannot evaluate. Steps 4 to 8 stay ❌.

## Part 3: The trigger

### trigger.tf

Two blocks, in this order: the permission, then the notification that depends on
it.

#### 13. The permission

**Block Type:** `resource`
**Resource Type:** `aws_lambda_permission`
**Resource Name:** `s3_invoke`

| Argument | Set To |
|---|---|
| `statement_id` | `"AllowS3Invoke"` |
| `action` | `"lambda:InvokeFunction"` |
| `function_name` | the `function_name` of `aws_lambda_function.ingest` |
| `principal` | `"s3.amazonaws.com"` |
| `source_arn` | the `arn` of `aws_s3_bucket.landing` |

**Tags:** not supported by this resource type.

**Docs:** [aws_lambda_permission](https://registry.terraform.io/providers/hashicorp/aws/6.69.1/docs/resources/lambda_permission) · [Granting S3 permission to invoke a function](https://docs.aws.amazon.com/lambda/latest/dg/with-s3-tutorial.html)

`source_arn` is the part that matters. Without it, any bucket in any account can
invoke this function. With it, only this bucket can.

#### 14. The notification

**Block Type:** `resource`
**Resource Type:** `aws_s3_bucket_notification`
**Resource Name:** `landing`

| Argument | Set To |
|---|---|
| `bucket` | the `id` of `aws_s3_bucket.landing` |
| `depends_on` | `[aws_lambda_permission.s3_invoke]`, written on one line |
| `lambda_function` (nested block) | one block with `lambda_function_arn` = the `arn` of `aws_lambda_function.ingest`, and `events` = `["s3:ObjectCreated:*"]` |

**Tags:** not supported by this resource type.

**Docs:** [aws_s3_bucket_notification](https://registry.terraform.io/providers/hashicorp/aws/6.69.1/docs/resources/s3_bucket_notification) · [S3 event notifications](https://docs.aws.amazon.com/AmazonS3/latest/userguide/EventNotifications.html)

`depends_on` is not decoration. S3 validates the destination when the
notification is written, and the destination is only valid once the permission
exists. **Unverified here:** this ordering failure is what the old guide recorded,
and no run in this workspace could reproduce it without an account. If your first
apply succeeds without the ordering, the line costs nothing; if it fails, the
error *"Unable to validate the following destination configurations"* is the
evidence, and the fix is this line rather than a second apply. Without the ordering, the apply fails with *"Unable to validate the
following destination configurations"*, and the second apply usually succeeds,
which is how people learn to re-run applies instead of fixing the order.

`ObjectCreated:*` covers both a new object and a new version of an existing key,
which is what the duplicate test needs.

> **✅ Checkpoint: step 4 (trigger)**
> Save `trigger.tf`, then run the check in your terminal before you commit:
> ```bash
> bash .github/scripts/check-local.sh
> ```
> Expected: `SP6 step 4 (trigger)` ✅, with the steps you have not built yet still ❌. If a step is ❌, the `Next:` line under the summary names the brief section to re-read and what the check looked for: fix the file and run the same command again, with no commit and no push.
> Then format, commit, and push:
> ```bash
> tofu fmt -recursive
> git add -A && git commit -m "feat(sp6): add the S3 permission and notification" && git push
> ```
> The push runs the same check on GitHub, which is the authority and is consulted once per milestone, before `gh pr ready`: [SP1](SP1.md#how-to-see-your-results) explains both tiers.
> Steps 4 and 5 turn ✅: the permission and the notification, and the ordering
> line the mock cannot see. Steps 6 to 8 stay ❌.

## Part 4: The function's source

Four files under `src/ingest/`. The handler logic and its entry point are
separate on purpose: the logic never imports an SDK, so a test can run it with
stub clients and no AWS account.

#### 15. `src/ingest/package.json`

| Key | Set To |
|---|---|
| `name` | `"ingest"` |
| `private` | `true` |
| `scripts.build` | `"tsc"` |
| `devDependencies` | `@aws-sdk/client-s3` `^3.0.0`, `@aws-sdk/client-sqs` `^3.0.0`, `@types/node` `^24.0.0`, `typescript` `^5.0.0` |

The SDK is a dev dependency because the `nodejs24.x` runtime already ships
SDK v3. It has to be there to compile, and it must not be in the zip.

**Docs:** [npm package.json](https://docs.npmjs.com/cli/configuring-npm/package-json)

#### 16. `src/ingest/tsconfig.json`

| Key | Set To |
|---|---|
| `compilerOptions.target` | `"ES2022"` |
| `compilerOptions.module` | `"CommonJS"` |
| `compilerOptions.moduleResolution` | `"Node"` |
| `compilerOptions.outDir` | `"dist"` |
| `compilerOptions.rootDir` | `"."` |
| `compilerOptions.strict` | `true` |
| `compilerOptions.esModuleInterop` | `true` |
| `compilerOptions.skipLibCheck` | `true` |
| `include` | `["index.ts", "handler.ts"]` |

**Docs:** [tsconfig reference](https://www.typescriptlang.org/tsconfig)

#### 17. `src/ingest/handler.ts`

**File Type:** `typescript`
**File Name:** `src/ingest/handler.ts`

The file exports one factory and two types:

| Export | Shape |
|---|---|
| `IngestDeps` | an interface with `getObject(bucket: string, key: string): Promise<string>` and `sendMessage(body: string): Promise<void>` |
| `S3Event` | the event: an object with `Records`, each record holding `eventTime` and an `s3` object with `bucket.name` and `object.key` |
| `createHandler(deps)` | takes an `IngestDeps` and returns an async handler that takes an `S3Event` and returns `{ sent: number }` |

The handler's behavior, in order, for each record:

1. Read the bucket from `record.s3.bucket.name` and the key from
   `record.s3.object.key`.
2. Decode the key: replace `+` with a space, then `decodeURIComponent`. S3
   encodes both in the event, and a key with a space arrives as `+`.
3. Call `deps.getObject(bucket, key)`. The result is the object's body as text.
4. Parse it as JSON. A body that is not JSON is a failure: let the error out and
   do not send a message for that record.
5. Send one message with `deps.sendMessage`, as a JSON string of the parsed body
   spread into an object, plus `landedAt` = `record.eventTime`. Do not use the
   function's own clock.
6. Count the message and return `{ sent }` when every record is done.

One message per record, in order. Do not batch, and do not catch errors: a
throw fails the invocation, which is how the S3 retry path stays visible.

Do not add the idempotency key here. The overview's message contract lists it as
arriving in SP9, where the consumer's conditional write decides how it is
computed. A key guessed now would be replaced then, and the two would disagree.

#### 18. `src/ingest/index.ts`

**File Type:** `typescript`
**File Name:** `src/ingest/index.ts`

It builds the two clients, wires them into the factory, and exports the result.
The SDK calls, with their arguments:

| Call | Arguments |
|---|---|
| `new S3Client` | an empty object; the runtime supplies the Region and the credentials |
| `new SQSClient` | an empty object |
| `new GetObjectCommand` | `{ Bucket: bucket, Key: key }` |
| `s3.send` | the command. The body is a stream, so read it with `Body.transformToString()` |
| `new SendMessageCommand` | `{ QueueUrl: QUEUE_URL, MessageBody: body }` |
| `sqs.send` | the command |
| the queue URL | `process.env.QUEUE_URL`, read once at module load |

The file exports `handler` = `createHandler({ getObject, sendMessage })`. The two
methods use the clients above; nothing else belongs in this file.

**Docs:** [S3 GetObject](https://docs.aws.amazon.com/AmazonS3/latest/API/API_GetObject.html) · [SQS SendMessage](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/APIReference/API_SendMessage.html) · [SDK v3 GetObjectCommand](https://docs.aws.amazon.com/AWSJavaScriptSDK/v3/latest/client/s3/command/GetObjectCommand/)

Build both files once, so the zip has something in it:

```bash
cd src/ingest && npm install && npm run build && cd ../..
ls src/ingest/dist
```

Expected: `handler.js` and `index.js`. `npm install` writes a
`package-lock.json`; commit it, because CI runs `npm ci`, which needs one.

> **✅ Checkpoint: steps 6 and 7 (handler and wiring)**
> Save the four files, then run the check in your terminal before you commit:
> ```bash
> bash .github/scripts/check-local.sh
> ```
> Expected: `SP6 step 6 (handler)` and `SP6 step 7 (wiring)` ✅, with the steps you have not built yet still ❌. If a step is ❌, the `Next:` line under the summary names the brief section to re-read and what the check looked for: fix the file and run the same command again, with no commit and no push.
> Then format, commit, and push:
> ```bash
> tofu fmt -recursive
> git add -A && git commit -m "feat(sp6): add the ingest handler and its entry point" && git push
> ```
> The push runs the same check on GitHub, which is the authority and is consulted once per milestone, before `gh pr ready`: [SP1](SP1.md#how-to-see-your-results) explains both tiers.
> Step 6 turns ✅ (the handler's behavior, run with stub clients) and step 7
> turns ✅ (the SDK calls, checked as text). Step 8 stays ❌.

## Part 5: Two more outputs

#### 19. Add to `outputs.tf`

| Block Type | Output Name | `value` set to |
|---|---|---|
| `output` | `landing_bucket` | the `id` of `aws_s3_bucket.landing` |
| `output` | `ingest_function_name` | the `function_name` of `aws_lambda_function.ingest` |

Give each one a `description` of one sentence. Leave the five outputs from SP5
alone.

> **✅ Checkpoint: step 8 (outputs)**
> Save `outputs.tf`, then run the check in your terminal before you commit:
> ```bash
> bash .github/scripts/check-local.sh
> ```
> Expected: `SP6 step 8 (outputs)` ✅, and the summary says `👍 SP6 passed.` If a step is ❌, the `Next:` line under the summary names the brief section to re-read and what the check looked for: fix the file and run the same command again, with no commit and no push.
> Then format, commit, and push:
> ```bash
> tofu fmt -recursive
> git add -A && git commit -m "feat(sp6): expose the bucket and the function name" && git push
> ```
> The push runs the same check on GitHub, which is the authority and is consulted once per milestone, before `gh pr ready`: [SP1](SP1.md#how-to-see-your-results) explains both tiers.
> Step 8 turns ✅, and every row is ✅.

## Check it

Run `bash .github/scripts/check-local.sh` at every checkpoint. What its output means, how to fix a red step, and when GitHub is the authority are explained once, in [SP1](SP1.md#how-to-see-your-results); this brief's own steps and its own failures are below.

### How to see your results


The check prints one row per step, in the order the parts appear, and a step is
green only when its file is in place and every assertion in it passes. A red row
prints the reason underneath it, naming the file, the value, or the attribute
that is wrong. CI prints the same rows in the job summary, so the local run and
the remote run read identically.


**Locally:** `.github/scripts/check.sh SP6`, which prints one row per step and
`👍 SP6 passed.` at the end. **On the pull request:** **Actions**, newest run,
**Summary**.

| Step | Checks |
|---|---|
| 1 (s3) | the bucket's name, `force_destroy`, versioning, SSE-S3, all four public-access settings, the tags, and that the name follows the prefix |
| 2 (ingest) | the log group and its retention, the trust policy, the role, the three permission statements with their exact actions and resources, the inline policy, the zip's paths, and every function setting including `nodejs24.x` |
| 3 (references) | the three references the mock cannot evaluate: `assume_role_policy`, `policy`, and `source_code_hash` |
| 4 (trigger) | the permission's principal, action, and `source_arn`, and the notification's target and event list |
| 5 (order) | `depends_on = [aws_lambda_permission.s3_invoke]` on one line, and the notification using the function's `arn` attribute |
| 6 (handler) | the handler's behavior, run with stub clients: the landing time from the event, the key decoded, one message per record |
| 7 (wiring) | the SDK calls in `index.ts`: `GetObjectCommand` with bucket and key, `QueueUrl`, `MessageBody` |
| 8 (outputs) | the two new outputs |

Reading a failure:

- **"The runtime must be nodejs24.x"**: an older example's `nodejs20.x` is still
  in the file. Node 20 is deprecated.
- **"must deploy the archive's output_path"**: `filename` and
  `source_code_hash` have to point at the archive data source, not at a typed-in
  path.
- **Step 5 ❌ on `depends_on`**: write it on one line, exactly as the table says.
  A multi-line list is correct Terraform and fails a text check, which is the one
  place this project prefers the one-line form.

## Done when (plan only, no apply)

Three things to prove, and none of them costs anything.

The build first, because the archive provider needs the folder:

```bash
export TF_VAR_alert_email="you@example.com"
(cd src/ingest && npm ci && npm run build)
tofu -chdir=terraform init
tofu -chdir=terraform plan
```

Expected, at the end: `Plan: 13 to add, 0 to change, 0 to destroy.` Those are
SP5's three resources plus ten here: the bucket and its three settings, the log
group, the role, the inline policy, the function, the permission, and the
notification.

Then confirm the zip holds the compiled files:

```bash
unzip -l terraform/build/ingest.zip
```

Expected: `index.js` and `handler.js`, and no `node_modules` folder.

Read the plan's function section before you move on: `runtime` is `nodejs24.x`,
`architectures` is `arm64`, `QUEUE_URL` names the main queue, and the log group
is named. If `filename` shows a `.zip` under `src/ingest` rather than
`terraform/build`, the archive paths are wrong.

Do not apply. SP12 is the first apply, and the caps land in SP8 first. If you
applied by mistake, `tofu -chdir=terraform destroy` removes everything and the
bucket is empty anyway.

## Mark the pull request ready
```bash
printf '%s\n' SP6 >> milestones.txt
git add milestones.txt && git commit -m "chore(sp6): add SP6 to milestones.txt" && git push
```

One last look at the check on GitHub, which is the authority here. It follows the run your last push started, so it needs no new commit and no push:

```bash
bash .github/scripts/remote-check.sh
```

This reads the milestone check only: the `static` and `plan` jobs your `ci.yml` runs are separate required checks, and the pull request's **Checks** tab is where a red one shows.

When it prints `👍 SP6 passed.`, retitle the pull request and mark it ready:

```bash
gh pr edit --title "feat(sp6): add the landing bucket, the ingest function, and the S3 trigger"
gh pr ready
```

Paste the plan's last line into the pull request body. A reviewer reads the diff
against this brief, then merges.
