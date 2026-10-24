#!/usr/bin/env bash
# Follows the milestone-check run GitHub started for the commit you pushed, and
# prints one screen.
#
#   bash .github/scripts/remote-check.sh            the milestone your branch points at (sp2-state -> SP2)
#   bash .github/scripts/remote-check.sh SP2        a specific milestone
#   bash .github/scripts/remote-check.sh --explain  the same, plus the failed step's raw output
#   bash .github/scripts/remote-check.sh --summarize SP2 < saved-log.txt   the summary alone
#
# You need this once per milestone, before `gh pr ready`. Every `git push`
# already runs the check on GitHub, so this follows that run: it looks for the
# run whose commit is the one you pushed, waits for it to appear, and watches it.
# It never starts a run of its own, because a second run for the same branch
# cancels the first one (the workflow sets cancel-in-progress), and the run your
# push started is the one the pull request shows.
#
# It reads the milestone-check workflow only. From SP4 your ci.yml adds its own
# jobs to the pull request: `static` runs tflint and checkov, `plan` runs the
# plan, branch protection requires both, and this script looks at neither. A
# green summary here is a green milestone, not a mergeable pull request; the
# pull request's Checks tab is where a red static or plan shows.
#
# Needs the GitHub CLI (https://cli.github.com), signed in with `gh auth login`.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1

GH=${GH:-gh}
WORKFLOW=${WORKFLOW:-milestone-check.yml}
POLLS=${POLLS:-45}          # 45 x 2 s: how long to wait for the push's run to appear
POLL_SLEEP=${POLL_SLEEP:-2}

upper() { printf '%s' "$1" | tr '[:lower:]' '[:upper:]'; }

usage() {
  cat <<'EOF'
Usage: bash .github/scripts/remote-check.sh [milestone] [--explain]
       bash .github/scripts/remote-check.sh --summarize <milestone>   (reads a saved log on stdin)
EOF
}

# Lets the summary be tested without GitHub:
#   bash .github/scripts/remote-check.sh --summarize SP2 < saved-log.txt
if [ "${1:-}" = "--summarize" ]; then
  exec env WHY_EXPLAIN_CMD="bash .github/scripts/remote-check.sh --explain" \
    bash .github/scripts/why.sh --summary "$(upper "${2:-}")"
fi

target=""
explain=0
for arg in "$@"; do
  case "$arg" in
    -h|--help) usage; exit 0 ;;
    --explain) explain=1 ;;
    -*) echo "❌ remote-check.sh: unknown option $arg"; usage; exit 2 ;;
    *) target=$(upper "$arg") ;;
  esac
done

command -v "$GH" >/dev/null 2>&1 || { echo "❌ Install the GitHub CLI first: https://cli.github.com"; exit 1; }

# One preflight before anything is claimed about runs: a signed-out CLI cannot
# answer a single question here, and polling for a minute and a half would end
# in the wrong explanation of why nothing came back.
if ! auth_out=$("$GH" auth status 2>&1); then
  echo "❌ The GitHub CLI can't reach your account, so nothing was checked:"
  printf '%s\n' "$auth_out" | sed 's/^/   /'
  case "$auth_out" in
    *"gh auth login"*) ;;
    *) echo "   Run: gh auth login" ;;
  esac
  exit 1
fi

branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
if [ -z "$branch" ] || ! git rev-parse "@{u}" >/dev/null 2>&1; then
  echo "❌ ${branch:-This branch} isn't on GitHub yet. Push it first: git push -u origin <branch>"
  exit 1
fi
[ -n "$(git status --porcelain 2>/dev/null)" ] && echo "⚠️  You have uncommitted changes. GitHub only checks what you've pushed."

pushed=$(git rev-parse "@{u}")
if [ "$(git rev-parse HEAD)" != "$pushed" ]; then
  echo "⚠️  You have commits that aren't pushed. GitHub checks $(git rev-parse --short "$pushed"), so this result won't include them."
fi

if [ -z "$target" ]; then
  target=$(upper "$(printf '%s' "$branch" | sed -nE 's/^(sp[0-9]{1,2}|ship)([-_].*)?$/\1/p')")
fi
if [ -z "$target" ]; then
  echo "❌ Can't tell the milestone from the branch name \"$branch\"."
  echo "   Run: bash .github/scripts/remote-check.sh <your milestone>, the SPn your branch is named for (sp9-state is SP9), or SHIP for the ship branch."
  exit 1
fi

err=$(mktemp "${TMPDIR:-/tmp}/remote-check-gh.XXXXXX") || exit 1
trap 'rm -f "$err"' EXIT

# The run for this exact commit, if GitHub has created it yet. No --event filter:
# the run a push starts is a "push" run, and an event filter is how the old
# version of this script managed never to see it.
run_for_commit() {
  "$GH" run list --workflow "$WORKFLOW" --branch "$branch" --commit "$pushed" --limit 5 \
    --json databaseId,headSha --jq '.[0].databaseId // empty' 2> "$err"
}

# 0 a run was found (printed), 1 none appeared in time, 2 GitHub could not be asked.
wait_for_run() {
  local attempt=0 found=""
  while [ "$attempt" -lt "$POLLS" ]; do
    if ! found=$(run_for_commit); then return 2; fi
    [ -n "$found" ] && { printf '%s' "$found"; return 0; }
    attempt=$((attempt + 1))
    sleep "$POLL_SLEEP"
  done
  return 1
}

echo "Checking the last commit you pushed to $branch ($(git rev-parse --short "$pushed"))"
echo "Looking for the run your push started..."
run=$(wait_for_run)
run_status=$?

if [ "$run_status" -eq 2 ]; then
  echo "❌ Couldn't ask GitHub for the run, so nothing was checked:"
  sed 's/^/   /' "$err"
  exit 1
fi

if [ -z "$run" ]; then
  echo "❌ No run of $WORKFLOW appeared for this commit after $((POLLS * POLL_SLEEP)) seconds."
  echo "   Nothing was started, on purpose: a second run on the same branch cancels the first."
  echo "   Open the repository's Actions tab, or push an empty commit (git commit --allow-empty -m \"chore: re-run\") and run this again."
  exit 1
fi

start=$SECONDS
"$GH" run watch "$run" --exit-status >/dev/null 2>&1
status=$?
echo "Run finished in $((SECONDS - start))s"

log=$(mktemp "${TMPDIR:-/tmp}/remote-check.XXXXXX") || exit 1
if ! "$GH" run view "$run" --log > "$log" 2>/dev/null; then
  echo "❌ Couldn't download the run's log. Open it on GitHub: $("$GH" run view "$run" --json url --jq .url 2>/dev/null)"
  rm -f "$log"
  exit 1
fi

echo
export WHY_EXPLAIN_CMD="bash .github/scripts/remote-check.sh --explain"
bash .github/scripts/why.sh --summary "$target" < "$log"

# A gate can fail before any step runs, and a run can die before the check
# prints anything at all: ask for the first thing to fix, not for a step.
if [ "$explain" -eq 1 ]; then
  bash .github/scripts/why.sh --first "$target" --explain < "$log"
else
  bash .github/scripts/why.sh --first "$target" < "$log"
fi
rm -f "$log"

echo
echo "Full results: $("$GH" run view "$run" --json url --jq .url 2>/dev/null)"
exit "$status"
