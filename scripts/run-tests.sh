#!/usr/bin/env bash
# Run: bash scripts/run-tests.sh [dir ...]
#
# Runs every *.test.sh with bash and every *.test.mjs with `node --test` under the given
# directories (default: plugins scripts), one file at a time, and prints
# `files=<n> fail=<n> skipped=<n>`. Exits 0 only when no file failed. A file that cannot run (a
# missing dependency, a missing interpreter) counts as a failure. `skipped` counts the cases a
# suite reports as not run: a line starting `skipped:` in a `.test.sh` suite, the `skipped <n>`
# total of a `.test.mjs` suite. A skip does not fail the run; it is only counted.
# The runner's own dependencies come from `npm ci` in plugins/agentic-core/shared/runner.
set -uo pipefail

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" || exit 2

# Suites refuse to create test directories when TMPDIR is empty; a CI image leaves it unset.
export TMPDIR="${TMPDIR:-${RUNNER_TEMP:-/tmp}}"
[ "$#" -gt 0 ] || set -- plugins scripts

OUT_FILE="$(mktemp "${TMPDIR}/run-tests.XXXXXX")" || { echo "cannot create a temp file" >&2; exit 2; }
trap 'rm -f "$OUT_FILE"' EXIT

files=0
fail=0
skipped=0
while IFS= read -r t; do
  files=$((files + 1))
  echo "::group::$t"
  case "$t" in
    *.test.sh)  bash "$t" 2>&1 | tee "$OUT_FILE" ;;
    *.test.mjs) node --test "$t" 2>&1 | tee "$OUT_FILE" ;;
  esac
  rc=${PIPESTATUS[0]}
  case "$t" in
    *.test.sh)  n=$(grep -cE '^[[:space:]]*skipped:' "$OUT_FILE") ;;
    *.test.mjs) n=$(awk 'NF == 3 && $2 == "skipped" && $3 ~ /^[0-9]+$/ { n += $3 } END { print n + 0 }' "$OUT_FILE") ;;
  esac
  skipped=$((skipped + ${n:-0}))
  echo "::endgroup::"
  if [ "$rc" -ne 0 ]; then
    fail=$((fail + 1))
    echo "::error file=$t::suite failed (exit $rc)"
  fi
done < <(find "$@" \( -name node_modules -prune \) -o -type f \( -name '*.test.sh' -o -name '*.test.mjs' \) -print | sort)

echo "files=$files fail=$fail skipped=$skipped"
[ "$files" -gt 0 ] && [ "$fail" -eq 0 ]
