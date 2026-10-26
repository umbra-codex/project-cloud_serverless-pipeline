# SP4: The CI skeleton

| | |
|---|---|
| **Milestone** | SP4: The CI skeleton |
| **Branch** | `sp4-ci` |
| **Depends on** | SP3, merged, with the role proven by the throwaway workflow |
| **Files you touch** | `.github/workflows/ci.yml` (new), `README.md`, `DECISIONS.md` (new), and you delete `.github/workflows/oidc-check.yaml`. `milestone-check.yml` is not edited |
| **Check** | Runs in this repo on every push to `sp4-ci`, and locally with `bash .github/scripts/check-local.sh`. The branch name decides which milestone CI checks, so use this exact name. |

## Goal

The bootstrap stack from SP2 and SP3 is in place: the state bucket, the OIDC provider, the CI plan role, and a check runner that already runs formatting, validation, and this milestone's step tests. What is missing is a workflow that does the two separate jobs the design calls for, one that scans and one that holds an AWS identity, and a badge a reader can click.

Two jobs, not one:

- **`static`** runs formatting, validation, `tflint`, and `checkov`. It gets no `id-token` and no credentials, because the scanners are third-party code and a job holding a role session is the wrong place to run them. It does not run the step tests: `milestone-check.yml` does that, and it is the only job that needs Bun.
- **`plan`** is the only job with `id-token: write`. It assumes the CI role, reads the remote state, builds both Lambda bundles, and runs a plan.

This is also the milestone where the throwaway workflow from SP3 goes away.

## How to read a brief

Every brief from here on reads the same way.

- **Goal** says what is true when the milestone is finished. If a line in it is not true yet, the milestone is not finished, however many steps are green.
- **Start your branch** is the branch name the check reads. A mismatch means the check runs nothing and looks green, so make it exact.
- **Part N** is one sitting. Each part lists the files to write or edit, the settings each one carries in a table, and every settings row it demands sits in a block whose type is named. A workflow or a configuration file that is given in full says so; nothing else is pasted, because typing it is the work.
- **Checkpoint** at the end of a part is the command to run and the step rows that turn green. Run it before you move on: a step that does not turn green tells you which part is short.
- **Item** and **step** are two numbers for the same work. The headings inside a part are items, so `item 13` is a heading; the check's rows are steps, so `step 4 (trigger)` is a check. A `Next:` line that names items is telling you which headings to re-read, not which row failed.
- **Check it** is the same check from outside the milestone, including the formatting, `init`, and `validate` gates that run before any step.
- **Done when** lists the settings the check cannot read, because they live in a dashboard or in your own judgment. Read them and do them; nothing will fail if you skip them, and the milestone will still be wrong.
- A block labeled **Expected** shows output, not a command. If yours differs, the difference is the finding.

Every checkpoint is complete as written. Never shorten one: if a step is red, the answer is in the part, not in a smaller check.

One file is in every milestone's diff and never in the tables above: `milestones.txt`. Each milestone ends by appending its own ID on its own line and committing that separately, `printf '%s\n' SP4 >> milestones.txt`, because the check runner and the SHIP step read that list to know what the repository claims to contain.

## Start your branch

Do this before you change any file. It gets the latest `main`, which has the bootstrap stack and the check runner, and branches from it:

```bash
git checkout main
git pull
git checkout -b sp4-ci
git push -u origin sp4-ci
```

The last command publishes the branch, so every later push in this brief knows where to go. You will open a draft pull request at your first checkpoint. Until the branch has a commit that `main` does not, the provider refuses to open one.

### Commit messages

Every commit follows [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/): `<type>(<scope>): <description>`. The scope is the milestone ID in lowercase, and each checkpoint gives you the exact message.

| Type | Use it for | Example |
|---|---|---|
| `ci` | the workflow | `ci(sp4): split the check into static and plan jobs` |
| `docs` | the README | `docs(sp4): add the CI badge` |
| `chore` | bookkeeping, like `milestones.txt` | `chore(sp4): add SP4 to milestones.txt` |

## Part 1: Two workflows, three jobs

Two workflows and three jobs: two in `ci.yml`, one in `milestone-check.yml`:

- `.github/workflows/milestone-check.yml` is the file the scaffold carried. It holds one job, `check`, which runs `.github/scripts/check.sh`. It stays as it is: it runs the step tests for the branch you are on and needs no identity.
- `.github/workflows/ci.yml` is new in this milestone. It is the project's own CI, and it is the one the badge and the branch protection point at. It holds two jobs, `static` and `plan`.

