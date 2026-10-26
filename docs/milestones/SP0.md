# SP0: Create the GitHub repo

| | |
|---|---|
| **Milestone** | SP0: Create the GitHub repo |
| **Branch** | `sp0-repo` |
| **Depends on** | nothing. This is the first milestone, and the repository does not exist yet |
| **Files you touch** | `repos.tf` in the local `github` folder (one block), then in the new clone: `README.md`, `terraform/backend.tf`, `.gitignore`, and the seeded `docs/`, `tests/`, `.github/` |
| **Check** | Runs in this repo on every push to `sp0-repo`, and locally with `bash .github/scripts/check-local.sh`. Use this exact branch name |

## If you are not Umbra

This guide is one person's build log, and it keeps his names, his machine and his accounts on purpose. If you are building it yourself, these are the values to substitute, and the only ones. Everything else is the project's.

| Value in this guide | Used in | Substitute |
|---|---|---|
| `umbra-codex`, the GitHub owner | SP0 Part 1, SP3 Parts 1 and 3, SP15, SHIP | your account name, from `gh api user --jq .login` |
| `~/Projects/github`, an existing OpenTofu config that manages his repositories | SP0 Part 1, SHIP | your own config folder. If you have none, `gh repo create --public` makes the repository by hand: you lose only the "the repository is described in a file" property, and every later milestone works unchanged |
| the Kamrui H1, his home server | Overview, SP10, SP11, SP15 | the machine that runs Podman. SP15 calls it "a home server", because the ship check refuses the machine's name |
| `YOUR-DOMAIN` | SP11, SHIP | a domain you control and have added to Cloudflare. It costs money; the free plan does not cover the domain |
| the AWS free-plan account whose plan ends on 2026-11-05 | Overview, SP1, SP8, SP14 | your own account, and the date its free plan ends: six months after you created it, or the day the credits run out, whichever comes first |
| `~/Projects/individual`, where the clone lands, and Hyprland with `wf-recorder` | SP0 Part 1, SP12 | any folder you keep projects in, and any screen recorder: SP12 names OBS as the alternative |
| `us-east-1` | SP2 to SP14 | the region you want to pay for. Nothing else here assumes one |

## Goal

A public repository created by OpenTofu rather than by hand, and a scaffold with the folders every later milestone writes into and the check that grades them.

Nothing here touches the pipeline, and nothing here touches AWS. The repository is the first artifact, and the one a reviewer opens before anything else: its name, its description, and the fact that it was made by a configuration file rather than a command.

The repository is public from its first commit, and that first commit is the one that has to be clean. Umbra builds in the open, and history is never rewritten here, so a key committed today is a key published today: **nothing secret ever enters this repository, from the first commit on.** The ignore file in Part 2 is the first guard, and the account is reached with a role SP3 creates rather than with stored keys, which is the second.

## Before step 1: what you need installed

Seven tools. Three are usually already there; the other four need a check, and each one carries its install line.

| Tool | Version | Why it is needed | Approve it now? |
|---|---|---|---|
| OpenTofu | 1.13.x (`tofu`) | every command in this guide. The `terraform` binary is never invoked; the `ManagedBy = "terraform"` tag every resource carries names the language, not the binary | usually installed. If not: `sudo pacman -S opentofu` |
| Node | 24 | builds the Lambda bundles that CI zips | usually installed. If `node --version` prints a major version other than 24, `sudo pacman -S nodejs-lts-krypton npm` replaces `nodejs`; pacman will ask you to confirm the removal |
| GitHub CLI | any current (`gh`) | creating the variable, the release, and the pull requests | usually installed. If not: `sudo pacman -S github-cli` |
| Bun | 1.4.3 | `bun test` runs the handler steps, so the check fails without it | check. Install: `curl -fsSL https://bun.sh/install \| bash` |
| `jq` | 1.7 or newer | SP13 parses benchmark rows with it | check. Install: `sudo pacman -S jq` |
| AWS CLI | v2 (`aws`) | SP1 to SP14: the identity, the drill, the benchmark, the destroy check | check. Install: `sudo pacman -S aws-cli-v2`, or AWS's own v2 installer, which is what AWS documents |
| `wf-recorder` | any current | the 60 to 90 second failure capture in SP12, on Hyprland | **yes: `sudo pacman -S wf-recorder`**, and OBS works instead if you prefer it |

