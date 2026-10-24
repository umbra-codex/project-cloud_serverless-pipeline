#!/usr/bin/env bash
# Why a step failed, and which part of the brief to re-read.
#
#   .github/scripts/check.sh SP2 | bash .github/scripts/why.sh SP2 2
#   bash .github/scripts/why.sh SP2 2 --explain      the same, then that step's raw output
#   bash .github/scripts/why.sh --summary SP2        the progress summary alone
#   bash .github/scripts/why.sh --first SP2          the first thing to fix
#   bash .github/scripts/why.sh --next SP2           the number of the first failed step
#
# It reads the check's own output on stdin, so it works for a run on your machine
# and for a run on GitHub: check-local.sh and remote-check.sh both call it.
# Nothing here knows the answer: every line comes from the check's output or
# from the brief named on that line.
set -uo pipefail
cd "$(dirname "$0")/../.."

use() {
  cat <<'EOF'
Usage: bash .github/scripts/why.sh <milestone> <step> [--explain]   (reads check output on stdin)
       bash .github/scripts/why.sh --summary <milestone> [--explain]
       bash .github/scripts/why.sh --first <milestone> [--explain]
       bash .github/scripts/why.sh --next <milestone> [--explain]
EOF
}

upper() { printf '%s' "$1" | tr '[:lower:]' '[:upper:]'; }
lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# Whatever the caller wants the learner to type for the whole run. A local run
# and a GitHub run differ, so the hint is theirs to set.
EXPLAIN_CMD=${WHY_EXPLAIN_CMD:-bash .github/scripts/check-local.sh --explain}

# One line per record, without the "job<TAB>step<TAB>" prefix a GitHub log line
# carries and without the timestamp, so the same code reads a terminal run and a
# GitHub run. Colour goes too: an escape sequence between the indentation and
# the word would defeat every match below.
normalize() {
  tr -d '\r' | tr -d '\357\273\277' | tr -d '\033' | sed -E 's/\[[0-9;]*[mK]//g' | awk -F'\t' '
    NF >= 3 { s = ""; for (i = 3; i <= NF; i++) s = s (i > 3 ? "\t" : "") $i; print s; next }
    { print }
  ' \
    | sed -E 's/^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z *//' \
    | sed -E 's/^ *(✅|❌) /  \1 /'
}

tmp=$(mktemp "${TMPDIR:-/tmp}/why.XXXXXX") || exit 1
trap 'rm -f "$tmp" "$tmp.v" "$tmp.blk" "$tmp.clean"' EXIT

mode=why
case "${1:-}" in
  ""|-h|--help) use; [ -z "${1:-}" ] && exit 2 || exit 0 ;;
  --summary) mode=summary; shift ;;
  --first) mode=first; shift ;;
  --next) mode=next; shift ;;
esac

target=$(upper "${1:-}")
if [ -z "$target" ]; then use; exit 2; fi
shift

step=""
explain=0
for arg in "$@"; do
  case "$arg" in
    --explain) explain=1 ;;
    -h|--help) use; exit 0 ;;
    *[!0-9]*) echo "❌ why.sh: \"$arg\" is not a step number."; exit 2 ;;
    *) step=$arg ;;
  esac
done

normalize > "$tmp"
grep -E '^  (✅|❌) ' "$tmp" > "$tmp.v" 2>/dev/null

# Prints the block of indented detail that follows a verdict line, e.g. the
# detail of "  ❌ SP2 step 2 (migrate)".
block() { # $1 = line number of the verdict in $tmp
  awk -v start="$1" '
    NR == start { inside = 1; next }
    inside && /^  (✅|❌) / { exit }
    # The ending line of the run is not part of any block.
    inside && /^(👍 |👎 )/ { exit }
    inside { print }
  ' "$tmp"
}