Why split them: the step tests need Bun and the whole test suite, and they run on any branch. The scan and the plan are what a reviewer reads on a pull request, and the plan needs an identity. One workflow doing both would either hand an AWS session to a job that runs `bun test`, or make every branch pay for a plan.

**File Type:** `workflow`
**File Name:** `.github/workflows/ci.yml`

| Setting | Set To |
|---|---|
| `name` | `ci` |
| `on` | `pull_request` and `push` to `main`, plus `workflow_dispatch` |
| `permissions` (top level) | `contents: read`. No `id-token` here: it is granted per job, never to the whole run |
| `concurrency.group` | `ci-${{ github.ref }}` |
| `concurrency.cancel-in-progress` | `true`, so a newer push cancels the older run |
| job `static` → `runs-on` | `ubuntu-latest` |
| job `static` → step 1 | `actions/checkout@v7` |
| job `static` → step 2 | `opentofu/setup-opentofu@v2` with `tofu_version: 1.13.1` |
| job `static` → step 3 | `tofu fmt -check -recursive` |
| job `static` → step 4 | `tofu -chdir=terraform init -backend=false -input=false`, then `tofu -chdir=terraform validate -no-color`. No backend read: this job holds no identity, and validate does not need state |
| job `static` → step 5 | `terraform-linters/setup-tflint@v6` with `tflint_version: v0.64.0` |
| job `static` → step 6 | `tflint --init`, then `tflint --recursive --config "$(pwd)/.tflint.hcl"`, with `GITHUB_TOKEN` from the workflow in `env` |
| job `static` → step 7 | `bridgecrewio/checkov-action@v12.2915.0`, with `directory: terraform`, `framework: terraform`, `soft_fail: false` |
| job `plan` → `needs` | `static` |
| job `plan` → `permissions` | `id-token: write` and `contents: read` |
| job `plan` → `env` | `TF_VAR_alert_email: ${{ secrets.ALERT_EMAIL }}`. The budget's email input has no default, so the plan has to be handed one |
| job `plan` → step 1 | `actions/checkout@v7` |
| job `plan` → step 2 | `opentofu/setup-opentofu@v2` with `tofu_version: 1.13.1` |
| job `plan` → step 3 | `actions/setup-node@v4` with `node-version: 24` |
| job `plan` → step 4 | a `run` that loops over `src/*/`, skips a folder with no `package.json`, and runs `npm ci` and `npm run build` in each folder it finds. Nothing exists there yet, so it does nothing today and does the right thing from SP6 on |
| job `plan` → step 5 | `aws-actions/configure-aws-credentials@v4` with `role-to-assume: ${{ vars.AWS_CI_ROLE_ARN }}` and `aws-region: us-east-1`. v4 is the pin this build used; a newer major exists and is not raised here on a guess (see SP3) |
| job `plan` → step 6 | `tofu -chdir=terraform init`, which reads the S3 backend and the remote state |
| job `plan` → step 7 | `tofu -chdir=terraform plan -no-color -input=false` |

The whole file, because the step test anchors on its indentation line for line. Two jobs, `push` on `main` only, and no top-level `id-token`:

```yaml
name: ci

on:
  pull_request:
  push:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: read      # top level stays read-only; id-token is granted per job, never to the whole run

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

jobs:
  static:
    name: static
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7

      - uses: opentofu/setup-opentofu@v2
        with:
          tofu_version: 1.13.1

      - run: tofu fmt -check -recursive

      - name: Validate
        run: |
          tofu -chdir=terraform init -backend=false -input=false
          tofu -chdir=terraform validate -no-color

      - uses: terraform-linters/setup-tflint@v6
        with:
          tflint_version: v0.64.0

      - name: tflint
        run: |
          tflint --init
          tflint --recursive --config "$(pwd)/.tflint.hcl"
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}

      - uses: bridgecrewio/checkov-action@v12.2915.0
        with:
          directory: terraform
          framework: terraform
          soft_fail: false

  plan:
    name: plan
    needs: static
    runs-on: ubuntu-latest
    permissions:
      # the only job that may mint an AWS session
      id-token: write
      contents: read
    env:
      # the budget's email input has no default
      TF_VAR_alert_email: ${{ secrets.ALERT_EMAIL }}
    steps:
      - uses: actions/checkout@v7

      - uses: opentofu/setup-opentofu@v2
        with:
          tofu_version: 1.13.1

      - uses: actions/setup-node@v4
        with:
          node-version: 24

      - name: Build Lambda bundles
        run: |
          for dir in src/*/; do
            [ -f "$dir/package.json" ] || continue
            ( cd "$dir" && npm ci && npm run build )
          done

      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ vars.AWS_CI_ROLE_ARN }}
          aws-region: us-east-1

      - run: tofu -chdir=terraform init

      - run: tofu -chdir=terraform plan -no-color -input=false
```

