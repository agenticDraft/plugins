#!/usr/bin/env bash
# Tests for find-placeholders.sh. Run with:
#   bash plugins/agentic-core/shared/lib/find-placeholders.test.sh
#
# No framework — exits 0 on success, 1 on any failure.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SCRIPT_DIR/find-placeholders.sh"

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
WORK="$(mktemp -d "$TMPDIR/find-placeholders-test.XXXXXX")" || exit 1
trap 'rm -rf "$WORK"' EXIT

echo "=== find-placeholders.sh tests ==="

echo "[found] one marker → its file, line and description; exit 1"
cat > "$WORK/one.yaml" <<'EOF'
version: 1
trigger:
  token: "@example-run"
  allowed_identities:
    - "FILL-IN: tracker identity of a person allowed to trigger a run"
EOF
OUT=$(bash "$CHECK" "$WORK/one.yaml" 2>&1); ST=$?
assert_eq "a marker → exit 1" "1" "$ST"
assert_eq "names file, line and what goes there" \
  "placeholder: $WORK/one.yaml:5: tracker identity of a person allowed to trigger a run" "$OUT"

echo "[found] several markers across two files → one line each, in order"
printf '{\n  "env": {\n    "A_TOKEN": "FILL-IN: the A token",\n    "B_SITE": "FILL-IN: the B site"\n  }\n}\n' > "$WORK/two.json"
OUT=$(bash "$CHECK" "$WORK/one.yaml" "$WORK/two.json" 2>&1); ST=$?
assert_eq "markers in two files → exit 1" "1" "$ST"
assert_eq "three lines" "3" "$(printf '%s\n' "$OUT" | grep -c '^placeholder: ')"
assert_contains "json line 3 named" "two.json:3: the A token" "$OUT"
assert_contains "json line 4 named" "two.json:4: the B site" "$OUT"

echo "[none] a filled file → exit 0, and no value is ever printed"
cat > "$WORK/filled.yaml" <<'EOF'
version: 1
trigger:
  token: "@example-run"
  allowed_identities:
    - "secret-identity-0000"
EOF
OUT=$(bash "$CHECK" "$WORK/filled.yaml" 2>&1); ST=$?
assert_eq "no marker → exit 0" "0" "$ST"
assert_eq "says none, names the file" "none: $WORK/filled.yaml" "$OUT"
assert_not_contains "the filled value is not printed" "secret-identity" "$OUT"

echo "[found] a marker line never prints what else is on that line"
printf 'key: "real-value-1234 FILL-IN: half filled"\n' > "$WORK/half.yaml"
OUT=$(bash "$CHECK" "$WORK/half.yaml" 2>&1); ST=$?
assert_eq "half-filled → exit 1" "1" "$ST"
assert_not_contains "text before the marker is not printed" "real-value" "$OUT"
assert_contains "the description is printed" "half.yaml:1: half filled" "$OUT"

echo "[usage] no argument → exit 2; missing file → exit 2"
OUT=$(bash "$CHECK" 2>&1); ST=$?
assert_eq "no argument → exit 2" "2" "$ST"
OUT=$(bash "$CHECK" "$WORK/absent.yaml" 2>&1); ST=$?
assert_eq "missing file → exit 2" "2" "$ST"
assert_contains "names the missing file" "absent.yaml" "$OUT"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
