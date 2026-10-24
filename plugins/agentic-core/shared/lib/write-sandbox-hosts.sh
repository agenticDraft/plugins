#!/usr/bin/env bash
# Run: bash plugins/agentic-core/shared/lib/write-sandbox-hosts.sh <declarations>
#
# write-sandbox-hosts.sh <declarations> [--file <path>]
#
# Appends every host the packs declare that the committed settings'
# `sandbox.network.allowedDomains` does not hold yet. Add only: an entry
# already there is never removed or moved, and nothing else in the file is
# touched. When no host is missing the file is not rewritten. Deterministic,
# no model involved.
#
#   <declarations>  the output of collect-pack-declarations.sh; only its
#                   `host` lines are read
#   --file          the committed settings file (default .claude/settings.json)
#
# Output (stdout):
#   created: <file> | updated: <file> | unchanged: <file>
#   added: <host>                one per host appended
#   present: <host>              one per declared host already listed
#   none: no host declared       nothing to do; no file created
#
# Exit codes:
#   0 — done
#   1 — refused: the file is not a JSON object, or its `sandbox`, `network` or
#       `allowedDomains` is of the wrong type; nothing is written
#   2 — usage error, or the declarations file does not exist

set -uo pipefail

usage() {
  echo "usage: write-sandbox-hosts.sh <declarations> [--file <path>]" >&2
  exit 2
}

[[ $# -ge 1 ]] || usage
DECL="$1"; shift
FILE=".claude/settings.json"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --file) [[ $# -ge 2 ]] || usage; FILE="$2"; shift 2 ;;
    *) usage ;;
  esac
done
[[ -f "$DECL" ]] || usage

HOSTS=()
seen=" "
while IFS=$'\t' read -r kind _pack host _rest; do
  [[ "$kind" == "host" && "$seen" != *" $host "* ]] || continue
  seen+="$host "; HOSTS+=("$host")
done < "$DECL"

if (( ${#HOSTS[@]} == 0 )); then
  echo "none: no host declared"
  exit 0
fi

SHAPE='type == "object"
  and ((.sandbox // {}) | type == "object")
  and ((.sandbox.network // {}) | type == "object")
  and ((.sandbox.network.allowedDomains // []) | type == "array")'
if [[ -e "$FILE" ]] && ! jq -e "$SHAPE" "$FILE" >/dev/null 2>&1; then
  echo "refused: $FILE is not a JSON object with an object sandbox.network and a list allowedDomains — fix it by hand, then run setup again"
  exit 1
fi

ADD=() REPORT=""
for host in "${HOSTS[@]}"; do
  if [[ -e "$FILE" ]] && jq -e --arg h "$host" 'any((.sandbox.network.allowedDomains // [])[]; . == $h)' "$FILE" >/dev/null 2>&1; then
    REPORT+="present: $host"$'\n'
  else
    ADD+=("$host")
  fi
done

if (( ${#ADD[@]} == 0 )); then
  printf 'unchanged: %s\n%s' "$FILE" "$REPORT"
  exit 0
fi

ADDED=""
for host in "${ADD[@]}"; do ADDED+="added: $host"$'\n'; done
MERGE='.sandbox.network.allowedDomains = ((.sandbox.network.allowedDomains // []) + $ARGS.positional)'

if [[ -e "$FILE" ]]; then
  TMP="$(mktemp "${FILE}.XXXXXX")" || { echo "refused: cannot write beside $FILE"; exit 1; }
  trap 'rm -f "$TMP"' EXIT
  jq "$MERGE" "$FILE" --args "${ADD[@]}" > "$TMP" 2>/dev/null \
    || { echo "refused: $FILE could not be merged"; exit 1; }
  cat "$TMP" > "$FILE"
  STATE="updated"
else
  mkdir -p "$(dirname "$FILE")"
  jq -n "{} | $MERGE" --args "${ADD[@]}" > "$FILE"
  STATE="created"
fi

printf '%s: %s\n%s%s' "$STATE" "$FILE" "$ADDED" "$REPORT"
exit 0