# The section of the brief to re-read for one step: the nearest heading above
# the checkpoint block that names the step, and the numbered items between that
# heading and the block. Derived from the brief, so a new brief needs no table
# here and the numbers cannot go stale.
pointer() { # $1 = milestone, $2 = step
  brief="docs/milestones/$1.md"
  [ -f "$brief" ] || return 0

  # The checkpoint block that names the step. Not every step has one: a block
  # like "steps 4 and 5" covers two, and a step can be described in prose
  # instead. A block may name a range instead ("steps 1 to 3"), which covers
  # every step between the two numbers; the range is read first, so a block
  # written either way finds the same steps.
  lineno=$(awk -v want="$2" '
    function range(line,   seg) {
      if (!match(line, /steps? [0-9]+ to [0-9]+/)) return ""
      seg = substr(line, RSTART, RLENGTH)
      gsub(/[^0-9]+/, " ", seg)
      return seg
    }
    /^> \*\*/ && index(tolower($0), "checkpoint") {
      seg = range(tolower($0))
      if (seg != "") {
        split(seg, r, " ")
        if (want + 0 >= r[1] + 0 && want + 0 <= r[2] + 0) { print NR; exit }
        next
      }
      s = $0
      gsub(/[^0-9]+/, " ", s)
      n = split(s, parts, " ")
      for (i = 1; i <= n; i++) if (parts[i] == want) { print NR; exit }
    }
  ' "$brief" 2>/dev/null)

  if [ -z "$lineno" ]; then
    # A section of its own, written for this step: "### About step 5".
    found=$(grep -n -E "^#{1,3} .*[Ss]teps? $2([^0-9]|$)" "$brief" 2>/dev/null | head -1)
    if [ -n "$found" ]; then
      hline=${found#*:}
      case "$hline" in
        *"Before step $2"*) ;;
        *) echo "Re-read $brief, \"$hline\"."; return 0 ;;
      esac
    fi
    # Otherwise the last block before this step: its section is still the one
    # to read, because the step builds on it.
    lineno=$(awk -v want="$2" '
      /^> \*\*/ && index(tolower($0), "checkpoint") {
        s = $0
        gsub(/[^0-9]+/, " ", s)
        n = split(s, parts, " ")
        for (i = 1; i <= n; i++) if (parts[i] != "" && parts[i] + 0 < want + 0) last = NR
      }
      END { if (last) print last }
    ' "$brief" 2>/dev/null)
  fi

  [ -n "$lineno" ] || return 0
  found=$(head -n $((lineno - 1)) "$brief" | grep -n -E '^#{1,3} ' | tail -1)
  # A block that covers two steps can sit after both parts it teaches, so the
  # nearest heading above it is right for the first step and wrong for the second:
  # SP0's "steps 1 and 2" block sits under "Part 2", and its words name both
  # parts. For a multi-step block, match the step's own label instead.
  if [ -n "$found" ]; then
    bhead=$(sed -n "${lineno}p" "$brief")
    # How many steps the block names, and which of them this one is: "steps 1
    # and 2" gives 2 and, for step 2, 2. "steps 1 to 3" gives 3 and, for step 2,
    # 2. The parenthetical that follows names each step in the same order,
    # separated by commas or by "and", so it can be read position by position.
    ord=$(printf '%s' "$bhead" | awk -v want="$2" '
      function range(line,   seg) {
        if (!match(line, /steps? [0-9]+ to [0-9]+/)) return ""
        seg = substr(line, RSTART, RLENGTH)
        gsub(/[^0-9]+/, " ", seg)
        return seg
      }
      { seg = range(tolower($0))
        if (seg != "") {
          split(seg, r, " ")
          m = (r[2] + 0) - (r[1] + 0) + 1
          k = (want + 0) - (r[1] + 0) + 1
          print m " " k
          next
        }
        s = $0; gsub(/[^0-9]+/, " ", s); n = split(s, p, " "); k = 0; m = 0
        for (i = 1; i <= n; i++) if (p[i] != "") { m++; if (p[i] == want) k = m }
        print m " " k }')
    nsteps=${ord%% *}
    kth=${ord#* }
    label=$(printf '%s' "$bhead" | sed -nE 's/.*\(([^)]*)\)[^()]*$/\1/p')
    word=$(printf '%s' "$label" | awk -v k="$kth" -F' and |, ' '{ if (k != 0 && k <= NF) print $k }')
    if [ "${nsteps:-0}" -ge 2 ] && [ -n "$word" ]; then
      cand=$(head -n $((lineno - 1)) "$brief" | grep -n -E '^#{1,3} ' | grep -i -F "$word" | tail -1)
      [ -n "$cand" ] && found=$cand
    fi
  fi
  if [ -z "$found" ]; then
    echo "Re-read $brief."
    return 0
  fi
  hno=${found%%:*}
  hline=${found#*:}
  # The numbered items that belong to this heading: its own section only. A part
  # can hold one file and the next part's file can sit below the checkpoint
  # block, so the search stops at the next heading of the same level, whichever
  # comes first.
  hashes=${hline%%[^#]*}
  level=${#hashes}
  end=$((lineno - 1))
  next=$(sed -n "$((hno + 1)),\$p" "$brief" | grep -n -E "^#{$level}([^#]|$)" | head -1 | cut -d: -f1)
  if [ -n "$next" ] && [ $((hno + next - 1)) -lt "$end" ]; then end=$((hno + next - 1)); fi
  items=$(sed -n "$((hno + 1)),${end}p" "$brief" \
    | grep -E '^#### [0-9]+\.' | sed -E 's/^#### ([0-9]+)\..*/\1/')
  first=$(printf '%s\n' "$items" | head -1)
  last=$(printf '%s\n' "$items" | tail -1)
  if [ -z "$first" ]; then
    echo "Re-read $brief, \"$hline\"."
  elif [ "$first" = "$last" ]; then
    echo "Re-read $brief, \"$hline\", item $first."
  else
    echo "Re-read $brief, \"$hline\", items $first to $last."
  fi
}

# Terraform draws a diagnostic's value excerpt in a box. Only the words outside
# the box are the message, so the box is dropped whole. The glyphs are matched
# as characters in awk, so no locale has to agree with the terminal about them.
unbox() { # $1 = block file, $2 = output file
  awk '
    {
      lead = $0
      sub(/^[[:space:]]*/, "", lead)
      c = substr(lead, 1, 1)
      if (c == "│" || c == "├" || c == "┌" || c == "└" || c == "╵" || c == "╷") next
      print
    }
  ' "$1" > "$2"
}

# From one failed check's output, the shortest true statement of what went
# wrong: the undeclared address, or the assertion's own message, or the one file
# check line that failed. Nothing is invented; every word comes from the output.
collapse() { # $1 = block file
  local addrs first rest lost msg errors line path note same
  unbox "$1" "$tmp.clean"

  addrs=$(grep -o 'There is no managed resource "[A-Za-z0-9_]*" "[A-Za-z0-9_]*"' "$1" 2>/dev/null \
    | sed -E 's/.*"([A-Za-z0-9_]+)" "([A-Za-z0-9_]+)".*/\1.\2/' \
    | awk '!seen[$0]++')
  if [ -n "$addrs" ]; then
    first=$(printf '%s\n' "$addrs" | head -1)
    rest=$(printf '%s\n' "$addrs" | tail -n +2 | paste -sd, - | sed 's/,/, /g')
    if [ -n "$rest" ]; then
      echo "Nothing is named $first yet. Also missing: $rest."
    else
      echo "Nothing is named $first yet."
    fi
    return 0
  fi

  # A file check (*.check, *.absent) prints "<path> <message>" and nothing else,
  # and its message is written for a learner, so it is printed as it stands.
  # A bare file name (the formatter's list) has no message at all, and must not
  # come back as "path: path".
  if ! grep -qE '\.tftest\.hcl|\.test\.ts|^ *Failure!|^ *Error: ' "$1" 2>/dev/null; then
    # Terraform's own init or plan diagnostic: tofu draws the error in a box and
    # prints progress lines above it ("Initializing: provider plugins..."). The
    # box glyphs are not part of the message, and the wrap is not punctuation, so
    # each paragraph is joined back into one line.
    if grep -qE '^[[:space:]]*[│╷╵├┌└]' "$1" 2>/dev/null; then
      cleaned=$(awk '
        function flush() { if (cur != "") { n++; para[n] = cur; cur = "" } }
        { s = $0
          sub(/^[[:space:]]+/, "", s)
          c = substr(s, 1, 1)
          if (c == "│" || c == "├" || c == "┌" || c == "└" || c == "╵" || c == "╷") {
            s = substr(s, 2); sub(/^[[:space:]]+/, "", s)
          }
          if (s == "") { flush(); next }
          if (s ~ /\.\.\.$/) next
          if (s ~ /^- /) next
          if (s ~ /^Error: /) s = substr(s, 8)
          cur = (cur == "" ? s : cur " " s)
        }
        END { flush(); for (i = 1; i <= n; i++) print para[i] }
      ' "$1")
      head=$(printf '%s\n' "$cleaned" | head -1)
      [ -n "$head" ] || return 0
      echo "$head"
      note=$(printf '%s\n' "$cleaned" | tail -n +2 | awk 'NF { printf "%s%s", sep, $0; sep = "; " }')
      [ -n "$note" ] && echo "Also failing: $note"
      return 0
    fi
    line=$(grep -E '^[[:space:]]*[^[:space:]]' "$1" | head -1 | sed -E 's/^[[:space:]]+//')
    [ -n "$line" ] || return 0
    case "$line" in
      *" is missing") echo "$line"; return 0 ;;
      *" "*) ;;
      *) echo "$line"; return 0 ;;
    esac
    path=${line%% *}
    msg=${line#* }
    echo "$path: $msg"
    note=""
    while IFS= read -r rest; do
      rest=$(printf '%s' "$rest" | sed -E 's/^[[:space:]]+//')
      [ -n "$rest" ] || continue
      case "$rest" in
        "$path "*) same=${rest#"$path "} ;;
        *) same=$rest ;;
      esac
      note="$note${note:+; }$same"
    done <<EOF2
$(sed -E 's/^[[:space:]]+//' "$1" | tail -n +2)
EOF2
    [ -n "$note" ] && echo "Also failing: $note"
    return 0
  fi

  # A bun test failure: the block starts with bun's version banner, which is not
  # a message. The useful lines are "(fail) <test name>" and the first
  # "error: <message>" under it.
  if grep -qE '^ *\(fail\) ' "$1" 2>/dev/null; then
    name=$(grep -E '^ *\(fail\) ' "$1" | head -1 | sed -E 's/^ *\(fail\) //; s/ \[[0-9.]+ms\]$//')
    what=$(grep -E '^ *error: ' "$1" | head -1 | sed -E 's/^ *error: //')
    if [ -n "$name" ] && [ -n "$what" ]; then
      echo "$name: $what"
    elif [ -n "$name" ]; then
      echo "$name"
    elif [ -n "$what" ]; then
      echo "$what"
    fi
    return 0
  fi

  # A Terraform test failure: the paragraph under "Error: Test assertion failed"
  # is the assertion's own error_message, wrapped by the terminal.
  msg=$(awk '
    function flush() { if (cur != "") { n++; para[n] = cur; cur = "" } }
    {
      s = $0
      sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s)
      if (s == "") { flush(); next }
      if (!seen) { if (s ~ /^Error: /) seen = 1; next }
      if (s ~ /^Error: /) exit
      if (s ~ /^on .* line [0-9]+/) next
      if (s ~ /^[0-9]+:/) next
      if (s ~ /^[│├┌└╵╷]/) next
      # The next run result trailer, printed with no blank line above it:
      # run "name"... pass. It is not part of the assertion message.
      if (s ~ /^run ".*"\.\.\. (pass|fail)$/) { flush(); exit }
      cur = (cur == "" ? s : cur " " s)
    }
    END {
      flush()
      for (i = n; i >= 1; i--) if (substr(para[i], 1, 1) != "-" && substr(para[i], 1, 8) != "Failure!") { print para[i]; exit }
    }
  ' "$tmp.clean")
  [ -n "$msg" ] || msg=$(sed -E 's/^[[:space:]]+//' "$1" | awk 'NF { print; exit }')
  [ -n "$msg" ] || return 0
  errors=$(grep -c -E '^ *Error: ' "$1" 2>/dev/null || true)
  case "$errors" in ''|0|1) echo "$msg" ;; *) echo "$msg (first of $errors errors)" ;; esac
}

step_name() { # $1 = milestone, $2 = step
  local line name
  line=$(grep -E "^  (✅|❌) $1 step $2 " "$tmp.v" 2>/dev/null | head -1)
  if [ -n "$line" ]; then
    name=${line#  ✅ }
    name=${name#  ❌ }
    printf '%s' "$name"
  fi
}

# The other milestones in milestones.txt, as a short list for the summary line.
other_list() {
  local all n shown out i
  all=$(echo $other_seen)
  n=$(printf '%s\n' "$all" | wc -l | tr -d ' ')
  if [ "$n" -le 6 ]; then
    printf '%s' "$all" | paste -sd, - | sed 's/,/, /g'
    return 0
  fi
  out=""
  i=0
  for one in $all; do
    i=$((i + 1))
    [ "$i" -le 6 ] || break
    out="$out${out:+, }$one"
  done
  echo "$out, and $((n - 6)) more"
}

# ---------------------------------------------------------------- summary ---
# One line per check file and one aggregate gate line. It returns 1 unless the
# whole milestone is green, so a caller cannot mistake a red run for a pass.
summary() {
  local line mark name total=0 passed=0 next="" rows="" others=0 other_bad="" other_seen=""
  local seen=0 bad=0 boot=""
  local finished=0 started=0 expected=0 lid
  while IFS= read -r line; do
    case "$line" in
      "  ✅ "*) mark="✅"; name=${line#  ✅ } ;;
      "  ❌ "*) mark="❌"; name=${line#  ❌ } ;;
      *) continue ;;
    esac
    case "$name" in
      "formatting (fmt -check)"|init|validate)
        seen=$((seen + 1))
        [ "$mark" = "✅" ] || bad=$((bad + 1)) ;;
      "init (bootstrap)")
        [ "$mark" = "✅" ] || boot="init (bootstrap)" ;;
      "$1 step "*|"$1: "*)
        started=1
        total=$((total + 1))
        if [ "$mark" = "✅" ]; then
          passed=$((passed + 1))
          rows="${rows}  ✅ $name
"
        elif [ -z "$next" ]; then
          next="$name"
          rows="${rows}  ❌ $name      <- next
"
        else
          rows="${rows}  ❌ $name
"
        fi ;;
      *)
        id=${name%% *}; id=${id%:}
        case "$id" in
          "$1") started=1 ;;
          *)
            case " $other_seen " in
              *" $id "*) ;;
              *) other_seen="$other_seen $id"; others=$((others + 1)) ;;
            esac
            [ "$mark" = "✅" ] || case " $other_bad " in *" $id "*) ;; *) other_bad="$other_bad $id" ;; esac ;;
        esac ;;
    esac
  done < "$tmp.v"

  # The check ends every complete run with "👍 ... passed." or "👎 Failed:".
  # Without one of those the log stopped early (a cancelled run, a killed
  # check.sh, the job's timeout), and "everything I saw was green" is not a pass.
  if grep -qE '^(👍 .*passed\.|👎 Failed:)' "$tmp"; then finished=1; fi

  if [ "$seen" -eq 0 ] && [ "$total" -eq 0 ]; then
    echo "$1: the run stopped before the check printed a result"
    echo "  ⚠️  no formatting, init, or validate row was printed"
    return 1
  fi

  if [ "$total" -eq 0 ]; then
    # Gate rows but no step rows: the run died after the gates. Saying "no
    # checks ran" there is wrong, because the gate checks did run and one is red.
    # The bootstrap row is printed under the compressed gate line, so "above"
    # would point at nothing.
    if [ "$bad" -gt 0 ]; then
      echo "$1: the steps did not run: the gate above is red and the run stopped there"
    elif [ -n "$boot" ]; then
      echo "$1: the steps did not run: $boot is red and the run stopped there"
    else
      echo "$1: the steps did not run: no step row was printed"
    fi
  else
    # How many check files this milestone is defined to have, so a truncated log
    # cannot report "2 of 2" when the milestone has four.
    lid=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
    expected=$(ls tests/$lid-* 2>/dev/null | wc -l | tr -d ' ')
    if [ -d terraform/bootstrap/tests ]; then
      expected=$((expected + $(ls terraform/bootstrap/tests/$lid-* 2>/dev/null | wc -l | tr -d ' ')))
    fi
    if [ "$expected" -gt "$total" ]; then
      echo "$1: $passed of $expected checks green, and the check reported only $total of them"
    else
      echo "$1: $passed of $total checks green"
    fi
  fi
  if [ "$bad" -gt 0 ]; then
    echo "  ❌ a gate before the steps is red, which fails the run on its own (fix this first)"
  elif [ "$seen" -eq 0 ]; then
    echo "  ⚠️  no formatting, init, or validate row was printed"
  elif [ "$seen" -lt 3 ]; then
    echo "  ⚠️  only $seen of the three gate rows were printed"
  else
    echo "  ✅ formatting, init, validate"
  fi
  [ -n "$boot" ] && echo "  ❌ $boot"
  printf '%s' "$rows"
  if [ -n "$other_seen" ] && [ -z "$other_bad" ]; then
    echo "  ✅ every other milestone in milestones.txt passes ($(other_list))"
  fi
  if [ -n "$other_bad" ]; then
    echo "  ❌ red outside $1: $(echo $other_bad | sed 's/ /, /g')"
  fi
  echo
  if [ "$passed" -eq "$total" ] && [ "$total" -gt 0 ] && [ "$seen" -eq 3 ] &&
     [ "$bad" -eq 0 ] && [ -z "$boot" ] && [ -z "$other_bad" ] && [ "$finished" -eq 1 ]; then
    echo "👍 $1 passed."
    return 0
  fi
  if [ "$finished" -eq 0 ]; then
    echo "  ⚠️  the run stopped before the check finished: it printed no 👍 or 👎 line"
  fi
  return 1
}

