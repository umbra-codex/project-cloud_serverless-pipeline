# SHIP: Ship

| | |
|---|---|
| **Milestone** | SHIP: Ship |
| **Branch** | `ship` |
| **Depends on** | SP15, merged. The repository is finished; this milestone is the one a stranger reads |
| **Files you touch** | `README.md`, `LICENSE` (new), `.github/workflows/ci.yml` (replaced), `.github/scripts/ship-check.sh` (copied in), and 66 paths deleted |
| **Check** | Runs in this repo on every push to `ship`, and locally with `.github/scripts/check.sh SHIP`. Use this exact branch name |

## Goal

A finished repository exists to show what was built, to a recruiter or a hiring
engineer, in about five minutes. Everything that was written to teach the build
works against that: a brief that says "checkpoint" and a runner that grades your
edits are a course, not a portfolio piece.

So this milestone does three things. It adds the one check that names what a
reader has no use for and refuses to pass while it is still there. It rewrites
the README for someone who was not there. And it removes the scaffolding, in two
commits, replacing the milestone runner with the CI a finished repository runs.

Nothing about the pipeline changes. The code, the infrastructure, the product
tests, the evidence, and the decisions stay exactly as they are, and the history
is not rewritten: it shows the pace of the work, and the rules kept secrets out
of it from the first commit.

## Start your branch

```bash
git checkout main
git pull
git checkout -b ship
git push -u origin ship
```

## Part 1: The ship check

The check for this milestone is a script that fails while any listed scaffolding,
learner-facing phrase, local path, or secret-shaped string is still in the
repository. It is the list from Part 5, written as code, and it runs once, before
the removal.

#### 1. `.github/scripts/ship-check.sh`

**File Type:** `bash`
**File Name:** `.github/scripts/ship-check.sh`

It ships with the guide, because it is this milestone's check and not product
code. Copy it in, and read the table so its output means something when it
prints:

```bash
cp "$GUIDE_DIR/.github/scripts/ship-check.sh" .github/scripts/
chmod +x .github/scripts/ship-check.sh
```

| Group | What it refuses | Why it is in the list |
|---|---|---|
| 1 | `docs/` and `milestones.txt` | the overview and the briefs are a course, and they live in the vault now |
| 1 | `tests/sp*.check`, `tests/sp*.absent` | they grade a learner's edits, file by file |
| 1 | `tests/tooling-*.test.ts`, `tests/tooling-fixtures.ts` | they test the check helpers, which are going too |
| 1 | `.github/workflows/milestone-check.yml` | the CI logic that maps a branch name to a milestone |
| 2 | `Checkpoint`, `Done when`, `you will` | words addressed to a learner, wherever they are in the tree |
| 3 | `/home/`, `~/Projects`, `C:\Users` | local paths, which say where this was built and not what it is |
| 3 | the name of the machine that built this, and `GUIDE_DIR` | private names, and a variable that only exists during the build |
| 3 | `github.com/OWNER/`, `actions/runs/000000000`, `pipeline.example.com`, `YOUR_GITHUB_OWNER` | placeholders where this repository's own links belong |
| 4 | access key ids, a private key header, a token, `aws_secret_access_key` | a public repository is public forever |
| 5 | `TODO`, `FIXME` | work you meant to do, or work you dropped, and a reader cannot tell which |

Every finding names the file and never the line, because a check that prints the
line it caught is a check that copies a key into a log. It reads the whole tree
and skips what `.gitignore` keeps out of it, and it skips `.github/scripts/` and
`tests/ship-*`: its own source names every word it refuses, and a check cannot
report its own absence. The last commit of this milestone deletes both.