Every install above is yours to approve, not this guide's: nothing here runs one for you. A `pacman` line or a `curl | bash` changes your machine, so read it, run it yourself if you want it, then run the preflight below.

One more, later on this same machine: `podman` 6.1.4, rootless, with a Compose provider in front of it, asked for again in SP10. There is no `docker` binary here and no shim that answers to that name, so every container command in this guide is `podman`. Nothing from SP0 to SP9 needs it, and nothing in SP0 to SP9 installs anything.

Preflight, from any directory. It prints a version for each tool or `MISSING`:

```bash
for tool in tofu node bun gh jq aws; do
  printf '%-6s ' "$tool"
  command -v "$tool" >/dev/null 2>&1 && "$tool" --version 2>&1 | head -1 || echo "MISSING"
done
```

Expected: six version lines. `MISSING` on `tofu` or `gh` stops this milestone: `tofu` creates the repository and `gh` confirms it. `MISSING` on `aws` or `jq` stops you in SP1 and SP13 rather than here, and `MISSING` on `bun` stops the check at SP6, when the first handler step runs.

### Before you start: the words this guide uses

Five ideas carry every milestone, and each one fits in a sentence.

- **Configuration.** A folder of `.tf` files in HCL, a declarative language: you say what should exist, not what to do. A block is `type "name" { arguments }`, and the arguments are the ones the provider documents.
- **Provider.** A plugin that teaches OpenTofu one API. `hashicorp/aws` is the AWS API and `integrations/github` is GitHub's; the `required_providers` block pins which version is used.
- **State.** A JSON record of what OpenTofu created. Here it lives in an S3 bucket, so this machine and CI read the same one. `tofu plan` compares the configuration with the state and with the real account; `tofu apply` makes the difference real; `tofu destroy` reverses it.
- **Resource.** One object in the provider's API: `aws_sqs_queue.main` is one queue. A `data` block reads an object that already exists without owning it.
- **Verdict.** A plan ends in `1 to add, 0 to change, 0 to destroy`, and `No changes.` after an apply is the proof that nothing drifted.

| Word in this guide | What it means here |
|---|---|
| bucket, queue, table | S3 storage, SQS messages, DynamoDB rows |
| dead-letter queue | where a message goes after `maxReceiveCount` failed receives |
| event source mapping | the Lambda setting that polls a queue and hands it batches |
| function, runtime | one program AWS runs on demand, billed per invocation |
| OIDC | GitHub proves who it is to AWS, so CI needs no stored key |
| tflint, checkov | two third-party scanners the `static` job runs over the configuration |
| brief, milestone | one file in `docs/milestones/`, one branch, one pull request |
| the check | `.github/scripts/check.sh`, which grades a milestone and needs no AWS account |

### What the check is, and is not

The check and its tests are about 12,000 words of shell, regex, and HCL that you copy into the repository in Part 2 and never have to read. They grade the shape of what you write: this argument exists with this value, this file holds this line. They do not test whether the pipeline works — SP12's live run and SP13's numbers are the only tests of behavior here — so a green check is a floor, not a proof, and every **Done when** section lists what no check can see.

Because they compare text, indentation and line breaks are part of the contract. Run `tofu fmt -recursive` before every checkpoint, and when a step fails with a message that quotes an argument, format and rerun before you change any logic.

## Part 1: The repository, made by OpenTofu

The repo comes from `~/Projects/github`, the OpenTofu configuration that already manages your other repositories, and that is the folder every command here uses. Do not use `gh repo create`: the point is that the repository is described in a file, and a reviewer can read it.

Work in `~/Projects/github`, then come back here:

```bash
cd ~/Projects/github
tofu plan
```

Expected: **No changes.** If it shows drift, settle that first, so the new repository is the only thing in the next plan.

Add this block to `repos.tf`, after rewording the description. The description is the first line a recruiter reads, and this repository is public from this commit:

| Argument | Set To |
|---|---|
| `name` | `project-cloud_serverless-pipeline` |
| `description` | one sentence naming both runtimes: the AWS pipeline and the Compose port |
| `visibility` | `public`, from this first commit. Nothing secret goes into the repository, ever |
| `auto_init` | `true`, so `main` exists with one commit |
| `has_issues` | `true` |
| `delete_branch_on_merge` | `true`, so merged branches do not pile up |
| `allow_squash_merge` | `true`, and the two below `false`: one commit per milestone is the shape every later brief assumes, and the merge button cannot produce anything else |
| `allow_merge_commit` | `false` |
| `allow_rebase_merge` | `false` |
| `archive_on_destroy` | `true`, so a destroy archives the repo instead of deleting it |
| `topics` | `aws`, `serverless`, `lambda`, `sqs`, `dynamodb`, `opentofu` |
| `security_and_analysis` | a nested block, not two arguments. Shown below the table |

**Block Type:** `resource`
**Resource Type:** `github_repository`
**Resource Name:** `serverless-pipeline`

**Docs:** the `github_repository` resource in the `integrations/github` provider, which the `github` configuration already pins: [github_repository](https://registry.terraform.io/providers/integrations/github/latest/docs/resources/repository)

The `security_and_analysis` row, as the provider actually takes it — two nested blocks, not two arguments. `secret_scanning = "enabled"` is an unsupported argument:

```hcl
security_and_analysis {
  secret_scanning {
    status = "enabled"
  }
  secret_scanning_push_protection {
    status = "enabled"
  }
}
```

A public repository gets both at no cost, and push protection refuses a push that carries a key before it reaches history.

**Tags:** this provider has no tags; `topics` is the closest thing and it is a list on the resource.

Then format, plan, read the summary, and apply exactly what you read:

```bash
tofu fmt && tofu validate
tofu plan -out=new-repo.tfplan
tofu apply new-repo.tfplan
```

Expected: `Plan: 1 to add, 0 to change, 0 to destroy.` Anything else means you touched a block you did not mean to. Keep the `.tfplan` extension: the ignore file in that folder catches `*.tfplan`, and a file called plain `tfplan` slips past it.

Later, if a plan shows `1 to destroy`, you deleted the block, and applying would archive the repository. To stop managing it without touching it, run `tofu state rm github_repository.serverless-pipeline` and delete the block in the same sitting.

Confirm it exists, then clone it and commit the config:

```bash
gh repo view umbra-codex/project-cloud_serverless-pipeline
git add repos.tf && git commit -m "feat: add serverless-pipeline repo"
gh repo clone umbra-codex/project-cloud_serverless-pipeline ~/Projects/individual/serverless-pipeline
```

Expected: `gh repo view` prints the repo, marked **Public**, with the description and the topics you wrote, and the clone lands in `~/Projects/individual/serverless-pipeline`.

**Be careful with `main`.** `auto_init = true` gives the repo one commit, so the clone starts on `main` and has history. A clone of a repo with no commits would start on `master` on a machine with no `init.defaultBranch`, which is a different repository shape than this guide assumes.

## Part 2: Your branch, and the scaffold

The repository holds one commit, made by `auto_init`, and nothing else. The guide's own files are not in it yet, and the check cannot run without them, so they come in now, as one commit, together with the folders every later milestone writes into.

The scaffold is the `guide/` folder of the answer key repository (`~/Projects/individual/serverless-pipeline-answer-key/guide`). `GUIDE_DIR` is that folder on your machine, and it is where every copy below reads from. Set it once in this shell:

```bash
cd ~/Projects/individual/serverless-pipeline
export GUIDE_DIR="$HOME/Projects/individual/serverless-pipeline-answer-key/guide"
```

Change that path to wherever your copy of the answer key's `guide/` folder lives. It must contain six things:

- `docs/overview.md`, and `docs/milestones/` with the seventeen briefs `SP0.md` to `SP15.md` and `SHIP.md`
- `tests/`, the 56 step and plan tests
- `terraform/bootstrap/tests/`, the three bootstrap plan tests
- `.github/scripts/`, the check runner and its helpers, and `.github/workflows/milestone-check.yml`
- `.tflint.hcl` and `.checkov.yaml`, the two lint configs
- `.gitattributes`, which fixes line endings

Confirm it before you copy anything. A wrong path is the only way this part fails silently:

```bash
ls "$GUIDE_DIR/docs/overview.md" "$GUIDE_DIR/tests" "$GUIDE_DIR/terraform/bootstrap/tests"
```

Expected: the file path, then a list of test files. If either is missing, `GUIDE_DIR` is wrong; fix it rather than copying from somewhere else.

The scaffold is furniture, not answers. It sits inside the answer key's repository: open only its `guide/` folder, never its `terraform/`, `src/` or `compose/` at the top level, while you build. This part copies the grader in, so read a test after you have written your own version, never before.

Now the branch, then the copies and the empty milestone list. Six things come across: the overview and the seventeen briefs, the step tests, the three bootstrap plan tests, the check runner, the milestone-check workflow, and the two lint files CI uses in SP4. The briefs are `SP*.md` and `SHIP.md`: Ship has no number, so the `SP*` pattern does not catch it, and it is copied on its own line.

```bash
git switch -c sp0-repo
mkdir -p docs/milestones tests .github/scripts .github/workflows
cp "$GUIDE_DIR/docs/overview.md" docs/overview.md
cp "$GUIDE_DIR"/docs/milestones/SP*.md docs/milestones/
cp "$GUIDE_DIR/docs/milestones/SHIP.md" docs/milestones/
cp "$GUIDE_DIR"/tests/* tests/
cp "$GUIDE_DIR/.github/scripts/check.sh" .github/scripts/check.sh
cp "$GUIDE_DIR/.github/workflows/milestone-check.yml" .github/workflows/milestone-check.yml
mkdir -p terraform/bootstrap/tests
cp "$GUIDE_DIR/terraform/bootstrap/tests"/*.tftest.hcl terraform/bootstrap/tests/
cp "$GUIDE_DIR/.tflint.hcl" .tflint.hcl
cp "$GUIDE_DIR/.checkov.yaml" .checkov.yaml
chmod +x .github/scripts/check.sh
printf '%s\n' \
  '# Milestones that are merged. CI checks every one of them on every push.' \
  '# Add your milestone ID on its own line in the same pull request that builds it.' \
  > milestones.txt
```

Expected: `ls docs/milestones | wc -l` prints `17`, and `ls tests | wc -l` prints `56`.

The seed leaves `milestones.txt` with two comment lines and no IDs, on purpose: a milestone registers itself, and the next part is where this one does.

Now the skeleton. Four folders, three files:

| Path | Set To |
|---|---|
| `terraform/` | created, holds one file |
| `src/ingest/` | created, empty until SP6 |
| `src/consumer/` | created, empty until SP7 |
| `evidence/` | created, filled in SP14 |
| `README.md` | the first heading exactly `# serverless-pipeline`, then one sentence |
| `terraform/backend.tf` | the `terraform` block with `required_version` and nothing else |
| `.gitignore` | the ten lines in the table below |

| Line in `.gitignore` | Why |
|---|---|
| `.terraform/` | provider binaries and module cache, never committed |
| `*.tfstate` | state belongs in the bucket from SP2 on, and never in git |
| `*.tfstate.*` | the backups and temporary files OpenTofu writes beside it |
| `*.tfvars` | local values, possibly secrets |
| `!*.tfvars.example` | the example file is committed, so a reader knows what to set |
| `node_modules/` | installed, not authored |
| `dist/` | compiled output, rebuilt by CI |
| `build/` | the same |
| `scratch/` | local files the money milestones create |
| `secrets/` | the Postgres password file in SP10 |

The same ten lines, in one command, so none is retyped:

```bash
cat > .gitignore <<'EOF'
.terraform/
*.tfstate
*.tfstate.*
*.tfvars
!*.tfvars.example
node_modules/
dist/
build/
scratch/
secrets/
EOF
```

`.terraform.lock.hcl` is not in that list on purpose. It gets committed in SP2, the first time this repository runs `init`, and it is why this machine and CI resolve the same provider versions.

```bash
mkdir -p terraform src/ingest src/consumer evidence
printf '%s\n' '# serverless-pipeline' '' 'An event-driven pipeline, built one milestone at a time.' > README.md
```

`terraform/backend.tf` holds one block:

| Block Type | Block | Contents |
|---|---|---|
| `terraform` | `required_version` | `">= 1.10"`, the release that made native S3 locking possible, which SP2 needs |

**Docs:** [terraform block](https://opentofu.org/docs/language/settings/)

Add the milestone's line, then commit and push:

```bash
printf '%s\n' SP0 >> milestones.txt
tofu fmt -recursive
git add -A && git commit -m "feat(sp0): create the repository and its scaffold"
git push -u origin sp0-repo
```

Expected: one commit, `feat(sp0): create the repository and its scaffold`, on a branch that exists on the remote.

**✅ Checkpoint: steps 1 and 2 (skeleton and seed)**
One setup step first, because you cannot run the check until the helper is in your repository. Copy the helpers and the line-ending file in from the guide folder, and commit them. They are not part of the milestone; they are how you read it. The loop you are about to use, rung by rung, is explained in [SP1](SP1.md#how-to-see-your-results).

```bash
for helper in check-local why remote-check lint-briefs; do
  cp "$GUIDE_DIR/.github/scripts/$helper.sh" .github/scripts/
done
chmod +x .github/scripts/*.sh && cp "$GUIDE_DIR/.gitattributes" .gitattributes
git add .github/scripts .gitattributes && git commit -m "chore(sp0): add the check helpers" && git push
```

`check.sh` is already in place from the copies above; this loop adds the four helpers around it. `lint-briefs.sh` is the odd one out: no workflow runs it, and it checks the briefs' headings, which is a job for when you edit a brief.

Then open this milestone's draft pull request, the only `gh pr` line in this block outside the ready step at the end:

```bash
gh pr create --fill --draft
```

Now run the check in your terminal, from the repository root:

```bash
bash .github/scripts/check-local.sh
```

Expected: `SP0 step 1 (skeleton)` ✅ and `SP0 step 2 (seed)` ✅, then `👍 SP0 passed.` If a step is ❌, the `Next:` line names the section to re-read: fix it and run the same command again before committing. Every later checkpoint runs this same command, and the push at each one runs the same check on GitHub. GitHub is the authority and is consulted once per milestone, before `gh pr ready`: [SP1](SP1.md#how-to-see-your-results) explains both tiers. Steps 1 and 2 turn ✅: the skeleton in this part, and the seed that came with it.

## Check it

Every checkpoint in this guide has one command, and you run it in your terminal, from the repository root:

```bash
bash .github/scripts/check-local.sh
```

How to read what it prints, rung by rung, and when GitHub is the authority are written once, in [SP1](SP1.md#how-to-see-your-results). This brief's own steps and its own failures are below.

| Step | Checks |
|---|---|
| 1 (skeleton) | the version pin in `terraform/backend.tf`, the ten ignore rules, and the README title |
| 2 (seed) | the briefs, the check runner, and `SP0` in `milestones.txt` |

Reading a failure:

- **Step 1 ❌ on `.gitignore`**: one of the ten lines is missing or spelled differently. Compare the whole file rather than the failing line.
- **Step 2 ❌ on `docs/milestones/SP0.md`**: the seed commit did not land. Go back to Part 2 and re-run the copies, rather than creating the files by hand.

## Done when (things only the console can show)

The check cannot see GitHub, so these are yours:

1. `gh repo view` shows the repository marked **Public**, with your description and topics.
2. The Actions tab shows the run for `sp0-repo`, with step 1 and step 2 green.
3. `git log --oneline` shows only commits you made, and `git ls-files` lists no `*.tfvars`, nothing under `secrets/`, and no key file. Nothing secret entered the repository with its first commit, and the push-protection setting you turned on reports the same.
4. Branch protection is **off**. SP4 turns it on, because before SP4 there is no CI to require.

## Mark the pull request ready
One last look at the check on GitHub, which is the authority here. It follows the run your last push started, so it needs no new commit and no push:

```bash
bash .github/scripts/remote-check.sh
```

When it prints `👍 SP0 passed.`, retitle the pull request and mark it ready:

```bash
gh pr edit --title "feat(sp0): create the repository and its scaffold"
gh pr ready
```

Expected: one pull request, `feat(sp0): create the repository and its scaffold`, merged by you after the check is green. SP1 starts from `main` after this merge.

## After the merge

Merge the pull request on GitHub, then clean up the branch:

```bash
git switch main && git pull
git branch -d sp0-repo
git fetch --prune
```

`git branch -d` refuses after a squash merge, because the branch's commits are not in `main`; `git branch -D sp0-repo` is the same delete. The remote branch is already gone: `delete_branch_on_merge` removes it when the pull request merges.
