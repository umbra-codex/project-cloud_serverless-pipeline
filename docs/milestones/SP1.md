# SP1: AWS access

| | |
|---|---|
| **Milestone** | SP1: AWS access |
| **Branch** | `sp1-aws` |
| **Depends on** | SP0, merged. The repository exists and the check runs in it |
| **Files you touch** | `milestones.txt` |
| **Check** | Runs in this repo on every push to `sp1-aws`, and locally with `.github/scripts/check.sh SP1`. Use this exact branch name |

## Goal

An AWS session you can prove, an account number written down somewhere you will
find it in SP12, and the first milestone registered in the repository that SP0
created. Every ARN in this guide contains that account number, and SP2 puts it in
a bucket name that is unique because of it.

Nothing here touches the pipeline, and this milestone has no file of its own. The
account is the artifact, which is why the check cannot see it and the steps below
are yours.

## Part 1: AWS access

No files. Two commands and one number you write down.

1. Sign in the way this account expects. If `aws sts get-caller-identity` fails
   with an expired session, re-authenticate first; the exact command depends on
   how the account is set up (an SSO profile, `aws login`, or a key you manage),
   and this guide does not guess it.
2. Confirm the identity and note the **Account** value.

```bash
aws sts get-caller-identity
```

Expected: a JSON object with `UserId`, `Account`, and `Arn`. If the `Account` is
not the one you expect, stop: the rest of the guide writes resources into
whatever account this command names.

3. Read the credit balance and its expiry date in the Billing console. The
   program treats the balance as the limit, not a calendar date, and SP12 to SP14
   are the milestones that spend anything.

> **Note, not a checkpoint.** There is no file to save and nothing for the
> check to read here. The proof is the command above printing an account you
> recognize, and the balance written down somewhere you will find it in SP12.
> The checkpoint of this milestone comes at the end of Part 2.

## Part 2: Your branch, and the registration

The repository from SP0 holds the scaffold and the check, and `milestones.txt`
holds two comment lines and one ID. A milestone registers itself in the pull
request that builds it, and this is the first milestone after the scaffold, so
this is the first registration you make.

```bash
git checkout main
git pull
git switch -c sp1-aws
printf '%s\n' SP1 >> milestones.txt
git add milestones.txt && git commit -m "chore(sp1): register SP1"
git push -u origin sp1-aws
```

Expected: `tail -3 milestones.txt` prints `SP0`, then `SP1`, and the branch exists
on the remote with one commit on it.

Nothing else changes in the repository. From here the check runs SP1 on this
branch, and it keeps re-running SP0 on every push, because every registered
milestone is re-checked.

