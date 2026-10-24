#!/usr/bin/env bash
# derive-project-values.sh — Runs the configured platform pack's declared
# derivation script (`config_derivation:` in its pack.yaml, see
# shared/pack-manifest.md) and passes on only the lines a project config may
# take from it. Deterministic, no model involved. The core never learns what
# the pack derives or how.
#
# Usage:
#   derive-project-values.sh <platform-pack-root> --remote <remote URL>
#
# The script is run as `<script> --remote <remote URL>`. Every line it prints
# must be one of:
#   branch_name.max_length=<positive int>
#   platform.<snake_case key>=<value without a double quote>
# One line of any other shape, a non-zero exit, or no line at all refuses the
# whole output: nothing is printed on stdout.
#
# Exit codes:
#   0 — the derived lines on stdout
#   1 — refused; the reason (and the script's own stderr) on stderr
#   2 — usage error: no root, no pack.yaml, no or empty --remote
#   3 — "not-declared: …" on stdout; the pack declares no derivation

set -uo pipefail

usage() {
  echo "usage: derive-project-values.sh <platform-pack-root> --remote <remote URL>" >&2
  exit 2
}

ROOT="${1:-}"
[[ -n "$ROOT" ]] || usage
shift
REMOTE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --remote) [[ $# -ge 2 ]] || usage; REMOTE="$2"; shift 2 ;;
    *) usage ;;
  esac
done
[[ -n "$REMOTE" ]] || usage
[[ -f "$ROOT/pack.yaml" ]] || { echo "no pack.yaml under $ROOT" >&2; exit 2; }

DECLARED=$(awk '/^config_derivation:/ { sub(/^config_derivation:[[:space:]]*/, ""); gsub(/"/, ""); print; exit }' "$ROOT/pack.yaml")
if [[ -z "$DECLARED" ]]; then
  echo "not-declared: the platform pack declares no config_derivation"
  exit 3
fi
SCRIPT="$ROOT/$DECLARED"
[[ -f "$SCRIPT" ]] || { echo "refused: config_derivation names a script that does not exist: $DECLARED" >&2; exit 1; }

ERR_FILE="$(mktemp "${TMPDIR:-/tmp}/derive-project-values.XXXXXX")" || { echo "refused: cannot create a temp file" >&2; exit 1; }
trap 'rm -f "$ERR_FILE"' EXIT

OUT=$(bash "$SCRIPT" --remote "$REMOTE" 2>"$ERR_FILE"); rc=$?
if (( rc != 0 )); then
  cat "$ERR_FILE" >&2
  echo "refused: the derivation script exited $rc" >&2
  exit 1
fi

count=0
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  if [[ ! "$line" =~ ^branch_name\.max_length=[1-9][0-9]*$ && ! "$line" =~ ^platform\.[a-z_][a-z0-9_]*=[^\"]+$ ]]; then
    echo "refused: a derived line is not 'branch_name.max_length=<positive int>' or 'platform.<key>=<value>': '$line'" >&2
    exit 1
  fi
  count=$((count + 1))
done <<< "$OUT"
(( count > 0 )) || { echo "refused: the derivation script printed nothing" >&2; exit 1; }

printf '%s\n' "$OUT" | grep -v '^$'
exit 0
