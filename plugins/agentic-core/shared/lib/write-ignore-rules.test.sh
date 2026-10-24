#!/usr/bin/env bash
# Tests for write-ignore-rules.sh. Run with:
#   bash plugins/agentic-core/shared/lib/write-ignore-rules.test.sh
#
# No framework — exits 0 on success, 1 on any failure.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRITE="$SCRIPT_DIR/write-ignore-rules.sh"

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

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    PASS=$((PASS + 1)); echo "  ok: $desc"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: $desc"; echo "    expected to contain: $needle"; echo "    got: $haystack"
  fi
}

assert_not_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    PASS=$((PASS + 1)); echo "  ok: $desc"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: $desc"; echo "    must not contain: $needle"; echo "    got: $haystack"
  fi
}

[[ -n "${TMPDIR:-}" ]] || { echo "TMPDIR is empty; refusing to create test directories" >&2; exit 1; }
WORK="$(mktemp -d "$TMPDIR/write-ignore-rules-test.XXXXXX")" || exit 1
trap 'rm -rf "$WORK"' EXIT

# No global or system ignore file may answer for the fixture.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 XDG_CONFIG_HOME="$WORK/xdg"

T=$'\t'
DECL="$WORK/declarations.txt"
{
  echo "host${T}example-scm${T}api.example-scm.test"
  echo "ignore${T}example-platform${T}example-drafts/"
  echo "ignore${T}example-tracker${T}.ai/example-tracker/"
  echo "ignore${T}core${T}.claude/settings.local.json"
  echo "ignore${T}core${T}.ai/run-context/"
  echo "ignore${T}core${T}.ai/run-state.json"
  echo "ignore${T}example-scm${T}.ai/run-context/"
  echo "commit${T}core${T}.ai/project-config.yaml"
  echo "commit${T}core${T}.ai/specs/"
} > "$DECL"

new_repo() {
  local d="$WORK/$1"
  mkdir -p "$d" && git -C "$d" init -q && echo "$d"
}

echo "[create] no ignore file → one block holding every path, each once"
R=$(new_repo a)
OUT=$(cd "$R" && bash "$WRITE" "$DECL" 2>&1); ST=$?
assert_eq "exit 0" 0 "$ST"
assert_contains "reports the file created" "created: .gitignore" "$OUT"
assert_contains "names a path added" "added: example-drafts/" "$OUT"
assert_contains "names the credentials file added" "added: .claude/settings.local.json" "$OUT"
assert_eq "a path two packs declare is written once" 1 "$(grep -cxF '.ai/run-context/' "$R/.gitignore")"
assert_eq "one marked block" 1 "$(grep -c '^# Written by setup' "$R/.gitignore")"
for p in example-drafts/ .ai/example-tracker/ .claude/settings.local.json .ai/run-context/ .ai/run-state.json; do
  (cd "$R" && git check-ignore -q --no-index -- "$p"); assert_eq "git now ignores $p" 0 $?
done
for p in .ai/project-config.yaml .ai/specs/; do
  (cd "$R" && git check-ignore -q --no-index -- "$p"); assert_eq "git does not ignore the committed $p" 1 $?
done

echo "[re-run] nothing missing → the file is not rewritten"
cp "$R/.gitignore" "$WORK/before"
OUT=$(cd "$R" && bash "$WRITE" "$DECL" 2>&1); ST=$?
assert_eq "exit 0" 0 "$ST"
assert_contains "reports unchanged" "unchanged: .gitignore" "$OUT"
assert_contains "names a path present" "present: example-drafts/" "$OUT"
cmp -s "$R/.gitignore" "$WORK/before"; assert_eq "byte-identical" 0 $?

echo "[merge] a broader rule already covers a path; existing lines are kept; no trailing newline handled"
R=$(new_repo b)
printf 'node_modules/\n.ai/run-context\n*.json' > "$R/.gitignore"
cp "$R/.gitignore" "$WORK/b.before"
OUT=$(cd "$R" && bash "$WRITE" "$DECL" 2>&1); ST=$?
assert_eq "exit 0" 0 "$ST"
assert_contains "reports updated" "updated: .gitignore" "$OUT"
assert_contains "a path a broader rule covers is present" "present: .ai/run-context/" "$OUT"
assert_contains "a file a glob covers is present" "present: .claude/settings.local.json" "$OUT"
assert_not_contains "never re-adds a covered path" "added: .ai/run-state.json" "$OUT"
assert_eq "the old content is the file's untouched start" "$(cat "$WORK/b.before")" "$(head -c "$(wc -c < "$WORK/b.before")" "$R/.gitignore")"
assert_eq "the last old line kept intact" 1 "$(grep -cxF '*.json' "$R/.gitignore")"
(cd "$R" && git check-ignore -q --no-index -- example-drafts/); assert_eq "git now ignores example-drafts/" 0 $?

echo "[conflict] a committed path an existing rule ignores is reported; the rule stays"
R=$(new_repo c)
printf '.ai/\n' > "$R/.gitignore"
OUT=$(cd "$R" && bash "$WRITE" "$DECL" 2>&1); ST=$?
assert_eq "exit 3" 3 "$ST"
assert_contains "names the path and the rule" "conflict: .ai/project-config.yaml — ignored by .gitignore:1:.ai/" "$OUT"
assert_eq "the rule is still there" 1 "$(grep -cxF '.ai/' "$R/.gitignore")"
assert_contains "the paths not covered are still written" "added: example-drafts/" "$OUT"

echo "[refused] outside a git work tree"
mkdir -p "$WORK/not-a-repo"
OUT=$(cd "$WORK/not-a-repo" && bash "$WRITE" "$DECL" 2>&1); ST=$?
assert_eq "exit 1" 1 "$ST"
assert_contains "says why" "refused:" "$OUT"
[[ ! -e "$WORK/not-a-repo/.gitignore" ]]; assert_eq "no file written" 0 $?

echo "[usage]"
bash "$WRITE" >/dev/null 2>&1; ST=$?
assert_eq "no argument: exit 2" 2 "$ST"

echo "=== $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]]
