#!/usr/bin/env bash
# Run: bash plugins/agentic-core/shared/lib/write-ignore-rules.sh <declarations>
#
# write-ignore-rules.sh <declarations> [--file <path>]
#
# Appends to the project's ignore file every path the packs and the core
# declare as never committed, unless git already ignores it — by any rule in
# any ignore file, a broader one included. Add only: no existing line is
# removed, changed or moved; new lines go in one block under a marker comment.
# Then checks every path the core commits on purpose and reports one that git
# ignores as a conflict, naming the rule; the rule is left for the human.
# Run from the project root, inside its git work tree. Deterministic, no model
# involved.
#
#   <declarations>  the output of collect-pack-declarations.sh; only its
#                   `ignore` and `commit` lines are read
#   --file          the ignore file (default .gitignore)
#
# Output (stdout):
#   created: <file> | updated: <file> | unchanged: <file>
#   added: <path>                                  one per line appended
#   present: <path>                                one per path git already ignores
#   conflict: <path> — ignored by <src>:<n>:<rule>  a committed path git ignores
#
# Exit codes:
#   0 — done
#   1 — refused: not inside a git work tree, or git could not answer
#   2 — usage error, or the declarations file does not exist
#   3 — done, with at least one conflict

set -uo pipefail

MARKER="# Written by setup: paths a delivery run writes, never committed"

usage() {
  echo "usage: write-ignore-rules.sh <declarations> [--file <path>]" >&2
  exit 2
}

[[ $# -ge 1 ]] || usage
DECL="$1"; shift
FILE=".gitignore"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --file) [[ $# -ge 2 ]] || usage; FILE="$2"; shift 2 ;;
    *) usage ;;
  esac
done
[[ -f "$DECL" ]] || usage

[[ "$(git rev-parse --is-inside-work-tree 2>/dev/null)" == "true" ]] \
  || { echo "refused: $(pwd) is not inside a git work tree"; exit 1; }

IGNORE=() COMMIT=()
seen=" "
while IFS=$'\t' read -r kind _owner path _rest; do
  case "$kind" in
    ignore) [[ "$seen" == *" $path "* ]] && continue; seen+="$path "; IGNORE+=("$path") ;;
    commit) COMMIT+=("$path") ;;
  esac
done < "$DECL"

# 0 — ignored, 1 — not ignored, anything else — git could not answer.
ignored() {
  git check-ignore -q --no-index -- "$1" 2>/dev/null
  local rc=$?
  (( rc <= 1 )) || { echo "refused: git check-ignore failed on $1"; exit 1; }
  return "$rc"
}

ADD=() REPORT=""
for path in ${IGNORE[@]+"${IGNORE[@]}"}; do
  if ignored "$path"; then REPORT+="present: $path"$'\n'; else ADD+=("$path"); fi
done

ADDED=""
if (( ${#ADD[@]} == 0 )); then
  STATE="unchanged"
else
  if [[ -e "$FILE" ]]; then STATE="updated"; else STATE="created"; fi
  {
    # Never glue a new line onto an old last line that has no newline.
    [[ -s "$FILE" && -n "$(tail -c 1 "$FILE")" ]] && echo
    [[ -s "$FILE" ]] && ! grep -qxF "$MARKER" "$FILE" && echo
    grep -qxF "$MARKER" "$FILE" 2>/dev/null || echo "$MARKER"
    for path in "${ADD[@]}"; do echo "$path"; ADDED+="added: $path"$'\n'; done
  } >> "$FILE"
fi

CONFLICTS=""
for path in ${COMMIT[@]+"${COMMIT[@]}"}; do
  if ignored "$path"; then
    rule=$(git check-ignore -v --no-index -- "$path" 2>/dev/null | cut -f1)
    CONFLICTS+="conflict: $path — ignored by $rule"$'\n'
  fi
done

printf '%s: %s\n%s%s%s' "$STATE" "$FILE" "$ADDED" "$REPORT" "$CONFLICTS"
[[ -z "$CONFLICTS" ]] || exit 3
exit 0
