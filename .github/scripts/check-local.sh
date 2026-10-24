#!/usr/bin/env bash
# Runs the same milestone check CI runs, in your terminal, and prints one screen.
#
#   bash .github/scripts/check-local.sh            the milestone your branch points at (sp2-state -> SP2)
#   bash .github/scripts/check-local.sh SP2        a specific milestone
#   bash .github/scripts/check-local.sh --explain  the same, plus every line the check printed
#
# No AWS account and no push: every plan in the tests runs against a mocked
# provider. It runs .github/scripts/check.sh itself, with the same arguments CI
# passes, so it cannot drift into a different check. It keeps that check's
# working files in .terraform/check/ (already ignored), so your own provider
# cache is left alone. GitHub is still the authority: this is a preview of the
# same check.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1

PIN="1.13.1"
upper() { printf '%s' "$1" | tr '[:lower:]' '[:upper:]'; }

usage() {
  cat <<'EOF'
Usage: bash .github/scripts/check-local.sh [milestone] [--explain]
  milestone   defaults to the one your branch name points at (sp2-state -> SP2)
  --explain   also print every line the check printed
EOF
}

target=""
explain=0
for arg in "$@"; do
  case "$arg" in
    -h|--help) usage; exit 0 ;;
    --explain) explain=1 ;;
    -*) echo "❌ check-local.sh: unknown option $arg"; usage; exit 2 ;;
    *) target=$(upper "$arg") ;;
  esac
done

if [ -z "${TF:-}" ]; then
  if command -v tofu >/dev/null 2>&1; then TF=tofu
  elif command -v terraform >/dev/null 2>&1; then TF=terraform
  else
    echo "❌ Neither tofu nor terraform is on your PATH. Install OpenTofu $PIN (see SP0, \"Before step 1\")."
    exit 1
  fi
fi
export TF

if [ "$TF" = "terraform" ]; then
  echo "⚠️  Using terraform. This guide is written for OpenTofu, and CI runs $PIN there, so a result here can differ."
fi

version=$("$TF" version 2>/dev/null | head -1 | sed -E 's/.*v([0-9]+\.[0-9]+\.[0-9]+).*/\1/')
echo "Checking with $("$TF" version 2>/dev/null | head -1)"
if [ -n "$version" ] && [ "$version" != "$PIN" ]; then
  echo "⚠️  $TF is $version; CI pins $PIN. A result here can differ from GitHub's. Install $PIN to match."
fi

if [ -z "$target" ]; then
  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
  target=$(upper "$(printf '%s' "$branch" | sed -nE 's/^(sp[0-9]{1,2}|ship)([-_].*)?$/\1/p')")
  if [ -z "$target" ]; then
    # Never name a specific milestone here: a learner on SP9 does not want a
    # hint about SP2. The branch is the usual source, so say what shape works.
    echo "❌ Can't tell the milestone from the branch name \"${branch:-$(pwd)}\"."
    echo "   Run: bash .github/scripts/check-local.sh <your milestone>, the SPn your branch is named for (sp9-state is SP9), or SHIP for the ship branch."
    exit 2
  fi
fi

if [ ! -f "docs/milestones/$target.md" ]; then
  echo "❌ docs/milestones/$target.md is not here. Run this from the repository root."
  exit 2
fi

if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
  echo "⚠️  You have uncommitted changes. This checks your working tree; GitHub checks commits, so commit before you trust a green run there."
fi

# --- the check itself: the same file CI runs, with its working files moved ---
# .terraform/ is already in the ignore file, so the check's working folder never
# shows up as an untracked change, and the learner's own provider cache is not
# touched.
mkdir -p .terraform/check || exit 1
log=.terraform/check/last-run.log
echo
echo "Running .github/scripts/check.sh $target all (the first run downloads the providers, so it takes longer)..."
TF_DATA_DIR=.terraform/check bash .github/scripts/check.sh "$target" all > "$log" 2>&1
status=$?

echo
WHY_EXPLAIN_CMD="bash .github/scripts/check-local.sh --explain" bash .github/scripts/why.sh --summary "$target" < "$log"
WHY_EXPLAIN_CMD="bash .github/scripts/check-local.sh --explain" bash .github/scripts/why.sh --first "$target" < "$log"

if [ "$explain" -eq 1 ]; then
  echo
  echo "Full check output:"
  cat "$log"
fi

echo
echo "The whole run is saved in .terraform/check/last-run.log."
echo "GitHub is the authority: the push you make next runs the same check there, and"
echo "\"bash .github/scripts/remote-check.sh\" follows that run and prints the same summary."

if [ "$status" -ne 0 ]; then exit 1; fi
exit 0
