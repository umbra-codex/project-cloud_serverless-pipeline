# SP2: Remote state bucket

| | |
|---|---|
| **Milestone** | SP2: Remote state bucket |
| **Branch** | `sp2-state` |
| **Depends on** | SP1, merged |
| **Files you touch** | `terraform/bootstrap/providers.tf` (new), `terraform/bootstrap/variables.tf` (new), `terraform/bootstrap/storage.tf` (new), `terraform/bootstrap/backend.tf` (new), `terraform/backend.tf` |
| **Check** | Runs in this repo on every push to `sp2-state`, and locally with `.github/scripts/check.sh SP2`. Use this exact branch name |

## Goal

One bucket that outlives every stack, holding the state of the pipeline and of
the small configuration that built the bucket itself.

The order is the whole milestone, and it is the part that trips first-timers: a
configuration cannot keep its state in a bucket that does not exist yet. So the
bootstrap configuration starts on **local state**, creates the bucket, and only
then moves its own state into that bucket. Nothing else in the guide has this
shape, and it is the reason `terraform/bootstrap/` is a separate folder with its
own state key.

## Start your branch

```bash
git checkout main
git pull
git checkout -b sp2-state
git push -u origin sp2-state
```

## Part 1: The bucket, from a configuration on local state

`terraform/bootstrap/` is a small root module: its own provider, its own inputs,
and the bucket. It is applied by you, and SP14 never destroys it, because the CI
role from SP3 lives in the same state.

### backend.tf

One `terraform` block, with the version pin and the provider requirement. No
backend inside it yet: Part 2 adds that, after the bucket exists.

| Block Type | Block | Contents |
|---|---|---|
| `terraform` | `required_version` | `">= 1.10"` |
| `terraform` | `required_providers` | `aws = { source = "hashicorp/aws", version = "~> 6.0" }` |

A module may have only one `terraform` block, which is why the version pin, the
provider requirement, and later the backend all live in this one file.

### providers.tf

| Block Type | Block | Arguments |
|---|---|---|
| `provider` | `aws` | `region = var.region` |

