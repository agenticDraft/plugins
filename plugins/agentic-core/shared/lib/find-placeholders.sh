#!/usr/bin/env bash
# find-placeholders.sh — Finds every unfilled personal-value placeholder in the
# given files (see shared/personal-values.md). Deterministic, no model involved.
#
# A placeholder is the marker `FILL-IN:` followed by a description of what goes
# there. For each one this prints the file, the line and that description, and
# nothing else from the line: a line can hold a value next to a marker, and a
# value is never printed.
#
# Usage:
#   find-placeholders.sh <file> [<file> ...]
#
# Output (stdout):
#   placeholder: <file>:<line>: <description>   one per marker
#   none: <file>                                one per file with no marker
#
# Exit codes:
#   0 — no file holds a marker
#   1 — at least one marker found
#   2 — usage error: no argument, or a file that does not exist

set -uo pipefail

MARKER="FILL-IN:"

if [[ $# -eq 0 ]]; then
  echo "usage: find-placeholders.sh <file> [<file> ...]" >&2
  exit 2
fi

for f in "$@"; do
  [[ -f "$f" ]] || { echo "not found: $f" >&2; exit 2; }
done

found=0
for f in "$@"; do
  hits=0
  lineno=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    lineno=$((lineno + 1))
    [[ "$line" == *"$MARKER"* ]] || continue
    # The description runs from the marker to the closing quote or the line's end.
    desc="${line#*"$MARKER"}"
    desc="${desc%%\"*}"
    desc="${desc#"${desc%%[![:space:]]*}"}"
    echo "placeholder: $f:$lineno: $desc"
    hits=$((hits + 1))
  done < "$f"
  if (( hits == 0 )); then
    echo "none: $f"
  else
    found=1
  fi
done

exit "$found"
