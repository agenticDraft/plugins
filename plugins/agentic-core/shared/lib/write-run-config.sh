#!/usr/bin/env bash
# write-run-config.sh — Mechanical merge of the last four sections of a project
# config — `limits`, `trigger`, `branch_name`, `platform` (see
# shared/project-config.md) — after the `paths:` block. No judgment involved:
# the caller has confirmed the values with a human; this script only places
# them in the fixed shape.
#
# Usage:
#   write-run-config.sh <config-path> [--questions <n>] [--fix-attempts <n>]
#                       [--token <token>] [--derived <file>] [--dry-run]
#
# Values, first one found wins:
#   limits, token — the flag, then the value already in the file, then the
#                   default (3, 3, "@agentic-run").
#   allowed_identities — the entries already in the file, carried forward and
#                   never printed; none → one placeholder for the human to fill
#                   (shared/personal-values.md). This script never writes an
#                   identity itself.
#   branch_name.max_length, platform.<key> — the --derived file's lines, then
#                   the values already in the file. A platform key the derived
#                   file does not name is kept.
#
# The --derived file holds one `<key>=<value>` line per derived value, as
# derive-project-values.sh prints them: `branch_name.max_length=<positive int>`
# or `platform.<snake_case key>=<value>`. Any other line refuses the whole
# file and nothing is written.
#
# --dry-run prints the four sections as they would be written, a kept identity
# shown only as a count, and writes nothing.
#
# The file must already hold a `paths:` block; everything after it must be one
# of the four sections above, or the file is refused rather than rewritten.
#
# Exit codes:
#   0 — "updated: <path>" (or the dry-run text) on stdout
#   1 — contract violation: a bad flag value, a malformed derived line, no
#       `paths:` block, or trailing content this script does not own
#   2 — usage error: no config path, a missing file, an unknown flag

set -uo pipefail

PLACEHOLDER="FILL-IN: tracker identity of a person allowed to trigger a run"

usage() {
  echo "usage: write-run-config.sh <config-path> [--questions <n>] [--fix-attempts <n>] [--token <token>] [--derived <file>] [--dry-run]" >&2
  exit 2
}

fail() {
  echo "invalid: $1" >&2
  exit 1
}

CONFIG_PATH="${1:-}"
[[ -n "$CONFIG_PATH" ]] || usage
shift
[[ -f "$CONFIG_PATH" ]] || { echo "not found: $CONFIG_PATH" >&2; exit 2; }

