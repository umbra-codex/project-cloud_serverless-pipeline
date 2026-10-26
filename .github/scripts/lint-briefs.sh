#!/usr/bin/env bash
# Every checkpoint in a milestone brief must tell the learner the one command to
# run, what to expect, what to do when a step is red, and when GitHub is the
# authority.
#
#   bash .github/scripts/lint-briefs.sh
#
# Markdown has no include, so this is how the fifteen briefs, and the sixteenth
# someone writes next month, keep the rule. Exit 0 when every block is fine, 1
# with one line per problem otherwise.
#
# The guide's own ci.yml runs this in the static job. Your ci.yml, written from
# SP4's step table, does not have that step; LANDING.md says why and gives the
# two lines to add if you edit the briefs in your copy.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1

bad=0
blocks=0
briefs=0

close_block() { # uses the loop's own variables: brief, start, seen_*, lead
  local missing=""
  [ "$seen_cmd" -eq 1 ] || missing="$missing the command (bash .github/scripts/check-local.sh);"
  [ "$seen_expected" -eq 1 ] || missing="$missing what to expect (a line with Expected:);"
  [ "$seen_fix" -eq 1 ] || missing="$missing the fix loop (the words \"same command again\");"
  [ "$seen_github" -eq 1 ] || missing="$missing when GitHub is consulted (a line naming gh pr ready);"
  if [ -n "$missing" ]; then
    echo "$brief:$start: checkpoint block lacks$missing"
    bad=$((bad + 1))
  fi
  # The prose in front of the command has to send the learner to the check
  # first. A block that says "then commit and push:" above the command reads as
  # an instruction to commit before the first run, which is the loop backwards.
  if [ -n "$lead" ] && [ "$seen_cmd" -eq 1 ]; then
    text=$(printf '%s' "$lead" | tr '[:upper:]' '[:lower:]')
    before=${text%%run the check*}
    if [ "$before" = "$text" ]; then
      echo "$brief:$start: the words before the command never tell the learner to run the check"
      bad=$((bad + 1))
    else
      case "$before" in
        *commit*|*push*)
          echo "$brief:$start: the block tells the learner to commit or push before it runs the check"
          bad=$((bad + 1)) ;;
      esac
    fi
  fi
}