> **✅ Checkpoint: step 1 (register)**
> Run the check in your terminal before you open the pull request:
> ```bash
> bash .github/scripts/check-local.sh
> ```
> Expected: `SP1 step 1 (register)` ✅, `SP0` still ✅ underneath it, and the summary says `👍 SP1 passed.` If the row is ❌, the `Next:` line under the summary names what the check looked for: fix `milestones.txt` and run the same command again, with no commit and no push.
> Then open this milestone's draft pull request:
> ```bash
> gh pr create --fill --draft
> ```
> The push runs the same check on GitHub, which is the authority and is consulted once per milestone, before `gh pr ready`: [How to see your results](#how-to-see-your-results) explains both tiers.
> Step 1 turns ✅.

## Check it

Every checkpoint in this guide has one command, and you run it in your terminal, from the repository root:

```bash
bash .github/scripts/check-local.sh
```

This section is the only place that output is explained. The other briefs point back here.

### How to see your results

**On your machine, at every checkpoint.** The helper runs `.github/scripts/check.sh <your milestone> all`, the same file CI runs, with the same arguments, so the local run cannot drift into a different check. It keeps the check's working files inside `.terraform/`, which your ignore file already covers, so they never show up as an untracked change and your own provider cache is left alone. It needs OpenTofu and not AWS: every plan in the tests runs against a mocked provider. It warns when your OpenTofu version is not the one CI pins (1.13.1), and when your working tree has uncommitted changes, because GitHub checks commits and not files.

It prints one screen. This is a real run, on a branch where SP2 step 1 is built and steps 2 and 3 are not:

```
SP2: 2 of 4 checks green
  ✅ formatting, init, validate
  ✅ SP2 step 1 (bucket)
  ✅ SP2 step 1 (bucket)
  ❌ SP2 step 2 (migrate)      <- next
  ❌ SP2 step 3 (root-backend)
  ✅ every other milestone in milestones.txt passes (SP0, SP1)

Next: SP2 step 2 (migrate). Re-read docs/milestones/SP2.md, "## Part 2: Move the bootstrap state into the bucket it just made".
terraform/bootstrap/backend.tf: the bootstrap config needs an S3 backend of its own
Also failing: its own key, so the pipeline destroy in SP14 cannot reach it; native locking, not a DynamoDB table; state objects are encrypted at rest
Run bash .github/scripts/check-local.sh --explain for the full output.
```

Read it in four rungs, in this order:

1. **Which step.** The row marked `<- next` is the first one to fix. The rows above it are already green. The rows below it are the steps you have not built yet, and they turn ✅ as you go.
2. **Where to re-read.** The line beginning `Next:` names the step, then the section of that brief to re-read, and the numbered items in that section when it has any:

   ```
   Next: SP6 step 4 (trigger). Re-read docs/milestones/SP6.md, "### trigger.tf", items 13 to 14.
   ```

3. **What the check looked for.** The line under that is the check's own message, naming the file and the assertion that failed, in the words the test was written with. Nothing here is summarized from anywhere else.
4. **Everything else.** `--explain` adds every line the check printed, unedited:

   ```bash
   bash .github/scripts/check-local.sh --explain
   ```

Then fix the file and run the same command again. No commit, no push, no waiting for GitHub: that is the loop, and once the providers are installed it takes about a minute a turn.

The count in the summary line counts **check files**, not steps. SP2 and SP3 run two files for step 1, one text read and one mocked plan, so step 1 appears twice and both rows have to be ✅.

**On GitHub, once per milestone, before `gh pr ready`.** GitHub is the authority. A green run in your terminal is a preview of the same check, and the two can disagree: your OpenTofu version may not be CI's, and GitHub checks what you pushed rather than what you have on disk. The push at your last checkpoint already started the check there, so run this once, from the same folder:

```bash
bash .github/scripts/remote-check.sh
```

It looks for the run your push started, waits for it, follows it, and prints the same summary and the same `Next:` line, then the run's URL. It never starts a run of its own: a second run on the same branch cancels the first. It needs the GitHub CLI, signed in with `gh auth login`.

It reads the milestone check and nothing else. From SP4 your `ci.yml` adds its own jobs to the pull request (`static` runs tflint and checkov, `plan` runs the plan), branch protection requires both, and this follower does not look at either: a green summary here is a green milestone, not a mergeable pull request. The pull request's **Checks** tab is where a red `static` or `plan` shows.

The run's page itself, when you want the whole log rather than the summary: open the repository on GitHub, then **Actions**, then the newest run, then **Summary**.

**When a step stays red after two tries**, re-read the whole section the `Next:` line names rather than the one line it points at, and run the same command again. When the summary says `👍 SP1 passed.`, the milestone is done in your terminal: commit, push, and go to the next checkpoint, or to the closing step if this was the last one.

The check runs this milestone in the steps below, one file each:

| Step | Checks |
|---|---|
| 1 (register) | `SP1` in `milestones.txt`, this brief in the tree, and the runner that reads both |

Reading a failure:

- **Step 1 ❌ on `milestones.txt`**: the line is missing or it reads something
  else. `tail milestones.txt` shows what the last commit added.
- **Step 1 ❌ on `docs/milestones/SP1.md`**: the seed from SP0 did not land. Go
  back to `LANDING.md` rather than creating the file by hand.

## Done when (things only the console can show)

The check cannot see GitHub or the AWS account, so these are yours:

1. `aws sts get-caller-identity` prints the account you expect, and you wrote the
   **Account** value down.
2. The Billing console shows a credit balance and an expiry date, and you wrote
   both down. SP12 is the first milestone that can spend anything.
3. The Actions tab shows the run for `sp1-aws`, with step 1 green and SP0 still
   green under it.

## Mark the pull request ready
One last look at the check on GitHub, which is the authority here. It follows the run your last push started, so it needs no new commit and no push:

```bash
bash .github/scripts/remote-check.sh
```

When it prints `👍 SP1 passed.`, retitle the pull request and mark it ready:

```bash
gh pr edit --title "chore(sp1): register SP1 and prove the AWS session"
gh pr ready
```

Expected: one pull request, `chore(sp1): register SP1 and prove the AWS session`,
merged by you after the check is green. SP2 starts from `main` after this merge,
with the account number in hand.
