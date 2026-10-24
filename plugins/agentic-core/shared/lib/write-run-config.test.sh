#!/usr/bin/env bash
# Tests for write-run-config.sh. Run with:
#   bash plugins/agentic-core/shared/lib/write-run-config.test.sh
#
# No framework — exits 0 on success, 1 on any failure.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRITER="$SCRIPT_DIR/write-run-config.sh"
VALIDATE="$SCRIPT_DIR/validate-project-config.sh"
FIND="$SCRIPT_DIR/find-placeholders.sh"

PASS=0
FAIL=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    PASS=$((PASS + 1)); echo "  ok: $desc"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: $desc"; echo "    --- expected ---"; echo "$expected"; echo "    --- got ---"; echo "$actual"
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
WORK="$(mktemp -d "$TMPDIR/write-run-config-test.XXXXXX")" || exit 1
trap 'rm -rf "$WORK"' EXIT

HEAD='version: 1

packs:
  platform: example-platform
  tracker: example-tracker
  scm: example-scm
  design: none
  browser: example-browser

commands:
  lint: "run-lint"
  test: ""
  build: ""
  serve: "run-serve"

paths:
  spec_dir: ".ai/specs"
  preview: "http://localhost:0000/preview"'

PH='FILL-IN: tracker identity of a person allowed to trigger a run'

echo "=== write-run-config.sh tests ==="

echo "[fresh] defaults, a placeholder identity, no derived keys"
CFG="$WORK/fresh.yaml"
printf '%s\n' "$HEAD" > "$CFG"
OUT=$(bash "$WRITER" "$CFG" 2>&1); ST=$?
assert_eq "exit 0" "0" "$ST"
assert_contains "reports updated" "updated: $CFG" "$OUT"
EXPECTED="$HEAD

limits:
  questions_per_run: 3
  fix_attempts_default: 3

trigger:
  token: \"@agentic-run\"
  allowed_identities:
    - \"$PH\""
assert_eq "file shape" "$EXPECTED" "$(cat "$CFG")"
OUT=$(bash "$FIND" "$CFG"); ST=$?
assert_eq "the placeholder is found" "1" "$ST"
assert_contains "on the identity line" "fresh.yaml:27:" "$OUT"
OUT=$(bash "$VALIDATE" "$CFG" 2>&1); ST=$?
assert_eq "shape-only validator passes a placeholder (why the grep runs first)" "0" "$ST"

echo "[derived] branch_name and platform blocks from a derived file"
printf 'branch_name.max_length=22\nplatform.preview_host_suffix=--repo--owner\n' > "$WORK/derived.txt"
OUT=$(bash "$WRITER" "$CFG" --derived "$WORK/derived.txt" 2>&1); ST=$?
assert_eq "exit 0" "0" "$ST"
EXPECTED_TAIL='branch_name:
  max_length: 22

platform:
  preview_host_suffix: "--repo--owner"'
assert_contains "branch_name and platform written last, in order" "$EXPECTED_TAIL" "$(cat "$CFG")"
OUT=$(bash "$VALIDATE" "$CFG" 2>&1); ST=$?
assert_eq "validator passes" "0" "$ST"

echo "[re-run] a filled identity, chosen limits and token and a hand-added platform key survive"
sed -i.bak "s/$PH/filled-identity-0000/" "$CFG" && rm -f "$CFG.bak"
sed -i.bak 's/questions_per_run: 3/questions_per_run: 5/; s/@agentic-run/@my-run/' "$CFG" && rm -f "$CFG.bak"
printf '  content_source: "https://example.invalid/content"\n' >> "$CFG"
printf 'branch_name.max_length=30\nplatform.preview_host_suffix=--other--owner\n' > "$WORK/derived2.txt"
OUT=$(bash "$WRITER" "$CFG" --derived "$WORK/derived2.txt" 2>&1); ST=$?
assert_eq "exit 0" "0" "$ST"
assert_not_contains "the identity is never printed" "filled-identity" "$OUT"
BODY="$(cat "$CFG")"
assert_contains "identity carried forward" '    - "filled-identity-0000"' "$BODY"
assert_not_contains "no placeholder re-added" "FILL-IN" "$BODY"
assert_contains "chosen questions_per_run kept" "questions_per_run: 5" "$BODY"
assert_contains "chosen token kept" 'token: "@my-run"' "$BODY"
assert_contains "derived max_length replaced" "max_length: 30" "$BODY"
assert_contains "derived suffix replaced" 'preview_host_suffix: "--other--owner"' "$BODY"
assert_contains "hand-added platform key kept" 'content_source: "https://example.invalid/content"' "$BODY"
assert_eq "one limits block" "1" "$(grep -c '^limits:' "$CFG")"
assert_eq "one platform block" "1" "$(grep -c '^platform:' "$CFG")"
OUT=$(bash "$VALIDATE" "$CFG" 2>&1); ST=$?
assert_eq "validator passes" "0" "$ST"