**Docs:** [aws provider](https://registry.terraform.io/providers/hashicorp/aws/6.69.1/docs)

### variables.tf

| Block Type | Variable | Type | Default |
|---|---|---|---|
| `variable` | `region` | `string` | `"us-east-1"` |
| `variable` | `state_bucket` | `string` | your bucket name, from Part 1 step 1 |

### storage.tf

Four blocks, one resource each for the bucket and three settings. They are
separate resources because the AWS provider split them: a bucket with versioning,
encryption and a public-access block is four resources, not one.

| Block Type | Resource Type | Resource Name |
|---|---|---|
| `resource` | `aws_s3_bucket` | `state` |
| `resource` | `aws_s3_bucket_versioning` | `state` |
| `resource` | `aws_s3_bucket_server_side_encryption_configuration` | `state` |
| `resource` | `aws_s3_bucket_public_access_block` | `state` |

| Resource | Argument | Set To |
|---|---|---|
| `aws_s3_bucket.state` | `bucket` | `var.state_bucket` |
| `aws_s3_bucket_versioning.state` | `bucket` | the `id` of `aws_s3_bucket.state` |
| `aws_s3_bucket_versioning.state` | `versioning_configuration.status` (nested block) | `"Enabled"` |
| `aws_s3_bucket_server_side_encryption_configuration.state` | `bucket` | the `id` of the bucket |
| `aws_s3_bucket_server_side_encryption_configuration.state` | `rule` (nested block) with `apply_server_side_encryption_by_default.sse_algorithm` | `"AES256"` |
| `aws_s3_bucket_public_access_block.state` | `bucket` | the `id` of the bucket |
| `aws_s3_bucket_public_access_block.state` | `block_public_acls`, `block_public_policy`, `ignore_public_acls`, `restrict_public_buckets` | all four `true` |

**Docs:** [aws_s3_bucket](https://registry.terraform.io/providers/hashicorp/aws/6.69.1/docs/resources/s3_bucket) · [versioning](https://registry.terraform.io/providers/hashicorp/aws/6.69.1/docs/resources/s3_bucket_versioning) · [encryption](https://registry.terraform.io/providers/hashicorp/aws/6.69.1/docs/resources/s3_bucket_server_side_encryption_configuration) · [public access block](https://registry.terraform.io/providers/hashicorp/aws/6.69.1/docs/resources/s3_bucket_public_access_block)

**Tags:** `Name` set to `var.state_bucket`, on the bucket only.

### Choose the name, then apply

Bucket names are global across every AWS account, so the name has to carry
something unique. Use your account ID from SP1:

```bash
export TF_VAR_state_bucket="tfstate-$(aws sts get-caller-identity --query Account --output text)-serverless"
echo "$TF_VAR_state_bucket"
```

Then, from `terraform/bootstrap/`. Read the first line before you run the second:
`tofu init` downloads the `hashicorp/aws` provider for this folder, about 100 MB,
into `terraform/bootstrap/.terraform/`. Nothing global is installed, and this is
the repository's first provider download, so approve it now.

```bash
cd terraform/bootstrap
tofu init
tofu apply
cd ../..
```

Expected: `Plan: 4 to add, 0 to change, 0 to destroy.` Four resources: the bucket
and its three settings. This is real money in the sense that S3 storage is billed,
and it is pennies a month for state files.

`tofu init` wrote `.terraform.lock.hcl` here. Commit it: it is the first lock file this repository has, and CI reads it.

If the apply fails with `BucketAlreadyExists`, the name is taken globally. Pick
another; nothing was created, so there is nothing to clean up.

> **✅ Checkpoint: step 1 (bucket)**
> Save the four files, then run the check in your terminal before you commit:
> ```bash
> bash .github/scripts/check-local.sh
> ```
> Expected: `SP2 step 1 (bucket)` ✅, with the steps you have not built yet still ❌. If a step is ❌, the `Next:` line under the summary names the brief section to re-read and what the check looked for: fix the file and run the same command again, with no commit and no push.
> Then format, commit, and push:
> ```bash
> tofu fmt -recursive
> git add -A && git commit -m "feat(sp2): create the state bucket from a bootstrap config" && git push
> gh pr create --fill --draft
> ```
> The push runs the same check on GitHub, which is the authority and is consulted once per milestone, before `gh pr ready`: [SP1](SP1.md#how-to-see-your-results) explains both tiers.
> Step 1 turns ✅: the bucket, versioning, encryption, and the public-access block.
> Steps 2 and 3 stay ❌.

## Part 2: Move the bootstrap state into the bucket it just made

The bucket exists now. The configuration that made it still keeps its state in
`terraform.tfstate` on this machine, which is the thing this whole milestone is
about.

Add a backend block to `terraform/bootstrap/backend.tf`:

| Argument | Set To |
|---|---|
| `bucket` | `var.state_bucket` is not allowed in a backend block, so the literal name you exported |
| `key` | `"bootstrap/terraform.tfstate"`, its own key, so SP14 cannot reach it |
| `region` | `"us-east-1"` |
| `encrypt` | `true` |
| `use_lockfile` | `true`, native locking, no DynamoDB table |

**Docs:** [S3 backend](https://opentofu.org/docs/language/settings/backends/s3/)

Then move the state, answering `yes` when it asks:

```bash
cd terraform/bootstrap
tofu init -migrate-state
```

Expected: the prompt names the old local state and the new S3 key, and after
`yes`, `tofu plan` reads **No changes**. If the plan wants to create the bucket
again, the migration copied nothing: check that the backend block's bucket is the
one the apply created.

Delete the local `terraform.tfstate` only after that plan says No changes. It is
gitignored, so it was never committed, and leaving it behind is how two states
start to disagree.

> **✅ Checkpoint: step 2 (migrate)**
> Save `terraform/bootstrap/backend.tf`, then run the check in your terminal before you commit:
> ```bash
> bash .github/scripts/check-local.sh
> ```
> Expected: `SP2 step 2 (migrate)` ✅, with the steps you have not built yet still ❌. If a step is ❌, the `Next:` line under the summary names the brief section to re-read and what the check looked for: fix the file and run the same command again, with no commit and no push.
> Then format, commit, and push:
> ```bash
> tofu fmt -recursive
> git add -A && git commit -m "feat(sp2): move the bootstrap state into the bucket" && git push
> ```
> The push runs the same check on GitHub, which is the authority and is consulted once per milestone, before `gh pr ready`: [SP1](SP1.md#how-to-see-your-results) explains both tiers.
> Step 2 turns ✅: the bootstrap backend block, its own key, and native locking.
> Step 3 stays ❌.

## Part 3: The pipeline's backend

The root configuration gets the same bucket and a different key.

| Argument | Set To |
|---|---|
| `bucket` | the same literal name |
| `key` | `"serverless-pipeline/terraform.tfstate"` |
| `region` | `"us-east-1"` |
| `encrypt` | `true` |
| `use_lockfile` | `true` |

Keep the `required_version` line from SP0 above it.

Then:

```bash
cd ../..
tofu -chdir=terraform init
```

Expected: `Successfully configured the backend "s3"!` There is no state file in
the bucket yet: a plan writes none, and the first one appears at the apply in
SP12. A plan does write a small `.tflock` object and delete it again, and because
versioning is on, `aws s3api list-object-versions --bucket "$TF_VAR_state_bucket"`
can show that object and a delete marker. That is normal, and worth knowing
before you see it and think something is wrong.

> **✅ Checkpoint: step 3 (root backend)**
> Save `terraform/backend.tf`, then run the check in your terminal before you commit:
> ```bash
> bash .github/scripts/check-local.sh
> ```
> Expected: `SP2 step 3 (root-backend)` ✅, and the summary says `👍 SP2 passed.` If a step is ❌, the `Next:` line under the summary names the brief section to re-read and what the check looked for: fix the file and run the same command again, with no commit and no push.
> Then format, commit, and push:
> ```bash
> tofu fmt -recursive
> git add -A && git commit -m "feat(sp2): point the root config at the bucket" && git push
> printf '%s\n' SP2 >> milestones.txt
> 
> git add milestones.txt && git commit -m "chore(sp2): add SP2 to milestones.txt" && git push
> ```
> The push runs the same check on GitHub, which is the authority and is consulted once per milestone, before `gh pr ready`: [SP1](SP1.md#how-to-see-your-results) explains both tiers.
> Step 3 turns ✅, and every row is ✅.

## Check it

Run `bash .github/scripts/check-local.sh` at every checkpoint. What its output means, how to fix a red step, and when GitHub is the authority are explained once, in [SP1](SP1.md#how-to-see-your-results); this brief's own steps and its own failures are below.

### How to see your results


The check prints one row per step, in the order the parts appear. Step 1 prints twice, because it has two files: `sp2-1-bucket.check` reads the
configuration as text, and `terraform/bootstrap/tests/sp2-1-bucket.tftest.hcl`
plans it with a mocked provider. The plan runs with the bootstrap as its root, so
no child module and no extra download is involved. Steps 2 and 3 are text reads.

| Step | Checks |
|---|---|
| 1 (bucket) | two rows from two files: a text read of the four bucket resources, and a mocked plan that asserts the same settings |
| 2 (migrate) | the bootstrap backend block, its own key, encryption, and native locking |
| 3 (root backend) | the root backend block, the pipeline key, and no local state path |

Reading a failure:

- **Step 1 ❌ on `block_public_acls`**: the public-access block is a separate
  resource from the bucket, and one of the four settings is missing or false.
- **Step 2 ❌ on `use_lockfile`**: the backend is on, but without native locking,
  two applies can interleave. It is one line.

## Done when (things only the console can show)

1. `aws s3api get-bucket-versioning --bucket "$TF_VAR_state_bucket"` prints
   `Enabled`.
2. `aws s3api get-public-access-block --bucket "$TF_VAR_state_bucket"` shows all
   four settings `true`.
3. `aws s3api list-objects-v2 --bucket "$TF_VAR_state_bucket" --prefix bootstrap/`
   shows a `terraform.tfstate` object, which is the migration working.
4. The bucket is **not** public and has no bucket policy. Nothing needs one: no
   one but your account and the CI role reads it.

## Mark the pull request ready
One last look at the check on GitHub, which is the authority here. It follows the run your last push started, so it needs no new commit and no push:

```bash
bash .github/scripts/remote-check.sh
```

When it prints `👍 SP2 passed.`, retitle the pull request and mark it ready:

```bash
gh pr edit --title "feat(sp2): create the state bucket and move the state into it"
gh pr ready
```

