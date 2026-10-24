#!/usr/bin/env bash
# Run: bash plugins/agentic-core/shared/lib/write-credential-placeholders.sh <declarations>
#
# write-credential-placeholders.sh <declarations> [--file <path>]
#
# Adds a placeholder to the credentials file for every variable the packs
# declare that has no key there yet (shared/personal-values.md): the key gets
# "FILL-IN: <its source>" in the file's `env` object. A key already present,
# filled or not, is never changed, and nothing else in the file is touched.
# A variable a login replaces (a `login` line) gets no key; it is named as an
# alternative. Deterministic, no model involved.
#
# A value is never read into this script and never printed, not even in a
# refusal: the file is only asked which keys it has.
#
#   <declarations>  the output of collect-pack-declarations.sh; only its
#                   `env` and `login` lines are read
#   --file          the credentials file (default .claude/settings.local.json)
#
# The file is created, readable by its owner only, when absent and at least one
# key is needed. When no key is missing it is not rewritten.
#
# Output (stdout):
#   created: <file> | updated: <file> | unchanged: <file>
#   added: <NAME>                     one per key written as a placeholder
#   kept: <NAME>                      one per declared key already present
#   alternative: <NAME> or <login>    one per variable a login replaces
#   none: no variable declared        nothing to do; no file created
#
# Exit codes:
#   0 — done
#   1 — refused: the file is not a JSON object whose `env`, when present, is an
#       object; nothing is written and nothing from the file is printed
#   2 — usage error, or the declarations file does not exist

set -uo pipefail

usage() {
  echo "usage: write-credential-placeholders.sh <declarations> [--file <path>]" >&2
  exit 2
}

[[ $# -ge 1 ]] || usage
DECL="$1"; shift
FILE=".claude/settings.local.json"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --file) [[ $# -ge 2 ]] || usage; FILE="$2"; shift 2 ;;
    *) usage ;;
  esac
done
[[ -f "$DECL" ]] || usage

NAMES=() SOURCES=() REPORT=""
seen=" "
while IFS=$'\t' read -r kind _pack name rest; do
  case "$kind" in
    env)
      [[ "$seen" == *" $name "* ]] && continue
      seen+="$name "; NAMES+=("$name"); SOURCES+=("$rest") ;;
    login)
      REPORT+="alternative: $name or $rest"$'\n' ;;
  esac
done < "$DECL"

if (( ${#NAMES[@]} == 0 )); then
  printf '%snone: no variable declared\n' "$REPORT"
  exit 0
fi

if [[ -e "$FILE" ]]; then
  # Shape only; jq's own messages can quote the file, so they are discarded.
  if ! jq -e 'type == "object" and ((.env // {}) | type == "object")' "$FILE" >/dev/null 2>&1; then
    echo "refused: $FILE is not a JSON object whose env is an object — fix it by hand, then run setup again"
    exit 1
  fi
fi

ADD_ARGS=() ADDED="" KEPT=""
for i in "${!NAMES[@]}"; do
  name="${NAMES[$i]}"
  if [[ -e "$FILE" ]] && jq -e --arg k "$name" '(.env // {}) | has($k)' "$FILE" >/dev/null 2>&1; then
    KEPT+="kept: $name"$'\n'
  else
    ADD_ARGS+=("$name" "FILL-IN: ${SOURCES[$i]}")
    ADDED+="added: $name"$'\n'
  fi
done

if (( ${#ADD_ARGS[@]} == 0 )); then
  printf 'unchanged: %s\n%s%s' "$FILE" "$KEPT" "$REPORT"
  exit 0
fi

# The keys to add, as one object built from argument pairs.
ADD=$(jq -n '[$ARGS.positional as $a | range(0; $a | length; 2) | {key: $a[.], value: $a[. + 1]}] | from_entries' \
  --args "${ADD_ARGS[@]}")

if [[ -e "$FILE" ]]; then
  TMP="$(mktemp "${FILE}.XXXXXX")" || { echo "refused: cannot write beside $FILE"; exit 1; }
  # The copy holds the file's values; it must not outlive this script.
  trap 'rm -f "$TMP"' EXIT
  if ! jq --argjson add "$ADD" '.env = ((.env // {}) + $add)' "$FILE" > "$TMP" 2>/dev/null; then
    rm -f "$TMP"; echo "refused: $FILE could not be merged"; exit 1
  fi
  # Copy into the existing file so its mode and owner stay as they are.
  cat "$TMP" > "$FILE"; rm -f "$TMP"
  STATE="updated"
else
  mkdir -p "$(dirname "$FILE")"
  ( umask 077; jq -n --argjson add "$ADD" '{env: $add}' > "$FILE" )
  STATE="created"
fi

printf '%s: %s\n%s%s%s' "$STATE" "$FILE" "$ADDED" "$KEPT" "$REPORT"
exit 0
