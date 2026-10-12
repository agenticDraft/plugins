#!/usr/bin/env bash
# Run: bash scripts/run-tests.sh [dir ...]
#
# Runs every *.test.sh with bash and every *.test.mjs with `node --test` under the given
# directories (default: plugins scripts), one file at a time, and prints
# `files=<n> fail=<n>`. Exits 0 only when no file failed. A file that cannot run (a missing
# dependency, a missing interpreter) counts as a failure; nothing is skipped.
# The runner's own dependencies come from `npm ci` in plugins/agentic-core/shared/runner.
set -uo pipefail

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" || exit 2
[ "$#" -gt 0 ] || set -- plugins scripts

files=0
fail=0
while IFS= read -r t; do
  files=$((files + 1))
  echo "::group::$t"
  case "$t" in
    *.test.sh)  bash "$t" ;;
    *.test.mjs) node --test "$t" ;;
  esac
  rc=$?
  echo "::endgroup::"
  if [ "$rc" -ne 0 ]; then
    fail=$((fail + 1))
    echo "::error file=$t::suite failed (exit $rc)"
  fi
done < <(find "$@" \( -name node_modules -prune \) -o -type f \( -name '*.test.sh' -o -name '*.test.mjs' \) -print | sort)

echo "files=$files fail=$fail"
[ "$files" -gt 0 ] && [ "$fail" -eq 0 ]
