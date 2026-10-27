#!/usr/bin/env bash
# Tests for register-source-tree.sh's in_source_tree. Run with:
#   bash plugins/agentic-core/shared/lib/register-source-tree.test.sh
#
# Builds the layouts a copy of the core can sit in and sources the helper from
# each. No framework — exits 0 on success, 1 on any failure.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="$SCRIPT_DIR/register-source-tree.sh"

PASS=0
FAIL=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    PASS=$((PASS + 1)); echo "  ok: $desc"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: $desc"; echo "    expected: $expected"; echo "    got:      $actual"
  fi
}

[[ -n "${TMPDIR:-}" ]] || { echo "TMPDIR is empty; refusing to create test directories" >&2; exit 1; }
WORK="$(mktemp -d "$TMPDIR/register-source-tree-test.XXXXXX")" || exit 1
[[ -n "$WORK" && -d "$WORK" ]] || { echo "cannot create a temp dir" >&2; exit 1; }
trap 'rm -rf "$WORK"' EXIT

# core_copy <plugin folder> <plugin.json name> — the helper at <folder>/shared/lib.
core_copy() {
  mkdir -p "$1/shared/lib" "$1/.claude-plugin"
  cp "$HELPER" "$1/shared/lib/"
  printf '{\n  "name": "%s",\n  "version": "0.0.1"\n}\n' "$2" > "$1/.claude-plugin/plugin.json"
}

# verdict <path to the helper> — 0 or 1, as in_source_tree returns it there.
verdict() {
  bash -c '. "$1"; in_source_tree; echo $?' _ "$1"
}

echo "=== in_source_tree tests ==="

echo "[source tree] the core in a folder named as its plugin.json"
core_copy "$WORK/src/plugins/example-core" example-core
assert_eq "returns 0" "0" "$(verdict "$WORK/src/plugins/example-core/shared/lib/register-source-tree.sh")"

echo "[source tree] reached through a pack's link to the core"
mkdir -p "$WORK/src/plugins/example-pack"
ln -s ../example-core/shared "$WORK/src/plugins/example-pack/core"
assert_eq "returns 0" "0" "$(verdict "$WORK/src/plugins/example-pack/core/lib/register-source-tree.sh")"

echo "[installed] the core in a version-named folder"
core_copy "$WORK/cache/example-core/0.0.1" example-core
assert_eq "returns 1" "1" "$(verdict "$WORK/cache/example-core/0.0.1/shared/lib/register-source-tree.sh")"

echo "[installed] a pack's own copy of the core"
mkdir -p "$WORK/cache/example-pack/0.0.1/core/lib" "$WORK/cache/example-pack/0.0.1/.claude-plugin"
cp "$HELPER" "$WORK/cache/example-pack/0.0.1/core/lib/"
printf '{\n  "name": "example-pack"\n}\n' > "$WORK/cache/example-pack/0.0.1/.claude-plugin/plugin.json"
assert_eq "returns 1" "1" "$(verdict "$WORK/cache/example-pack/0.0.1/core/lib/register-source-tree.sh")"

echo "[no manifest] a shared/lib with no plugin.json above it"
mkdir -p "$WORK/bare/example-core/shared/lib"
cp "$HELPER" "$WORK/bare/example-core/shared/lib/"
assert_eq "returns 1" "1" "$(verdict "$WORK/bare/example-core/shared/lib/register-source-tree.sh")"

echo "[nested name] only the top-level name counts, not author.name"
core_copy "$WORK/nested/plugins/someone" example-core
printf '{\n  "name": "example-core",\n  "author": {\n    "name": "someone"\n  }\n}\n' \
  > "$WORK/nested/plugins/someone/.claude-plugin/plugin.json"
assert_eq "returns 1" "1" "$(verdict "$WORK/nested/plugins/someone/shared/lib/register-source-tree.sh")"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