# One failed step: what it was, where to re-read, and the check's own message.
step_explain() { # $1 = milestone, $2 = step
  local sname where line start
  sname=$(step_name "$1" "$2")
  where=$(pointer "$1" "$2")
  line="Next: $1 step $2"
  if [ -n "$sname" ]; then
    sname=${sname#"$1 step $2 "}
    sname=${sname#(}; sname=${sname%)}
    [ -n "$sname" ] && line="$line ($sname)"
  fi
  line="$line."
  [ -n "$where" ] && line="$line $where"
  echo "$line"
  start=$(grep -n -E "^  ❌ $1 step $2 " "$tmp" 2>/dev/null | head -1 | cut -d: -f1)
  if [ -n "$start" ]; then
    block "$start" > "$tmp.blk"
    collapse "$tmp.blk"
    if [ "$explain" -eq 1 ]; then
      echo
      cat "$tmp.blk"
    fi
  else
    echo "The check printed no detail for this step."
  fi
  echo "Run $EXPLAIN_CMD for the full output."
}

# The first thing to fix: a red gate row (they run before every step), then the
# first red step, then the case where the run died before the check printed
# anything. Prints nothing and returns 3 when there is nothing red.
first() { # $1 = milestone
  local gate start n red name id files count
  for gate in "formatting (fmt -check)" init validate "init (bootstrap)"; do
    # Exact row, not a prefix: "  ❌ init" is a prefix of "  ❌ init (bootstrap)",
    # so a prefix match reported the bootstrap gate as "red at init" while init
    # was green on the same screen.
    start=$(awk -v want="  ❌ $gate" '$0 == want { print NR; exit }' "$tmp" 2>/dev/null)
    [ -n "$start" ] || continue
    block "$start" > "$tmp.blk"
    if [ "$gate" = "formatting (fmt -check)" ]; then
      # The formatter prints one file name per line and nothing else, so the
      # block is a list, not a "<path> <message>" pair.
      files=$(sed -E 's/^ +//' "$tmp.blk" | grep -E '\.tf$' | head -6 | paste -sd, - | sed 's/,/, /g')
      count=$(sed -E 's/^ +//' "$tmp.blk" | grep -cE '\.tf$')
      if [ -n "$files" ] && [ "${count:-0}" -gt 6 ]; then
        files="$files, and $((count - 6)) more"
      fi
      if [ -n "$files" ]; then
        echo "Next: $1 is red at formatting (fmt -check), which fails the whole run on its own. The formatter wants to change these files:"
        echo "$files"
      else
        echo "Next: $1 is red at formatting (fmt -check), which fails the whole run on its own. The check's own message:"
        collapse "$tmp.blk"
      fi
      if [ "$explain" -eq 1 ]; then echo; cat "$tmp.blk"; fi
      echo "Run tofu fmt -recursive from the repo root, then the same command again."
      return 0
    fi
    echo "Next: $1 is red at $gate, so no step could run on this configuration. The check's own message:"
    collapse "$tmp.blk"
    if [ "$explain" -eq 1 ]; then echo; cat "$tmp.blk"; fi
    case "$gate" in
      init)
        echo "init downloads the providers, so this is usually the network or the plugin cache." ;;
      validate)
        echo "The message names the file and the line." ;;
      *)
        echo "The bootstrap folder is its own root module, and its init has to succeed too." ;;
    esac
    return 0
  done

  n=$(grep -E "^  ❌ $1 step [0-9]+ " "$tmp.v" 2>/dev/null | head -1 | sed -E "s/^  ❌ $1 step ([0-9]+) .*/\1/")
  if [ -n "$n" ]; then
    step_explain "$1" "$n"
    return 0
  fi

  # A red row that is not one of this milestone's steps: an earlier milestone
  # broke, which the check re-runs on every push.
  red=$(grep -E '^  ❌ ' "$tmp.v" 2>/dev/null | head -1)
  if [ -n "$red" ]; then
    name=${red#  ❌ }
    id=${name%% *}; id=${id%:}
    echo "Next: $1: $id is red ($name). Every milestone in milestones.txt is re-run on each push, so a change here can break one you finished."
    start=$(grep -n -F "$red" "$tmp" 2>/dev/null | head -1 | cut -d: -f1)
    if [ -n "$start" ]; then
      block "$start" > "$tmp.blk"
      collapse "$tmp.blk"
      if [ "$explain" -eq 1 ]; then echo; cat "$tmp.blk"; fi
    fi
    echo "Re-read docs/milestones/$id.md, and run bash .github/scripts/check-local.sh $id on its own."
    echo "Run $EXPLAIN_CMD for the full output."
    return 0
  fi

  # Rows exist, none is red, and the run ended: there is nothing to fix.
  if [ -s "$tmp.v" ] && grep -qE '^(👍 .*passed\.|👎 Failed:)' "$tmp"; then
    return 3
  fi

  # No verdict rows at all, or rows but no ending: the run stopped before the
  # check reported anything, so the cause is whatever the last step printed.
  if [ -s "$tmp.v" ]; then
    echo "Next: $1: the run stopped before the check finished. The last lines it printed:"
  else
    echo "Next: $1: nothing was checked. The run stopped before the check printed a result."
  fi
  tail -n 80 "$tmp" > "$tmp.blk"
  if grep -q 'Error: ' "$tmp.blk"; then
    n2=$(collapse "$tmp.blk")
  else
    n2=$(grep -v -E '^  (✅|❌) ' "$tmp.blk" | grep -v '^[[:space:]]*$' | tail -1 | sed -E 's/^[[:space:]]+//')
  fi
  [ -n "$n2" ] && echo "$n2"
  echo "Run $EXPLAIN_CMD for the full output."
  return 1
}

case "$mode" in
  summary) summary "$target"; exit $? ;;
  first) first "$target"; exit $? ;;
  next)
    line=$(grep -E "^  ❌ $target step [0-9]+ " "$tmp.v" 2>/dev/null | head -1)
    [ -n "$line" ] || exit 3
    printf '%s\n' "$line" | sed -E "s/^  ❌ $target step ([0-9]+) .*/\1/"
    exit 0 ;;
esac

if [ -z "$step" ]; then use; exit 2; fi

step_explain "$target" "$step"
