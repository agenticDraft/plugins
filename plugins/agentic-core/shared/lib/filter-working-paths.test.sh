#!/usr/bin/env bash
# Tests for filter-working-paths.sh. Run with:
#   bash plugins/agentic-core/shared/lib/filter-working-paths.test.sh
#
# No framework — exits 0 on success, 1 on any failure.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILTER="$SCRIPT_DIR/filter-working-paths.sh"

PASS=0
FAIL=0
check() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    PASS=$((PASS + 1)); echo "  ok: $desc"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: $desc"; echo "    expected: $expected"; echo "    actual:   $actual"
  fi
}

[[ -n "${TMPDIR:-}" ]] || { echo "TMPDIR is empty; refusing to create test directories" >&2; exit 1; }
WORK="$(mktemp -d "$TMPDIR/filter-working-paths-test.XXXXXX")" || exit 1
[[ -n "$WORK" && -d "$WORK" ]] || { echo "cannot create a temp dir" >&2; exit 1; }
trap 'rm -rf "$WORK"' EXIT

printf '%s\n' 'example-drafts/' '.ai/example-tracker/' '.ai/run-state.json' > "$WORK/paths.txt"

INPUT='blocks/cards/cards.css
example-drafts/EX-1.plain.html
example-drafts/nested/EX-1.svg
example-drafts-other/keep.txt
.ai/example-tracker/fetch.json
.ai/run-state.json
.ai/run-state.json.bak
.ai/specs/EX-1/draft.md'

echo "=== filter-working-paths.sh tests ==="

echo "[filter] a directory entry drops everything under it; a file entry drops only itself"
OUT="$(printf '%s\n' "$INPUT" | bash "$FILTER" "$WORK/paths.txt")"; ST=$?
check "exit 0" 0 "$ST"
check "kept paths, in input order" 'blocks/cards/cards.css
example-drafts-other/keep.txt
.ai/run-state.json.bak
.ai/specs/EX-1/draft.md' "$OUT"

echo "[missing] no file excludes nothing"
OUT="$(printf '%s\n' "$INPUT" | bash "$FILTER" "$WORK/absent.txt")"; ST=$?
check "exit 0" 0 "$ST"
check "every path kept" "$INPUT" "$OUT"

echo "[comments] blank and # lines in the file are not entries"
printf '%s\n' '# working paths' '' 'example-drafts/' > "$WORK/commented.txt"
OUT="$(printf '%s\n' '# not a path' 'example-drafts/a' 'keep' | bash "$FILTER" "$WORK/commented.txt")"
check "only the declared entry drops" '# not a path
keep' "$OUT"

echo "[empty input] nothing in, nothing out"
OUT="$(printf '' | bash "$FILTER" "$WORK/paths.txt")"; ST=$?
check "exit 0" 0 "$ST"
check "no output" "" "$OUT"

echo "[usage] no argument"
bash "$FILTER" < /dev/null >/dev/null 2>&1; ST=$?
check "exit 2" 2 "$ST"

echo ""
echo "passed: $PASS, failed: $FAIL"
[[ "$FAIL" -eq 0 ]]