echo "[flags] explicit values win over the file"
OUT=$(bash "$WRITER" "$CFG" --questions 2 --fix-attempts 4 --token "@go" 2>&1); ST=$?
assert_eq "exit 0" "0" "$ST"
BODY="$(cat "$CFG")"
assert_contains "questions flag" "questions_per_run: 2" "$BODY"
assert_contains "fix-attempts flag" "fix_attempts_default: 4" "$BODY"
assert_contains "token flag" 'token: "@go"' "$BODY"
assert_contains "no --derived keeps the derived keys already there" "max_length: 30" "$BODY"

echo "[dry-run] shows the blocks, writes nothing, hides kept identities"
BEFORE="$(cat "$CFG")"
OUT=$(bash "$WRITER" "$CFG" --dry-run 2>&1); ST=$?
assert_eq "exit 0" "0" "$ST"
assert_eq "file unchanged" "$BEFORE" "$(cat "$CFG")"
assert_contains "shows limits" "questions_per_run: 2" "$OUT"
assert_contains "shows the identity count, not the identity" "1 identity kept, not shown" "$OUT"
assert_not_contains "never prints the identity" "filled-identity" "$OUT"
FRESH2="$WORK/fresh2.yaml"; printf '%s\n' "$HEAD" > "$FRESH2"
OUT=$(bash "$WRITER" "$FRESH2" --dry-run 2>&1)
assert_contains "dry-run on a fresh file shows the placeholder" "$PH" "$OUT"

echo "[reject] malformed derived lines; the file is left as it was"
BEFORE="$(cat "$CFG")"
for bad in 'branch_name.max_length=0' 'branch_name.max_length=abc' 'commands.lint=rm' 'platform.Bad-Key=x' \
           'platform.key=has"quote' 'no-equals-sign' 'branch_name.other=1'; do
  printf '%s\n' "$bad" > "$WORK/bad.txt"
  OUT=$(bash "$WRITER" "$CFG" --derived "$WORK/bad.txt" 2>&1); ST=$?
  assert_eq "'$bad' → exit 1" "1" "$ST"
done
assert_eq "file untouched by every rejection" "$BEFORE" "$(cat "$CFG")"

echo "[reject] bad flag values; a file with no paths: block; unknown trailing content"
OUT=$(bash "$WRITER" "$CFG" --questions -1 2>&1); ST=$?
assert_eq "negative questions → exit 1" "1" "$ST"
OUT=$(bash "$WRITER" "$CFG" --token "" 2>&1); ST=$?
assert_eq "empty token → exit 1" "1" "$ST"
OUT=$(bash "$WRITER" "$CFG" --token 'a"b' 2>&1); ST=$?
assert_eq "quoted token → exit 1" "1" "$ST"
printf 'version: 1\n' > "$WORK/nopaths.yaml"
OUT=$(bash "$WRITER" "$WORK/nopaths.yaml" 2>&1); ST=$?
assert_eq "no paths: block → exit 1" "1" "$ST"
printf '%s\n\nlimits:\n  questions_per_run: 3\n  fix_attempts_default: 3\n\nsurprise:\n  x: 1\n' "$HEAD" > "$WORK/unknown.yaml"
BEFORE="$(cat "$WORK/unknown.yaml")"
OUT=$(bash "$WRITER" "$WORK/unknown.yaml" 2>&1); ST=$?
assert_eq "unknown trailing key → exit 1, never dropped" "1" "$ST"
assert_eq "file untouched" "$BEFORE" "$(cat "$WORK/unknown.yaml")"

echo "[usage]"
OUT=$(bash "$WRITER" 2>&1); ST=$?
assert_eq "no argument → exit 2" "2" "$ST"
OUT=$(bash "$WRITER" "$WORK/absent.yaml" 2>&1); ST=$?
assert_eq "missing config → exit 2" "2" "$ST"
OUT=$(bash "$WRITER" "$CFG" --derived "$WORK/absent.txt" 2>&1); ST=$?
assert_eq "missing derived file → exit 2" "2" "$ST"
OUT=$(bash "$WRITER" "$CFG" --nope 2>&1); ST=$?
assert_eq "unknown flag → exit 2" "2" "$ST"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
