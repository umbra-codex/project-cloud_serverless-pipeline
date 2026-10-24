#!/usr/bin/env bash
# The milestone check that CI runs on every push. It needs no AWS account
# and no credentials: the Terraform tests use a mocked provider, and the handler
# tests use stub AWS clients.
#
#   .github/scripts/check.sh SP3            one milestone (plus fmt, init, validate)
#   .github/scripts/check.sh all            every milestone listed in milestones.txt
#   .github/scripts/check.sh SP3 all        both (what CI runs on a sp3-* branch)
#
# Uses tofu (CI installs OpenTofu). TF=terraform overrides, but the tests have
# only been run on OpenTofu. Results also go to the Actions run summary.
set -uo pipefail
cd "$(dirname "$0")/../.."

upper() { printf '%s' "$1" | tr '[:lower:]' '[:upper:]'; }
lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# Every milestone has step files. A milestone with no tests is a mistake.
RECAP_IDS="" # no recaps: every milestone has steps

case "${1:-}" in
  "" | -h | --help)
    echo "Usage: .github/scripts/check.sh <milestone...|all>   e.g. .github/scripts/check.sh SP3 all"
    [ -z "${1:-}" ] && exit 2 || exit 0
    ;;
esac

if [ -z "${TF:-}" ]; then
  if command -v tofu >/dev/null 2>&1; then TF=tofu
  elif command -v terraform >/dev/null 2>&1; then TF=terraform
  else echo "❌ Neither tofu nor terraform is on your PATH."; exit 1
  fi
fi

# Expand "all" from milestones.txt and drop duplicates, keeping order.
ids=()
add_id() {
  local id existing
  id=$(upper "$1")
  [ -z "$id" ] && return
  for existing in ${ids[@]+"${ids[@]}"}; do [ "$existing" = "$id" ] && return; done
  ids+=("$id")
}
for arg in "$@"; do
  if [ "$(lower "$arg")" = "all" ]; then
    while IFS= read -r id; do add_id "$id"; done < <(grep -Ev '^[[:space:]]*(#|$)' milestones.txt | tr -d ' \r')
  else
    add_id "$arg"
  fi
done
if [ "${#ids[@]}" -eq 0 ]; then echo "❌ No milestones to check (is milestones.txt empty?)."; exit 1; fi

