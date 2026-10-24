#!/usr/bin/env bash
# Tests for write-sandbox-hosts.sh. Run with:
#   bash plugins/agentic-core/shared/lib/write-sandbox-hosts.test.sh
#
# No framework — exits 0 on success, 1 on any failure.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRITE="$SCRIPT_DIR/write-sandbox-hosts.sh"

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

[[ -n "${TMPDIR:-}" ]] || { echo "TMPDIR is empty; refusing to create test directories" >&2; exit 1; }
WORK="$(mktemp -d "$TMPDIR/write-sandbox-hosts-test.XXXXXX")" || exit 1
trap 'rm -rf "$WORK"' EXIT

T=$'\t'
DECL="$WORK/declarations.txt"
{
  echo "env${T}example-tracker${T}EXAMPLE_SITE${T}the host name of your example tracker site"
  echo "host${T}example-platform${T}*.example-preview.test"
  echo "host${T}example-tracker${T}*.example-tracker.test"
  echo "host${T}example-scm${T}api.example-scm.test"
  echo "host${T}example-scm${T}*.example-tracker.test"
} > "$DECL"

echo "[create] an absent file gets the allowlist, each host once, in declaration order"
F="$WORK/a/.claude/settings.json"
OUT=$(bash "$WRITE" "$DECL" --file "$F" 2>&1); ST=$?
assert_eq "exit 0" 0 "$ST"
assert_contains "reports the file created" "created: $F" "$OUT"
assert_contains "names a host added" "added: api.example-scm.test" "$OUT"
assert_eq "the list" '["*.example-preview.test","*.example-tracker.test","api.example-scm.test"]' \
  "$(jq -c '.sandbox.network.allowedDomains' "$F")"

echo "[merge] existing hosts and settings are kept, in their order; only missing hosts are appended"
G="$WORK/b/settings.json"
mkdir -p "$WORK/b"
cat > "$G" <<'EOF'
{
  "enabledPlugins": { "example-platform@example": true },
  "sandbox": {
    "enabled": true,
    "network": { "allowedDomains": ["github.com", "api.example-scm.test"] }
  }
}
EOF
OUT=$(bash "$WRITE" "$DECL" --file "$G" 2>&1); ST=$?
assert_eq "exit 0" 0 "$ST"
assert_contains "reports the file updated" "updated: $G" "$OUT"
assert_contains "names a host already present" "present: api.example-scm.test" "$OUT"
assert_eq "the list: old first, unchanged, then the new" \
  '["github.com","api.example-scm.test","*.example-preview.test","*.example-tracker.test"]' \
  "$(jq -c '.sandbox.network.allowedDomains' "$G")"
assert_eq "other settings unchanged" 'true|true' \
  "$(jq -c '.enabledPlugins["example-platform@example"]' "$G")|$(jq -c '.sandbox.enabled' "$G")"

echo "[re-run] nothing missing → the file is not rewritten"
cp "$G" "$WORK/before.json"
touch -t 202001010000 "$G"
OUT=$(bash "$WRITE" "$DECL" --file "$G" 2>&1); ST=$?
assert_eq "exit 0" 0 "$ST"
assert_contains "reports the file unchanged" "unchanged: $G" "$OUT"
cmp -s "$G" "$WORK/before.json"; assert_eq "byte-identical" 0 $?
assert_eq "not even touched" "202001010000" "$(date -r "$G" +%Y%m%d%H%M 2>/dev/null || stat -c %y "$G")"

echo "[merge] a file with no sandbox block gets one"
H="$WORK/c/settings.json"
mkdir -p "$WORK/c"
echo '{ "enabledPlugins": {} }' > "$H"
OUT=$(bash "$WRITE" "$DECL" --file "$H" 2>&1); ST=$?
assert_eq "exit 0" 0 "$ST"
assert_eq "three hosts" "3" "$(jq '.sandbox.network.allowedDomains | length' "$H")"
assert_eq "enabledPlugins kept" "{}" "$(jq -c '.enabledPlugins' "$H")"

echo "[refused] not JSON, or a sandbox / network / allowedDomains of the wrong type — file unchanged"
J="$WORK/d/settings.json"
mkdir -p "$WORK/d"
for bad in '{ "sandbox": ' '[]' '{ "sandbox": true }' '{ "sandbox": { "network": [] } }' \
           '{ "sandbox": { "network": { "allowedDomains": "github.com" } } }'; do
  printf '%s' "$bad" > "$J"
  OUT=$(bash "$WRITE" "$DECL" --file "$J" 2>&1); ST=$?
  assert_eq "refused (exit 1): $bad" 1 "$ST"
  assert_eq "unchanged: $bad" "$bad" "$(cat "$J")"
done
assert_contains "says why" "refused: $J" "$OUT"

echo "[nothing declared] no host → no file created"
printf 'env%sp%sX%sy\n' "$T" "$T" "$T" > "$WORK/env-only.txt"
K="$WORK/e/settings.json"
OUT=$(bash "$WRITE" "$WORK/env-only.txt" --file "$K" 2>&1); ST=$?
assert_eq "exit 0" 0 "$ST"
assert_contains "says nothing was needed" "none: no host declared" "$OUT"
[[ ! -e "$K" ]]; assert_eq "no file created" 0 $?

echo "[usage]"
bash "$WRITE" >/dev/null 2>&1; ST=$?
assert_eq "no argument: exit 2" 2 "$ST"

echo "=== $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]]
