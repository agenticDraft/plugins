#!/usr/bin/env bash
# Tests for write-credential-placeholders.sh. Run with:
#   bash plugins/agentic-core/shared/lib/write-credential-placeholders.test.sh
#
# No framework — exits 0 on success, 1 on any failure. Every value below is a
# made-up test string; the checks prove such a string is never printed.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRITE="$SCRIPT_DIR/write-credential-placeholders.sh"
FIND="$SCRIPT_DIR/find-placeholders.sh"

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
WORK="$(mktemp -d "$TMPDIR/write-credential-placeholders-test.XXXXXX")" || exit 1
trap 'rm -rf "$WORK"' EXIT

T=$'\t'
DECL="$WORK/declarations.txt"
{
  echo "env${T}example-tracker${T}EXAMPLE_SITE${T}the host name of your example tracker site"
  echo "env${T}example-tracker${T}EXAMPLE_API_TOKEN${T}example account settings, API tokens"
  echo "login${T}example-scm${T}EXAMPLE_SCM_TOKEN${T}example-cli auth login"
  echo "host${T}example-scm${T}api.example-scm.test"
  echo "ignore${T}core${T}.ai/run-context/"
} > "$DECL"

file_mode() { stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1"; }

echo "[create] an absent file gets one placeholder per variable, and nothing for a login variable"
F="$WORK/a/.claude/settings.local.json"
OUT=$(bash "$WRITE" "$DECL" --file "$F" 2>&1); ST=$?
assert_eq "exit 0" 0 "$ST"
assert_contains "reports the file created" "created: $F" "$OUT"
assert_contains "names each key added" "added: EXAMPLE_SITE" "$OUT"
assert_contains "names the second key added" "added: EXAMPLE_API_TOKEN" "$OUT"
assert_contains "names the login alternative" "alternative: EXAMPLE_SCM_TOKEN or example-cli auth login" "$OUT"
assert_eq "the placeholder holds the marker and the source" \
  "FILL-IN: the host name of your example tracker site" "$(jq -r '.env.EXAMPLE_SITE' "$F")"
assert_eq "no key for the login variable" "false" "$(jq '.env | has("EXAMPLE_SCM_TOKEN")' "$F")"
assert_eq "only the two keys" "2" "$(jq '.env | length' "$F")"
assert_eq "readable by the owner only" "600" "$(file_mode "$F")"
FOUND=$(bash "$FIND" "$F"); FST=$?
assert_eq "find-placeholders sees both lines" "1/2" "$FST/$(grep -c '^placeholder:' <<< "$FOUND")"

echo "[re-run] a filled key and a placeholder are both left untouched; the file is not rewritten"
jq '.env.EXAMPLE_API_TOKEN = "test-value-not-a-secret-123"' "$F" > "$F.tmp" && cat "$F.tmp" > "$F" && rm "$F.tmp"
cp "$F" "$WORK/before.json"
OUT=$(bash "$WRITE" "$DECL" --file "$F" 2>&1); ST=$?
assert_eq "exit 0" 0 "$ST"
assert_contains "reports the file unchanged" "unchanged: $F" "$OUT"
assert_contains "names the filled key as kept" "kept: EXAMPLE_API_TOKEN" "$OUT"
assert_contains "names the placeholder key as kept" "kept: EXAMPLE_SITE" "$OUT"
assert_not_contains "never prints a value" "test-value-not-a-secret-123" "$OUT"
cmp -s "$F" "$WORK/before.json"; assert_eq "byte-identical" 0 $?

echo "[merge] an existing file with other settings gains only the missing key"
G="$WORK/b/settings.local.json"
mkdir -p "$WORK/b"
cat > "$G" <<'EOF'
{
  "permissions": { "allow": ["Bash(true)"] },
  "env": {
    "OTHER_VARIABLE": "test-value-other-456",
    "EXAMPLE_SITE": "test-value-site-789"
  },
  "disabledMcpjsonServers": ["example"]
}
EOF
chmod 640 "$G"
OUT=$(bash "$WRITE" "$DECL" --file "$G" 2>&1); ST=$?
assert_eq "exit 0" 0 "$ST"
assert_contains "reports the file updated" "updated: $G" "$OUT"
assert_contains "adds the missing key" "added: EXAMPLE_API_TOKEN" "$OUT"
assert_contains "keeps the present key" "kept: EXAMPLE_SITE" "$OUT"
assert_not_contains "never prints a value" "test-value" "$OUT"
assert_eq "the filled key is unchanged" "test-value-site-789" "$(jq -r '.env.EXAMPLE_SITE' "$G")"
assert_eq "an undeclared key is unchanged" "test-value-other-456" "$(jq -r '.env.OTHER_VARIABLE' "$G")"
assert_eq "other settings are unchanged" '["Bash(true)"]|["example"]' \
  "$(jq -c '.permissions.allow' "$G")|$(jq -c '.disabledMcpjsonServers' "$G")"
assert_eq "the file's mode is kept" "640" "$(file_mode "$G")"

echo "[merge] a file with no env block gets one"
H="$WORK/c/settings.local.json"
mkdir -p "$WORK/c"
echo '{ "permissions": {} }' > "$H"
OUT=$(bash "$WRITE" "$DECL" --file "$H" 2>&1); ST=$?
assert_eq "exit 0" 0 "$ST"
assert_eq "both keys added" "2" "$(jq '.env | length' "$H")"

echo "[login] a login variable the human set is kept and never removed"
I="$WORK/d/settings.local.json"
mkdir -p "$WORK/d"
echo '{ "env": { "EXAMPLE_SCM_TOKEN": "test-value-scm-000" } }' > "$I"
OUT=$(bash "$WRITE" "$DECL" --file "$I" 2>&1); ST=$?
assert_eq "exit 0" 0 "$ST"
assert_eq "still there, unchanged" "test-value-scm-000" "$(jq -r '.env.EXAMPLE_SCM_TOKEN' "$I")"
assert_not_contains "never prints its value" "test-value-scm-000" "$OUT"

echo "[refused] a file that is not JSON, or whose env is not an object — nothing printed from it, nothing changed"
J="$WORK/e/settings.local.json"
mkdir -p "$WORK/e"
printf '{ "env": { "EXAMPLE_SITE": "test-value-broken-111" ' > "$J"
cp "$J" "$WORK/broken.before"
OUT=$(bash "$WRITE" "$DECL" --file "$J" 2>&1); ST=$?
assert_eq "malformed: exit 1" 1 "$ST"
assert_contains "says it refused" "refused: $J" "$OUT"
assert_not_contains "prints nothing from the file" "test-value-broken-111" "$OUT"
cmp -s "$J" "$WORK/broken.before"; assert_eq "malformed file unchanged" 0 $?
echo '{ "env": "test-value-string-222" }' > "$J"
OUT=$(bash "$WRITE" "$DECL" --file "$J" 2>&1); ST=$?
assert_eq "env a string: exit 1" 1 "$ST"
assert_not_contains "prints nothing from the file" "test-value-string-222" "$OUT"
echo '["test-value-array-333"]' > "$J"
OUT=$(bash "$WRITE" "$DECL" --file "$J" 2>&1); ST=$?
assert_eq "not an object: exit 1" 1 "$ST"
assert_not_contains "prints nothing from the file" "test-value-array-333" "$OUT"

echo "[nothing declared] no variable → no file created"
printf 'host%sp%sexample.test\n' "$T" "$T" > "$WORK/hosts-only.txt"
K="$WORK/f/settings.local.json"
OUT=$(bash "$WRITE" "$WORK/hosts-only.txt" --file "$K" 2>&1); ST=$?
assert_eq "exit 0" 0 "$ST"
assert_contains "says nothing was needed" "none: no variable declared" "$OUT"
[[ ! -e "$K" ]]; assert_eq "no file created" 0 $?

echo "[usage]"
bash "$WRITE" >/dev/null 2>&1; ST=$?
assert_eq "no argument: exit 2" 2 "$ST"
bash "$WRITE" "$WORK/absent.txt" >/dev/null 2>&1; ST=$?
assert_eq "no declarations file: exit 2" 2 "$ST"

echo "=== $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]]