failed_steps=""
summary_rows=""
failure_log=""
step() {
  local name="$1"; shift
  local out
  if out=$("$@" 2>&1); then
    echo "  ✅ $name"
    summary_rows="$summary_rows| $name | ✅ |
"
  else
    echo "  ❌ $name"
    printf '%s\n' "$out" | sed 's/^/     /'
    failed_steps="$failed_steps
     - $name"
    summary_rows="$summary_rows| $name | ❌ |
"
    failure_log="$failure_log
### $name
\`\`\`
$out
\`\`\`
"
  fi
}

write_summary() {
  [ -n "${GITHUB_STEP_SUMMARY:-}" ] || return 0
  {
    echo "## Milestone check: ${ids[*]}"
    echo
    echo "| Step | Result |"
    echo "|---|---|"
    printf '%s' "$summary_rows"
    echo
    if [ -z "$failed_steps" ]; then
      echo "**👍 Passed.**"
    else
      echo "**👎 Failed.** Fix the first ❌ above, commit, and push. The check runs again on every push."
      echo
      echo "<details><summary>Output of the failed steps</summary>"
      printf '%s\n' "$failure_log"
      echo "</details>"
    fi
  } >> "$GITHUB_STEP_SUMMARY"
}

finish() {
  write_summary
  if [ -z "$failed_steps" ]; then
    echo "👍 ${ids[*]} passed."
    exit 0
  fi
  echo "👎 Failed:$failed_steps"
  echo "   Fix the first one listed, commit, and push. The check runs again on every push."
  exit 1
}

echo "Checking ${ids[*]} with $("$TF" version | head -1)"
step "formatting (fmt -check)" "$TF" fmt -check -recursive .
step "init" "$TF" -chdir=terraform init -backend=false -input=false ${TF_PLUGIN_DIR:+-plugin-dir="$TF_PLUGIN_DIR"} -test-directory=../tests
step "validate" "$TF" -chdir=terraform validate -no-color

# The bootstrap stack is its own root module with its own tests. It is
# initialised without its backend, because the bucket it points at may not
# exist yet, and its tests are run from that directory.
if [ -d terraform/bootstrap ]; then
  step "init (bootstrap)" "$TF" -chdir=terraform/bootstrap init -backend=false -input=false ${TF_PLUGIN_DIR:+-plugin-dir="$TF_PLUGIN_DIR"}
fi

# The step tests can't run on a configuration that doesn't init or validate;
# stop here so the real problem isn't buried under follow-on errors.
case "$failed_steps" in *init* | *validate*) finish ;; esac

# A file check (*.check): each line is "path | regex | message". The file must
# exist and contain a match for the regex. A regex that starts with "!" must NOT
# match, which is how a step pins the shape it forbids.
run_file_check() {
  local check_file="$1" out="" line path rest regex msg negate
  while IFS= read -r line; do
    case "$line" in "" | "#"*) continue ;; esac
    # Split at the first and the last " | ", so the regex itself may contain "|".
    path=${line%% | *}
    rest=${line#* | }
    msg=${rest##* | }
    regex=${rest% | *}
    negate=""
    case "$regex" in "!"*) negate=1; regex=${regex#!} ;; esac
    if [ ! -f "$path" ]; then
      case "$out" in *"$path is missing"*) ;; *) out="$out$path is missing
" ;; esac
    elif [ -n "$negate" ]; then
      if grep -Eq -- "$regex" "$path"; then
        out="$out$path $msg
"
      fi
    elif ! grep -Eq -- "$regex" "$path"; then
      out="$out$path $msg
"
    fi
  done < "$check_file"
  [ -z "$out" ] && return 0
  printf '%s' "$out"
  return 1
}

# An absence check (*.absent): each line is a path that must NOT be committed.
# In a real clone that means "not tracked by git", because an ignored password
# file is supposed to exist on disk; outside a git tree there is no index, so
# presence is the test. Used for a file a milestone deletes, and for secrets
# that must never be committed.
run_absent_check() {
  local check_file="$1" out="" path tracked=""
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 && tracked=1
  while IFS= read -r path; do
    case "$path" in "" | "#"*) continue ;; esac
    if [ -n "$tracked" ]; then
      if git ls-files --error-unmatch -- "$path" >/dev/null 2>&1; then
        out="$out$path is tracked by git, which must never happen
"
      fi
    elif [ -e "$path" ]; then
      out="$out$path must not exist
"
    fi
  done < "$check_file"
  [ -z "$out" ] && return 0
  printf '%s' "$out"
  return 1
}

# A milestone's steps are tests/<id>-<n>-<name>.tftest.hcl, .check, .absent, or
# .test.ts, run in numeric step order.
for id in "${ids[@]}"; do
  lid=$(lower "$id")
  files=$( (ls tests/"$lid"-* 2>/dev/null; ls terraform/bootstrap/tests/"$lid"-* 2>/dev/null) | sort -t- -k2,2n)
  if [ -z "$files" ]; then
    case "$RECAP_IDS" in
      *" $id "*) echo "  ✅ $id (recap: no steps to run)" ;;
      *) echo "  ❌ $id: no test files in tests/"
         failed_steps="$failed_steps
     - $id (no test files)"
         summary_rows="$summary_rows| $id | ❌ no test files |
" ;;
    esac
    continue
  fi
  for file in $files; do
    [ -f "$file" ] || continue
    base=$(basename "$file")
    rest=${base#"$lid"-}
    num=${rest%%-*}
    name=${rest#*-}; name=${name%.tftest.hcl}; name=${name%.check}; name=${name%.absent}; name=${name%.test.ts}
    label="$id step $num ($name)"
    case "$file" in
      *.check) step "$label" run_file_check "$file" ;;
      *.absent) step "$label" run_absent_check "$file" ;;
      *.tftest.hcl)
        case "$file" in
          terraform/bootstrap/*) step "$label" "$TF" -chdir=terraform/bootstrap test -no-color -test-directory=tests -filter=tests/"$base" ;;
          *) step "$label" "$TF" -chdir=terraform test -no-color -test-directory=../tests -filter=../tests/"$base" ;;
        esac
        ;;
      *.test.ts) step "$label" bun test "./$file" ;;
      *) echo "  ❌ $base: unknown test file type" ;;
    esac
  done
done

finish