Every `ci.yml` anchor in `sp4-1-workflow.check` matches a line of that listing exactly, which is why the two comments above the keys sit on their own lines: `id-token: write` is on the `plan` job only, never at the top, and `TF_VAR_alert_email` exists because the budget's email input has no default.

The `[ -f "$dir/package.json" ] || continue` line is what keeps this honest from SP6 on: `src/` is empty today, so the loop matches nothing and the step passes. Do not delete it when the first function lands. Nothing in `plan` may move into `static`: the credentials step and everything after it belong to the job that holds the token, and the three scanners belong to the job that does not.

### The milestone check workflow, unchanged

`.github/workflows/milestone-check.yml` already exists and already works. Its shape, for reference, and the only thing you touch in it: nothing here.

| Setting | Set To |
|---|---|
| `name` | `milestone-check` |
| `on` | `push` on any branch, plus `workflow_dispatch` with one input: `milestone`, description "Milestone to check, e.g. SP8. Leave blank to use the branch name.", `required: false`, default empty |
| job `check` → steps | checkout, OpenTofu 1.13.1, Bun 1.4.3, then a step with `id: target` that turns the branch name into a milestone, then `actions/cache@v6` for `~/.terraform.d/plugin-cache` keyed on `terraform/.terraform.lock.hcl`, then `.github/scripts/check.sh $MILESTONE all` |

The `target` step reads its inputs from `env`, never from `${{ }}` inside the `run:` line: a branch name is attacker-controlled text in a fork, and text interpolated into a shell line is a command. The script refuses anything that is not two to four letters and digits.

