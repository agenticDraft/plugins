#!/usr/bin/env bash
# Tests for name-files-to-commit.sh. Run with:
#   bash plugins/agentic-core/shared/lib/name-files-to-commit.test.sh
#
# No framework — exits 0 on success, 1 on any failure.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAME="$SCRIPT_DIR/name-files-to-commit.sh"

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
WORK="$(mktemp -d "$TMPDIR/name-files-to-commit-test.XXXXXX")" || exit 1
trap 'rm -rf "$WORK"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 XDG_CONFIG_HOME="$WORK/xdg"

T=$'\t'
DECL="$WORK/declarations.txt"
{
  echo "ignore${T}core${T}.claude/settings.local.json"
  echo "commit${T}core${T}.ai/project-config.yaml"
  echo "commit${T}core${T}.ai/project-conventions.yaml"
  echo "commit${T}core${T}.ai/specs/"
} > "$DECL"

R="$WORK/repo"
mkdir -p "$R" && git -C "$R" init -q
git -C "$R" -c user.name=t -c user.email=t@example.test commit -q --allow-empty -m init

echo "[name] changed or new committed files, plus the two settings files setup edits — nothing else"
mkdir -p "$R/.ai/specs/ITEM-1" "$R/.claude"
echo "version: 1" > "$R/.ai/project-config.yaml"
echo "draft" > "$R/.ai/specs/ITEM-1/draft.md"
printf '.claude/settings.local.json\n' > "$R/.gitignore"
echo '{}' > "$R/.claude/settings.json"
echo '{}' > "$R/.claude/settings.local.json"
echo "unrelated" > "$R/unrelated.txt"
OUT=$(cd "$R" && bash "$NAME" "$DECL" 2>&1); ST=$?
assert_eq "exit 0" 0 "$ST"
assert_eq "the list, in a fixed order" "commit: .ai/project-config.yaml
commit: .ai/specs/
commit: .gitignore
commit: .claude/settings.json" "$OUT"

echo "[name] once committed, nothing is named"
git -C "$R" add .ai .gitignore .claude/settings.json
git -C "$R" -c user.name=t -c user.email=t@example.test commit -q -m setup
OUT=$(cd "$R" && bash "$NAME" "$DECL" 2>&1); ST=$?
assert_eq "exit 0" 0 "$ST"
assert_eq "says so" "none: every file setup wrote is committed" "$OUT"

echo "[refused] outside a git work tree"
mkdir -p "$WORK/plain"
OUT=$(cd "$WORK/plain" && bash "$NAME" "$DECL" 2>&1); ST=$?
assert_eq "exit 1" 1 "$ST"

echo "[usage]"
bash "$NAME" >/dev/null 2>&1; ST=$?
assert_eq "no argument: exit 2" 2 "$ST"

echo "=== $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]]