# Two shapes exist in the briefs: the blockquoted one this script was written
# for, where every line of a block starts with "> ", and the plain one, where
# the checkpoint is bold text and the commands sit in an ordinary fence. The
# plain shape is the one the guides use now, because a quoted block copies its
# "> " markers into the terminal, where a leading ">" is a redirect. Reading
# both here, once, keeps every rule below unchanged: a plain block is presented
# to this script as a quoted block.
__src="${dir:-docs/milestones}"
[ -d "$__src" ] || __src="docs/milestones"
__tmp="$(mktemp -d)"
trap 'rm -rf "$__tmp"' EXIT
mkdir -p "$__tmp/docs/milestones"
for __f in "$__src"/*.md; do
  [ -f "$__f" ] || continue
  awk '
    /^## / { plain = 0 }
    /^\*\*.*heckpoint:/ { plain = 1; print "> " $0; next }
    plain == 1 && /^#/ { plain = 0; print; next }
    plain == 1 { print "> " $0; next }
    { print }
  ' "$__f" > "$__tmp/docs/milestones/$(basename "$__f")"
done
cd "$__tmp"

for brief in docs/milestones/*.md; do
  [ -f "$brief" ] || continue
  briefs=$((briefs + 1))
  inblock=0
  start=0
  seen_cmd=0
  seen_expected=0
  seen_fix=0
  seen_github=0
  lead=""
  lead_done=0
  fence=0
  n=0
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    # A checkpoint block is a bold blockquote heading that says "Checkpoint:".
    # "Note, not a checkpoint." is prose, and stays prose.
    head=0
    case "$line" in
      "> **"*"Checkpoint:"*) head=1 ;;
    esac
    if [ "$head" -eq 1 ]; then
      if [ "$inblock" -eq 1 ]; then close_block; fi
      inblock=1
      start=$n
      seen_cmd=0
      seen_expected=0
      seen_fix=0
      seen_github=0
      lead=""
      lead_done=0
      fence=0
      prevline=""
      blocks=$((blocks + 1))
      # The heading has to name the step or steps it covers, or the learner
      # cannot tell which check it belongs to.
      if ! printf '%s' "$line" | grep -Eq 'Checkpoint: steps? [0-9]+'; then
        echo "$brief:$n: this checkpoint heading does not name a step; write it as '> **✅ Checkpoint: step N (...)**'"
        bad=$((bad + 1))
      fi
      continue
    fi
    # A heading outside a blockquote is a checkpoint the learner will never see
    # as one, and this lint cannot read it.
    case "$line" in
      "#"*[Cc]"heckpoint"*)
        echo "$brief:$n: a checkpoint heading outside a blockquote is not read as a checkpoint; write it as '> **✅ Checkpoint: ...**'"
        bad=$((bad + 1))
        continue ;;
    esac
    case "$line" in
      ">"*)
        if [ "$inblock" -eq 1 ]; then
          lower=$(printf '%s' "$line" | tr '[:upper:]' '[:lower:]')
          case "$line" in
            '> ```'*) if [ "$fence" -eq 0 ]; then fence=1; else fence=0; fi ;;
          esac
          case "$line" in
            "> bash .github/scripts/check-local.sh"|"> bash .github/scripts/check-local.sh "*)
              seen_cmd=1
              lead_done=1 ;;
          esac
          # A line that starts mid-sentence, right after the previous line ended
          # with a full stop, is a leftover half of a sentence. SP4's block used
          # to carry one: "... explains both tiers." then "pull request (see ...)."
          if [ "$fence" -eq 0 ]; then
            case "$line" in
              "> "[a-z]*)
                case "$prevline" in
                  *.|*:|*\?|*!)
                    echo "$brief:$n: this line starts mid-sentence, right after the previous line ended"
                    bad=$((bad + 1)) ;;
                esac ;;
            esac
          fi
          # Prose in front of the command, with fenced commands left out: a
          # "git commit" inside a fence is an action, not a claim about order.
          if [ "$fence" -eq 0 ] && [ "$lead_done" -eq 0 ]; then
            case "$line" in
              "> bash .github/scripts/check-local.sh"|"> bash .github/scripts/check-local.sh "*) ;;
              ">") ;;
              *) lead="$lead $line" ;;
            esac
          fi
          # Remember the last prose line, for the fragment rule above.
          if [ "$fence" -eq 0 ]; then
            case "$line" in
              '> ```'*) ;;
              *) prevline=$line ;;
            esac
          fi
          case "$line" in
            *"bash .github/scripts/check-local.sh"*)
              case "$line" in
                "> bash .github/scripts/check-local.sh"|"> bash .github/scripts/check-local.sh "*) ;;
                *) echo "$brief:$n: the checkpoint command must be on its own line, '> bash .github/scripts/check-local.sh'"; bad=$((bad + 1)) ;;
              esac ;;
          esac
          case "$lower" in
            *"expected:"*) seen_expected=1 ;;
          esac
          case "$lower" in
            *"same command again"*) seen_fix=1 ;;
          esac
          case "$lower" in
            *"gh pr ready"*) seen_github=1 ;;
          esac
          # The old flow sent the learner to a results page instead of a command.
          case "$line" in
            *"Open the results"*)
              echo "$brief:$n: sends the learner to the results page instead of a command"
              bad=$((bad + 1)) ;;
          esac
        fi ;;
      *)
        if [ "$inblock" -eq 1 ]; then
          close_block
          inblock=0
        fi ;;
    esac
  done < "$brief"
  if [ "$inblock" -eq 1 ]; then close_block; fi
done

if [ "$bad" -eq 0 ]; then
  echo "👍 $blocks checkpoint blocks in $briefs briefs tell the learner the command, what to expect, how to fix a red step, and when GitHub is the authority."
  exit 0
fi
echo "👎 $bad problem(s) in $blocks checkpoint blocks across $briefs briefs."
exit 1