**Docs:** [Workflow syntax](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax) · [Workflow commands and step outputs](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-commands) · [opentofu/setup-opentofu](https://github.com/opentofu/setup-opentofu) · [checkov-action](https://github.com/bridgecrewio/checkov-action) · [tflint setup action](https://github.com/terraform-linters/setup-tflint)

Why the milestone is read from an environment variable and never pasted into a shell line: a branch name is attacker-controlled text in a fork, and text interpolated into `run:` is a command. Here the script reads `$MILESTONE`, refuses anything that is not a short ID, and only then uses it.

Why `checkov-action` is pinned to a release tag instead of `@master`: `@master` means whatever that repository holds at the moment your job starts. A tag is better than that and weaker than a commit SHA: the upstream repository can move a tag, and it cannot rewrite a SHA. So this pin protects against drift, not against a compromised upstream, and pinning by SHA is the stricter choice if you want it. The tag stays in this guide because it stays readable in a diff.

The suppressions live in `.checkov.yaml` beside the workflow, and each one carries its reason on the lines above it: twelve in total. Read them before you argue with a run, because a skip with a reason is a decision and a skip without one is a hole.

Why `static` has no `id-token`: `setup-tflint` and `checkov-action` are third party. A job that can mint an AWS session should not also run them.

**✅ Checkpoint: step 1 (workflow)**
Save `.github/workflows/ci.yml`, then run the check in your terminal before you commit:

```bash
bash .github/scripts/check-local.sh
```

Expected: `SP4 step 1 (workflow)` ✅, with the steps you have not built yet still ❌. If a step is ❌, the `Next:` line names the section to re-read: fix it and run the same command again before committing. Then format, commit, and push:

```bash
tofu fmt -recursive
git add -A && git commit -m "ci(sp4): split the check into static and plan jobs" && git push
gh pr create --fill --draft
```

The push runs the same check on GitHub, which is the authority and is consulted once per milestone, before `gh pr ready`: [SP1](SP1.md#how-to-see-your-results) explains both tiers. Step 1 turns ✅. Steps 2 and 3 stay ❌ until you finish Parts 2 and 3.

### The decision log

Create the decision log now, not in SP15. Every milestone from here adds a line while the reasoning is fresh, and SP15 only reads it back into the README:

| File | Set To |
|---|---|
| `DECISIONS.md` | first line `# Decisions`, then one dated line per choice: `- 2026-10-22: chose two workflows over one, because the step tests need Bun on any branch and the plan needs an identity` |

The rule for a line: what you chose, what you chose it over, and the reason. One sentence. A line you cannot write that way is a decision you have not made yet.

## Part 2: The badge

**File Type:** `markdown`
**File Name:** `README.md`

| Line | Set To |
|---|---|
| 1 | `# serverless-pipeline` |
| 2 | empty |
| 3 | the badge, as one line: an image link to `https://github.com/OWNER/project-cloud_serverless-pipeline/actions/workflows/ci.yml/badge.svg`, wrapped in a link to `https://github.com/OWNER/project-cloud_serverless-pipeline/actions/workflows/ci.yml` |
| 4 | empty |
| 5 and on | a two-line description of the repo, then leave the rest of the README alone until SP15 |

Replace `OWNER` with your account name. The badge only renders once the workflow has run at least once on the default branch, so a 404 in the first hour is expected.

**Docs:** [Workflow status badge](https://docs.github.com/en/actions/how-tos/monitor-workflows/add-a-status-badge)

The badge is the cheapest possible claim, and it is also the one a reader actually clicks. Point it at `ci.yml`, not at the old throwaway workflow: a badge on a deleted workflow shows "no status" forever.

**✅ Checkpoint: step 2 (badge)**
Save `README.md`, then run the check in your terminal before you commit:

```bash
bash .github/scripts/check-local.sh
```

Expected: `SP4 step 2 (badge)` ✅, with the steps you have not built yet still ❌. If a step is ❌, the `Next:` line names the section to re-read: fix it and run the same command again before committing. Then format, commit, and push:

```bash
tofu fmt -recursive
git add -A && git commit -m "docs(sp4): add the CI badge" && git push
```

The push runs the same check on GitHub, which is the authority and is consulted once per milestone, before `gh pr ready`: [SP1](SP1.md#how-to-see-your-results) explains both tiers. Step 2 turns ✅. Step 3 is still ❌: the throwaway workflow is still there.

## Part 3: Retire the throwaway workflow

SP3 proved the role could be assumed with a `workflow_dispatch` workflow that prints `aws sts get-caller-identity`. The `plan` job now proves the same thing on every push, so the throwaway has to go. Two workflows that both assume the role is one more thing to read and one more thing to keep in step.

**File Type:** `workflow`
**File Name:** `.github/workflows/oidc-check.yaml`

| Action | What to do |
|---|---|
| the file | delete it, with `git rm .github/workflows/oidc-check.yaml` |
| the name | no replacement. The `plan` job is the permanent proof |

**Docs:** [Deleting files in a repository](https://docs.github.com/en/repositories/working-with-files/managing-files/deleting-files-in-a-repository)

Use `git rm`, not a plain delete: a plain delete leaves an untracked file behind if you change your mind, and the check reads the working tree.

**✅ Checkpoint: step 3 (old-workflow)**
Delete the file, then run the check in your terminal before you commit:

```bash
bash .github/scripts/check-local.sh
```

Expected: `SP4 step 3 (old-workflow)` ✅, and the summary says `👍 SP4 passed.` If a step is ❌, the `Next:` line names the section to re-read: fix it and run the same command again before committing. Then format, commit, and push:

```bash
tofu fmt -recursive
git add -A && git commit -m "ci(sp4): remove the throwaway OIDC workflow" && git push
```

The push runs the same check on GitHub, which is the authority and is consulted once per milestone, before `gh pr ready`: [SP1](SP1.md#how-to-see-your-results) explains both tiers. Step 3 turns ✅, and every row is ✅. This is the last step of the milestone.

## Check it

Run `bash .github/scripts/check-local.sh` at every checkpoint. What its output means, how to fix a red step, and when GitHub is the authority are explained once, in [SP1](SP1.md#how-to-see-your-results); this brief's own steps and its own failures are below.

### How to see your results


How to run the check, what a finished run prints, and when GitHub is the authority are explained once in [SP1](SP1.md#how-to-see-your-results). Run it from the repo root with `bash .github/scripts/check-local.sh` at every checkpoint; it reads the milestone from your branch name, `sp4-ci` here.

The check runs SP4 in three steps, one per part:

| Step | Checks |
|---|---|
| 1 (workflow) | `.github/workflows/ci.yml`: the `static` and `plan` job names, `id-token: write` on the plan job only, the role variable, OpenTofu 1.13.1, tflint, checkov with `soft_fail: false`, and the build loop |
| 2 (badge) | `README.md`: the title, and the badge line pointing at `ci.yml` with `/badge.svg` |
| 3 (old-workflow) | `.github/workflows/oidc-check.yaml` is gone |

Steps you have not reached show ❌, and that is expected. You are done when every row is ✅.

Reading a failure:

- **`formatting (fmt -check)` is ❌ and lists files:** the spacing is not what `tofu fmt` produces. Run `tofu fmt -recursive` and push again. This row is not one of the three steps, but it fails the whole run on its own.
- **Only `formatting`, `init`, and `validate` appear, with no step rows:** `validate` failed, and the script stops there because no step can run on a configuration that does not validate. Read its output; it names the file and the line.
- **Step 1 ❌ with "needs a job called static":** the workflow still has the old single `check` job. Replace it rather than adding a second one.
- **Step 3 ❌ with "must not exist":** the throwaway workflow is still there. That is the whole point of the step.
- **Step 2 ❌:** the badge line must be a link around an image, and the workflow file name in both URLs must be `ci.yml`.

## Done when (the settings the check cannot read)

Three things live in the repository's settings, not in a file, so the check cannot see them. Run all of this in one terminal, from the repo root, with the GitHub CLI signed in.

The alert email is a repo secret, not a variable, so the plan output masks it:

```bash
gh secret set ALERT_EMAIL --body "you@example.com"
```

Branch protection needs the two job names. A required context that no job produces leaves every pull request permanently unmergeable, which is why the names here must match the job names exactly — and why this comes **after** the first run, not before it. A required check whose name no run has reported shows as **Expected** and blocks the merge until a run reports it, so set these once `ci.yml` has run on the branch.

```bash
gh api -X PUT repos/:owner/project-cloud_serverless-pipeline/branches/main/protection \
  -F required_status_checks[strict]=true \
  -F 'required_status_checks[contexts][]=static' \
  -F 'required_status_checks[contexts][]=plan' \
  -F enforce_admins=true \
  -F required_pull_request_reviews[required_approving_review_count]=0 \
  -F restrictions=null
```

Read it back. Expected: `["static","plan"]`, in either order:

```bash
gh api repos/:owner/project-cloud_serverless-pipeline/branches/main/protection \
  --jq '.required_status_checks.contexts'
```

Wait for the run on your branch. Every wait here is bounded:

```bash
for i in $(seq 1 40); do
  state=$(gh run list --workflow ci.yml --branch sp4-ci --limit 1 \
    --json status,conclusion --jq '.[0] | "\(.status)/\(.conclusion)"')
  echo "poll $i: $state"
  case "$state" in completed/*) break ;; esac
  sleep 15
done
```

Expected: the last line reads `completed/success`. That is `ci.yml`, the workflow holding the two required checks: `static` passes, and `plan` assumes the role and plans an empty stack, which is the point: the role, the backend, and the state all work before there is anything to deploy. The milestone check is a different workflow in a different run, and `remote-check.sh` below reads that one; polling it here would tell you nothing about `static` or `plan`.

Two things that look like failures and are not:

- No warning appears for `alert_email`. OpenTofu ignores a `TF_VAR_alert_email` that has no matching `variable` block, so the value sits unused until SP5 declares it. That is why the environment variable stays: the plan job never has to change again, and there is nothing to read in the log about it.
- If the plan job fails with **"Credentials could not be loaded"**, the repo variable `AWS_CI_ROLE_ARN` from SP3 is missing or empty. Read it with `gh variable list` and set it again from the bootstrap folder.

## Mark the pull request ready

You are one command from done. Add the milestone ID to `milestones.txt` on its own line, then format, commit, and push:

```bash
printf '%s\n' SP4 >> milestones.txt
git add milestones.txt && git commit -m "chore(sp4): add SP4 to milestones.txt" && git push
```

One last look at the check on GitHub, which is the authority here. It follows the run your last push started, so it needs no new commit and no push:

```bash
bash .github/scripts/remote-check.sh
```

This reads the milestone check only: the `static` and `plan` jobs your `ci.yml` runs are separate required checks, and the pull request's **Checks** tab is where a red one shows.

Then paste the finished run's URL into the pull request body, retitle the pull request, and mark it ready. The repository is squash-only, so the title becomes the one commit on `main`:

```bash
gh pr edit --title "ci(sp4): split the check into two jobs and add the badge"
gh pr ready
```

A reviewer reads the diff against this brief, then merges.

## After the merge

Merge the pull request on GitHub, then clean up the branch:

```bash
git switch main && git pull
git branch -d sp4-ci
git fetch --prune
```

`git branch -d` refuses after a squash merge, because the branch's commits are not in `main`; `git branch -D sp4-ci` is the same delete. The remote branch is already gone: `delete_branch_on_merge` removes it when the pull request merges.