FLAG_QUESTIONS=""
FLAG_FIX=""
FLAG_TOKEN=""
TOKEN_GIVEN=0
DERIVED=""
DRY_RUN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --questions)    [[ $# -ge 2 ]] || usage; FLAG_QUESTIONS="$2"; shift 2 ;;
    --fix-attempts) [[ $# -ge 2 ]] || usage; FLAG_FIX="$2"; shift 2 ;;
    --token)        [[ $# -ge 2 ]] || usage; FLAG_TOKEN="$2"; TOKEN_GIVEN=1; shift 2 ;;
    --derived)      [[ $# -ge 2 ]] || usage; DERIVED="$2"; shift 2 ;;
    --dry-run)      DRY_RUN=1; shift ;;
    *) usage ;;
  esac
done
[[ -z "$DERIVED" || -f "$DERIVED" ]] || { echo "not found: $DERIVED" >&2; exit 2; }

for pair in "questions:$FLAG_QUESTIONS" "fix-attempts:$FLAG_FIX"; do
  value="${pair#*:}"
  [[ -z "$value" || "$value" =~ ^[0-9]+$ ]] || fail "--${pair%%:*} must be a non-negative integer"
done
if (( TOKEN_GIVEN )); then
  [[ -n "$FLAG_TOKEN" ]] || fail "--token is empty"
  [[ "$FLAG_TOKEN" != *'"'* ]] || fail "--token contains a double quote"
fi

# --- read the file: the head up to and including paths:, then the owned tail
LINES=()
while IFS= read -r line || [[ -n "$line" ]]; do
  LINES+=("$line")
done < "$CONFIG_PATH"
n=${#LINES[@]}

paths_idx=-1
tail_idx=$n
for ((i = 0; i < n; i++)); do
  [[ "${LINES[i]}" == "paths:" ]] && paths_idx=$i
  if [[ "${LINES[i]}" =~ ^(limits|trigger|branch_name|platform):$ ]]; then
    tail_idx=$i
    break
  fi
done
(( paths_idx >= 0 )) || fail "no 'paths:' block before the sections this script writes"

CUR_QUESTIONS=""
CUR_FIX=""
CUR_TOKEN=""
CUR_MAX=""
IDENTITIES=()
PLAT_KEYS=()
PLAT_VALUES=()

section=""
for ((i = tail_idx; i < n; i++)); do
  line="${LINES[i]}"
  [[ -z "${line//[[:space:]]/}" ]] && continue
  if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_-]*):$ ]]; then
    section="${BASH_REMATCH[1]}"
    case "$section" in
      limits|trigger|branch_name|platform) continue ;;
      *) fail "unknown top-level key after paths: '$section'" ;;
    esac
  fi
  case "$section" in
    limits)
      if [[ "$line" =~ ^\ \ questions_per_run:\ ([0-9]+)$ ]]; then CUR_QUESTIONS="${BASH_REMATCH[1]}"
      elif [[ "$line" =~ ^\ \ fix_attempts_default:\ ([0-9]+)$ ]]; then CUR_FIX="${BASH_REMATCH[1]}"
      else fail "unexpected line in limits at line $((i + 1))"; fi ;;
    trigger)
      if [[ "$line" =~ ^\ \ token:\ \"(.*)\"$ ]]; then CUR_TOKEN="${BASH_REMATCH[1]}"
      elif [[ "$line" == "  allowed_identities:" ]]; then :
      elif [[ "$line" =~ ^\ \ \ \ -\ \".*\"$ ]]; then IDENTITIES+=("$line")
      else fail "unexpected line in trigger at line $((i + 1))"; fi ;;
    branch_name)
      if [[ "$line" =~ ^\ \ max_length:\ ([1-9][0-9]*)$ ]]; then CUR_MAX="${BASH_REMATCH[1]}"
      else fail "unexpected line in branch_name at line $((i + 1))"; fi ;;
    platform)
      if [[ "$line" =~ ^\ \ ([a-z_][a-z0-9_]*):\ (.*)$ ]]; then
        PLAT_KEYS+=("${BASH_REMATCH[1]}"); PLAT_VALUES+=("${BASH_REMATCH[2]}")
      else fail "unexpected line in platform at line $((i + 1))"; fi ;;
    *) fail "unexpected content after paths: at line $((i + 1))" ;;
  esac
done

# A placeholder entry is not an identity to keep: it is written again below.
KEPT=()
for entry in ${IDENTITIES[@]+"${IDENTITIES[@]}"}; do
  [[ "$entry" == *"FILL-IN:"* ]] || KEPT+=("$entry")
done

# --- derived values -----------------------------------------------------------
set_platform() {
  local key="$1" value="$2" j
  for ((j = 0; j < ${#PLAT_KEYS[@]}; j++)); do
    if [[ "${PLAT_KEYS[j]}" == "$key" ]]; then PLAT_VALUES[j]="$value"; return; fi
  done
  PLAT_KEYS+=("$key"); PLAT_VALUES+=("$value")
}

DERIVED_MAX=""
D_KEYS=()
D_VALUES=()
if [[ -n "$DERIVED" ]]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" ]] && continue
    if [[ "$line" =~ ^branch_name\.max_length=([1-9][0-9]*)$ ]]; then
      DERIVED_MAX="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^platform\.([a-z_][a-z0-9_]*)=([^\"]+)$ ]]; then
      D_KEYS+=("${BASH_REMATCH[1]}"); D_VALUES+=("${BASH_REMATCH[2]}")
    else
      fail "derived line is not 'branch_name.max_length=<positive int>' or 'platform.<key>=<value>': '$line'"
    fi
  done < "$DERIVED"
fi
for ((j = 0; j < ${#D_KEYS[@]}; j++)); do
  set_platform "${D_KEYS[j]}" "\"${D_VALUES[j]}\""
done

QUESTIONS="${FLAG_QUESTIONS:-${CUR_QUESTIONS:-3}}"
FIX="${FLAG_FIX:-${CUR_FIX:-3}}"
if (( TOKEN_GIVEN )); then TOKEN="$FLAG_TOKEN"; else TOKEN="${CUR_TOKEN:-@agentic-run}"; fi
MAX="${DERIVED_MAX:-$CUR_MAX}"

# --- render -------------------------------------------------------------------
# render <show-identities: 1|0>
render() {
  echo "limits:"
  echo "  questions_per_run: $QUESTIONS"
  echo "  fix_attempts_default: $FIX"
  echo
  echo "trigger:"
  echo "  token: \"$TOKEN\""
  echo "  allowed_identities:"
  if (( ${#KEPT[@]} == 0 )); then
    echo "    - \"$PLACEHOLDER\""
  elif (( $1 )); then
    printf '%s\n' "${KEPT[@]}"
  else
    local word="identities"
    (( ${#KEPT[@]} == 1 )) && word="identity"
    echo "    - <${#KEPT[@]} $word kept, not shown>"
  fi
  if [[ -n "$MAX" ]]; then
    echo
    echo "branch_name:"
    echo "  max_length: $MAX"
  fi
  if (( ${#PLAT_KEYS[@]} > 0 )); then
    echo
    echo "platform:"
    for ((j = 0; j < ${#PLAT_KEYS[@]}; j++)); do
      echo "  ${PLAT_KEYS[j]}: ${PLAT_VALUES[j]}"
    done
  fi
}

if (( DRY_RUN )); then
  render 0
  exit 0
fi

# The head, without the blank lines that separated it from the old tail.
last=$((tail_idx - 1))
while (( last >= 0 )) && [[ -z "${LINES[last]//[[:space:]]/}" ]]; do last=$((last - 1)); done
{
  for ((i = 0; i <= last; i++)); do printf '%s\n' "${LINES[i]}"; done
  echo
  render 1
} > "$CONFIG_PATH.tmp" && mv "$CONFIG_PATH.tmp" "$CONFIG_PATH"
echo "updated: $CONFIG_PATH"
exit 0
