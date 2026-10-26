#!/usr/bin/env bash
# Run: bash plugins/agentic-core/shared/lib/write-working-paths.sh <config> <out-file>
#
# write-working-paths.sh <config> <out-file> [--project-dir <dir>]
#
# Writes the run's working paths — every configured pack's `ignore_paths` and
# every `ignore` line of the core's run-paths.txt — to <out-file>, one per
# line, sorted, each once. These are the paths no change set includes and no
# commit carries (filter-working-paths.sh). The declarations come from
# collect-pack-declarations.sh, so only the packs the config names count. The
# file is replaced, never appended to. Deterministic, no model involved.
#
# Output (stdout): `written: <out-file> (<n> paths)`
#
# Exit codes:
#   0 — written
#   1 — refused: the collector refused (its reason on stdout); nothing written
#   2 — usage error

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() { echo "usage: write-working-paths.sh <config> <out-file> [--project-dir <dir>]" >&2; exit 2; }

[[ $# -ge 2 && -n "$1" && -n "$2" ]] || usage
CONFIG="$1"; OUT_FILE="$2"; shift 2
EXTRA=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-dir) [[ $# -ge 2 ]] || usage; EXTRA=(--project-dir "$2"); shift 2 ;;
    *) usage ;;
  esac
done

if ! DECL="$(bash "$SCRIPT_DIR/collect-pack-declarations.sh" "$CONFIG" ${EXTRA[@]+"${EXTRA[@]}"} 2>&1)"; then
  printf '%s\n' "$DECL"
  exit 1
fi

PATHS="$(printf '%s\n' "$DECL" | awk -F '\t' '$1 == "ignore" { print $3 }' | sort -u)"
mkdir -p "$(dirname "$OUT_FILE")"
printf '%s\n' "$PATHS" | grep . > "$OUT_FILE.tmp.$$"
mv "$OUT_FILE.tmp.$$" "$OUT_FILE"
echo "written: $OUT_FILE ($(grep -c . "$OUT_FILE") paths)"
exit 0