**Docs:** [find](https://pubs.opengroup.org/onlinepubs/9699919799/utilities/find.html) · [grep](https://pubs.opengroup.org/onlinepubs/9699919799/utilities/grep.html)

**The step files.** Nothing to write. `tests/ship-1-shipcheck.check`,
`tests/ship-2-readme.check`, `tests/ship-3-license.check`, and
`tests/ship-4-ship.test.ts` came in with the seed in SP0. Step 1 and step 4 are
about this script: step 1 reads its lists, and step 4 runs it against throwaway
trees, one per group, because a check that has never failed has not been tested.

### About step 4: the check's own test

Step 4 runs the ship check against ten throwaway trees, one clean and nine that
each carry one thing it refuses, so it is green while this repository still holds
everything on the list. The gate on this repository is the ship check itself, run
by hand at the checkpoint and again in Part 5 before the removal commit, and its
output is what goes into the pull request.

## Part 2: The README a stranger reads

The README is the only file most people will open. It has to answer four
questions from the first screen: what this is, how it works, what proves it
works, and what it traded away. Then it has to keep each answer.

Keep the title, the badge, and the sections SP15 wrote, and add the three that a
stranger needs and a learner did not:

| Section | What goes in it | Why it is on the page |
|---|---|---|
| the intro | three sentences: what the pipeline does, the two runtimes, and one line beginning `What proves it:` that names the green run, the capture, and the benchmark. Last, one line saying the trade-offs are in `## Decisions` | this is the five-minute test, and it is the first thing anyone reads |
| `## What this is` | the two runtimes, one paragraph each, and what runs today against what is a record | the AWS half cannot be applied again, and a reader has to know that before they try |
| `## Architecture` | both mermaid diagrams, with a line saying dotted arrows are failure paths | a diagram answers "how does it work" faster than any paragraph |
| `## How an event moves` | the six numbered steps, and the idempotency key stated once | it is the part an interviewer will ask about |
| `## The benchmark` | both runtimes, 1,000 events, p50 and p95, cost per 1,000, and where the numbers came from | a number with a source is evidence; a number without one is a claim |
| `## Proof it works` | the badge, the link to the run that finished the work, the Release asset, and `evidence/` | this is the section that turns "trust me" into "check it" |
| `## IAM: the policy, and the reason for every action` | both policy blocks with placeholders, and the action table | least privilege is arguable, action by action, and that argument is the point |
| `## Why this cannot run away` | the budget with credits excluded, the two concurrency caps, and what the caps did during the burst | it is the question every reviewer of a cloud project asks |
| `## Cost and teardown` | what it cost, what the free tier covered, the destroy, and `scripts/check-destroyed.sh` | a project that never explains its teardown looks like one that is still billing |
| `## What you can verify yourself` | the clickable claims, then the evidence a reader has to trust | the split is what makes the rest believable |
| `## Decisions` | one dated line per decision: chose X over Y because Z | it is the interview prep, and the record of the trade-offs |
| `## Run it yourself` | the Compose stack: the token, the password file, `podman compose up -d --build`, `podman compose ps` | a reader who can start it believes the rest |
| `## License` | one line, pointing at `LICENSE` | a repository without a license is not usable by anyone who finds it |

**The five-minute test.** Hand the repository page to somebody who was not
there. From the first screen alone, with no scrolling into the code, they should
be able to answer: what is it, how does it work, what proves it works, and what
trade-offs were made. If any of the four needs a second file, the intro is not
finished.

The two diagrams are the same pair as the overview. Copy them rather than
redrawing them: they are the one place where the two runtimes are compared side
by side.

## Part 3: The license

#### 3. `LICENSE`

**File Type:** `text`
**File Name:** `LICENSE`

| Part | Set To |
|---|---|
| first line | `MIT License`, then a blank line |
| copyright line | `Copyright (c) 2026 ` and your name, which is the name a reader will credit |
| the grant | the MIT text verbatim: the permission paragraph, the "The above copyright notice" paragraph, and the all-caps warranty paragraph |
| nothing else | no appendix, no year range, no note about the guide |

**Docs:** [the MIT license, verbatim](https://choosealicense.com/licenses/mit/)

GitHub reads this file and puts the license on the repository page, which is one
of the four things that page has to show. Step 3 reads it too: a title line, a
year, the grant, and the warranty.

> **✅ Checkpoint: steps 1 to 3 (ship check, README, license)**
> Save `README.md` and `LICENSE`, then run the check in your terminal before you commit:
> ```bash
> bash .github/scripts/check-local.sh
> ```
> Expected: `SHIP step 1 (shipcheck)` ✅, `step 2 (readme)` ✅, `step 3 (license)` ✅, `step 4 (ship)` ✅, and the summary says `👍 SHIP passed.` If a step is ❌, the `Next:` line under the summary names the brief section to re-read and what the check looked for: fix the file and run the same command again, with no commit and no push.
> Now run the ship check itself, which is the gate that has not passed yet:
> ```bash
> bash .github/scripts/ship-check.sh
> ```
> Expected: `👎 Ship check failed`, with one line per thing still in the tree. That list is the next two parts, and it is the reason this milestone exists. Step 4 is green because it runs the script against throwaway trees; the run above is the script against this repository.
> Then commit and push:
> ```bash
> tofu fmt -recursive
> git add -A && git commit -m "docs(ship): rewrite the README for a stranger and add the license" && git push
> gh pr create --fill --draft
> ```
> The push runs the same check on GitHub, which is the authority and is consulted once per milestone, before `gh pr ready`: [SP1](SP1.md#how-to-see-your-results) explains both tiers.
> Steps 1 to 4 are ✅. The ship check is still ❌: Parts 4 and 5 are what turn it.

## Part 4: The normal workflow

**File Type:** `yaml`
**File Name:** `.github/workflows/ci.yml`

The milestone runner is about to go, so the repository needs the CI it will keep.
This is the same file name, so the badge SP4 put in the README keeps pointing at
a real workflow, and it is a replacement rather than an addition: one workflow,
one badge, one place to look.

It ships with the guide. Copy it in from `$GUIDE_DIR`, or write it from the
table below, which is the whole of its behavior:

```bash
cp "$GUIDE_DIR/.github/workflows/ci.yml" .github/workflows/ci.yml
```

| Part | Set To |
|---|---|
| `name` | `ci` |
| `on` | `push`, `pull_request`, and `workflow_dispatch`. Every branch, every pull request: a finished repository is checked on all of them |
| `permissions` | `contents: read` at the top, so a job that needs more asks for it |
| `concurrency` | group `ci-${{ github.ref }}`, `cancel-in-progress: true`, so a second push to the same branch stops the first run instead of paying for both |
| the `static` job | `ubuntu-latest`, checkout, OpenTofu 1.13.1, Bun 1.4.3, then: `tofu fmt -check -recursive`; `tofu -chdir=terraform init -backend=false -input=false` and `tofu -chdir=terraform validate -no-color`; `tofu -chdir=terraform test -no-color -test-directory=../tests`; the bootstrap folder's `init -backend=false` and `test`; `bun test ./tests`; tflint v0.64.0 with `tflint --init` and `tflint --recursive --config "$(pwd)/.tflint.hcl"`; checkov `v12.2915.0` over `terraform` with `soft_fail: false` |
| the `plan` job | `needs: static`, `if: vars.AWS_CI_ROLE_ARN != ''`, `id-token: write`, `role-to-assume` from that variable, Node 24, the bundle build (`npm ci && npm run build` per folder), then `tofu -chdir=terraform init` and `tofu -chdir=terraform plan -no-color -input=false` |
| the product test command | `tofu -chdir=terraform test -no-color -test-directory=../tests`, then `tofu -chdir=terraform/bootstrap test -no-color`, then `bun test ./tests`. The plan tests assert the infrastructure, the handler tests assert the two functions, and none of them needs an account |

**Docs:** [workflow syntax](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax) · [OpenTofu test](https://opentofu.org/docs/cli/commands/test/)

Three things about it are worth saying out loud. It runs the product's tests
rather than the milestone's: the plan tests and the handler tests are the ones
that describe the thing being shipped. It never calls the milestone runner,
which is the point of replacing it. And the `plan` job skips itself when the
repository variable is empty, which it is once the account has closed and you
delete the variable in the Done-when list; the job stays because the OIDC design
is part of what a reader came to see.

## Part 5: What leaves

The table is the answer to "what does a reader not need". It was produced by
listing the tree, not from memory: run `git ls-files | sort` at the end of SP15
and group what it prints. The ship check reads the same list.

| What leaves | Paths | Why | Removed by |
|---|---|---|---|
| the overview and the briefs | `docs/overview.md`, `docs/milestones/*.md` | a course, and the vault keeps it | the first commit |
| the milestone list | `milestones.txt` | the runner reads it, and the runner is going | the first commit |
| the step checks | `tests/sp*.check`, `tests/sp*.absent` | they grade a learner's edits, one file per step | the first commit |
| the helper tests | `tests/tooling-*.test.ts`, `tests/tooling-fixtures.ts` | they test the check helpers | the first commit |
| the branch-to-milestone CI | `.github/workflows/milestone-check.yml` | it maps a branch name to a milestone | the first commit |
| learner-facing text | any file the ship check names under `Checkpoint`, `Done when`, or `you will` | it addresses a learner | the first commit |
| local paths and private names | `/home/...`, `~/Projects`, the name of the machine, `GUIDE_DIR` | they describe where this was built | the first commit |
| the placeholders in the README | `github.com/OWNER/`, `actions/runs/000000000`, `pipeline.example.com` | they point at somebody else's repository, and a broken badge is the first thing a stranger sees | the first commit |
| TODOs | any `TODO` or `FIXME` the ship check finds | a reader cannot tell a plan from an omission | the first commit |
| the milestone runner and its helpers | `.github/scripts/check.sh`, `check-local.sh`, `why.sh`, `remote-check.sh`, `lint-briefs.sh` | CI runs the tests now, and nothing here is a step any more | the last commit |
| this milestone's own check | `.github/scripts/ship-check.sh`, `tests/ship-*` | it exists to prove the removal, and it cannot report its own absence | the last commit |

**What stays.** The real code and infrastructure (`src/`, `terraform/`,
`compose/`, `compose.yaml`, `scripts/`), the tests of the product itself
(`tests/sp*.tftest.hcl`, `tests/sp6-6-handler.test.ts`, `tests/sp9-1-consumer.test.ts`,
`tests/sp9-2-ingest-key.test.ts`, and the three in `terraform/bootstrap/tests/`),
`evidence/`, the decision log, `.github/workflows/ci.yml`, `.gitignore`,
`.gitattributes`, `.tflint.hcl`, `.checkov.yaml`, the README, the license, and
the history.

### The placeholders in the README

The README's badge and its proof links carry placeholders: `OWNER`, because SP15's
step needs a name that is not yours, and `000000000` and `pipeline.example.com`,
because the run and the hostname did not exist when SP4 wrote the badge.
`evidence/ci-run.txt` carries two more, because it is the URL of the run that
finishes the work and that run had not happened. A placeholder is a link a reader
cannot click, so this part replaces them, and the ship check refuses them until
they are gone:

| Placeholder | Replace with | Where to find it |
|---|---|---|
| `OWNER`, in the badge, in the three `github.com` links, and in `evidence/ci-run.txt` | the owner in the repository's URL | the address bar |
| `000000000` in the README | the id of the run that finished the work | **Actions**, the run, then its URL |
| `REPLACE_WITH_RUN_ID` in `evidence/ci-run.txt` | the same id, without the rest of the URL | the same page |
| `pipeline.example.com` | the hostname the tunnel publishes | SP11's Done when |
| `YOUR_GITHUB_OWNER` | the same owner, if one is still in either file | the command below |

```bash
grep -n -E "github\.com/OWNER/|actions/runs/000000000|pipeline\.example\.com|YOUR_GITHUB_OWNER|REPLACE_WITH_RUN_ID" README.md evidence/ci-run.txt
```

Expected, after the edits: no output. The badge has to point at this repository
or it renders as a broken image, which is the one thing a stranger sees first,
and `evidence/ci-run.txt` is the link a reader follows to check the run.

**Two commits, and what each one proves.**

1. `chore(ship): remove the build scaffolding and land the normal workflow`. It
   deletes everything in the table's first eight rows and replaces `ci.yml` in
   the same commit, so the repository is never without CI. Run the ship check
   and the milestone check before you commit it:
   ```bash
   bash .github/scripts/ship-check.sh
   bash .github/scripts/check.sh SHIP
   ```
   Expected: `👍 Ship check passed.`, then `👍 SHIP passed.` The second command is
   the one run in this guide without `all`, because the milestones it would
   re-run are the files this commit deletes.
2. `chore(ship): remove the milestone runner`. It deletes `.github/scripts/` and
   `tests/ship-*`: the runner, the helpers, the ship check, and the step files
   that read the first eight rows. After this commit there is no runner to
   remove, and the proof is the normal workflow's run on the commit itself: it
   runs the product tests and the scans, and nothing it runs is a milestone
   check.

```bash
git rm -r --quiet docs milestones.txt
git rm --quiet .github/workflows/milestone-check.yml
rm -f tests/sp*.check tests/sp*.absent tests/tooling-*.test.ts tests/tooling-fixtures.ts

bash .github/scripts/ship-check.sh
bash .github/scripts/check.sh SHIP

git add -A && git commit -m "chore(ship): remove the build scaffolding and land the normal workflow"
git push
```

When both print 👍, commit the last one:

```bash
git rm -r --quiet .github/scripts
git rm --quiet --ignore-unmatch tests/ship-1-shipcheck.check tests/ship-2-readme.check tests/ship-3-license.check tests/ship-4-ship.test.ts
git add -A && git commit -m "chore(ship): remove the milestone runner"
git push
```

Expected: the second push starts the `ci` workflow on `ship`, and it is green.
That run is the proof for the commit that removed the runner: the repository
still formats, validates, scans, and passes its own tests with no runner in it.

## Check it

Run `bash .github/scripts/check-local.sh` at every checkpoint. What its output
means, how to fix a red step, and when GitHub is the authority are explained once,
in [SP1](SP1.md#how-to-see-your-results); this brief's own steps and its own
failures are below.

### How to see your results

The check prints one row per step, in the order the parts appear, and a step is
green only when its file is in place and every assertion in it passes. A red row
prints the reason underneath it, naming the file, the value, or the attribute
that is wrong. CI prints the same rows in the job summary, so the local run and
the remote run read identically.

**Locally:** `.github/scripts/check.sh SHIP`. **On the pull request:** **Actions**,
newest run, **Summary**. From the fourth part the milestone rows are the only
ones left, because the files that made the others are gone.

| Step | Checks |
|---|---|
| 1 (shipcheck) | that the ship check names every group and every scaffolding path it refuses |
| 2 (readme) | the stranger's four questions on the first screen, then one section per answer |
| 3 (license) | the MIT title, a year and a holder, the grant, and the warranty |
| 4 (ship) | the ship check against ten throwaway trees: one clean, and nine that each carry one thing it has to refuse |

Reading a failure:

- **Step 2 ❌ on `^What proves it: `**: the line has to start the sentence, at
  the start of a line, and name the run, the capture, and the benchmark.
- **Step 4 ❌ on a group**: the check stopped refusing something the brief
  promises it refuses. The test names the group.

## Done when (a fresh clone, and the page)

### 1. A fresh clone builds and runs from the README alone

```bash
mkdir -p ~/fresh && git clone https://github.com/YOUR_GITHUB_OWNER/project-cloud_serverless-pipeline ~/fresh/serverless-pipeline
cd ~/fresh/serverless-pipeline
```

Then, with nothing but the README open, the commands that run offline:

```bash
tofu fmt -check -recursive
tofu -chdir=terraform init -backend=false -input=false
tofu -chdir=terraform validate -no-color
tofu -chdir=terraform test -no-color -test-directory=../tests
tofu -chdir=terraform/bootstrap init -backend=false -input=false
tofu -chdir=terraform/bootstrap test -no-color
bun test ./tests
```

Expected: `Success! 19 passed, 0 failed.` for the plan tests, `Success! 5
passed, 0 failed.` for the bootstrap folder, and every handler test green. The
first `init` downloads the providers, so it is the slow one.

| Claim | Ran here? | The command that checks it |
|---|---|---|
| the format, the validation, and the plan tests pass in a fresh clone | yes, above | `tofu -chdir=terraform test -test-directory=../tests` |
| the Compose stack starts from the README | **unverified**: it needs the tunnel token and a running Podman | `podman compose up -d --build` then `podman compose ps` |
| the status page answers GET | **unverified**: the tunnel is a live service | open `https://pipeline.example.com/` in a browser; it answers one JSON object |
| the `plan` job can still reach an account | **unverified**, and expected to be no: the account closed | the `plan` job's row on the pull request |
| the workflow's action versions are current | **unverified**: no run happens on this machine | the first push after the last commit |

### 2. The normal workflow is green

```bash
gh pr checks --watch
```

Expected: `static` passes, and `plan` is skipped. A skipped job is not a
failure (unverified: the first run's **Checks** tab shows the `plan` row as
skipped, not red); if it is red, the variable still points at a role that no
longer exists.

### 3. The ship check passed before the runner was removed

Paste the `👍 Ship check passed.` line and the `👍 SHIP passed.` line into the
pull request body, next to the commit that removed the runner. The order is the
proof: the check went green, then the thing that ran it left.

### 4. The repository page

| What | Set it with | Check it |
|---|---|---|
| a description | `gh repo edit --description "Event-driven serverless pipeline, AWS and Compose, with the evidence"` | the first line under the repository name |
| topics | `gh repo edit --add-topic aws,serverless,lambda,sqs,dynamodb,opentofu,podman` | the topic row on the repository page |
| a license | the `LICENSE` file in this milestone | the license line on the repository page, which says MIT |
| a pin | the profile page: **Customize your pins**, then this repository | your profile, first screen |
| the `plan` job skips | `gh variable delete AWS_CI_ROLE_ARN` | the `plan` row says skipped on the next run |

The `gh` commands are unverified here: this machine has no authenticated
session to check them against. The check is the page itself, which is where a
reader looks.

History is not rewritten. You have not force-pushed, amended a pushed commit, or
rebased a shared branch in this milestone, and `git log --oneline` on `main`
still shows one commit per milestone.

## Mark the pull request ready

```bash
gh pr checks --watch
gh pr edit --title "chore(ship): remove the scaffolding from a finished repository"
gh pr ready
```

Expected: one pull request, `chore(ship): remove the scaffolding from a finished
repository`, with `static` green, `plan` skipped, and the two 👍 lines in its
body. Merge it. The repository page is the finish line.
