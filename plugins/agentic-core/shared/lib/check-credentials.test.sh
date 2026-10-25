#!/usr/bin/env bash
# Tests for check-credentials.sh. Run with:
#   bash plugins/agentic-core/shared/lib/check-credentials.test.sh
#
# No framework — exits 0 on success, 1 on any failure. Every probe here is a
# fixture script; nothing reaches the network.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SCRIPT_DIR/check-credentials.sh"

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
WORK="$(mktemp -d "$TMPDIR/check-credentials-test.XXXXXX")" || exit 1
trap 'rm -rf "$WORK"' EXIT

SECRET="fixture-value-0000-do-not-print"

# pack <dir> <probe exit> — a provider whose one credential check runs a
# fixture script that prints a secret to both streams, then exits as told.
pack() {
  mkdir -p "$WORK/$1/scripts"
  printf '#!/usr/bin/env bash\necho "%s"\necho "%s" >&2\nexit %s\n' "$SECRET" "$SECRET" "$2" > "$WORK/$1/scripts/probe.sh"
  cat > "$WORK/$1/pack.yaml" <<EOF
kind: provider
role: design
operations: {}
unsupported: [fetch_reference]
credential_checks:
  - check: repository-access
    probe: [bash, <pack>/scripts/probe.sh]
    proves: "the credential reaches the configured repository; not what it may write there"
    remedy: "give the credential access to this repository"
EOF
}

pack passing 0
pack failing 1
mkdir -p "$WORK/bare"
printf 'kind: provider\nrole: design\noperations: {}\nunsupported: [fetch_reference]\n' > "$WORK/bare/pack.yaml"

echo "[pass] a passing probe reports what it proves, and nothing it printed"
OUT=$(bash "$CHECK" "scm=$WORK/passing/pack.yaml" 2>&1); ST=$?
assert_eq "exit 0" 0 "$ST"
assert_contains "ok line with proves" "ok: scm repository-access — proves only: the credential reaches the configured repository; not what it may write there" "$OUT"
assert_not_contains "the probe's output is discarded" "$SECRET" "$OUT"

echo "[fail] a failing probe reports the declared remedy before any stage"
OUT=$(bash "$CHECK" "scm=$WORK/failing/pack.yaml" 2>&1); ST=$?
assert_eq "exit 1" 1 "$ST"
assert_contains "failed line with remedy" "failed: scm repository-access — give the credential access to this repository" "$OUT"
assert_not_contains "the probe's output is discarded" "$SECRET" "$OUT"

echo "[none] a pack declaring no check says so; it is not a pass"
OUT=$(bash "$CHECK" "tracker=$WORK/bare/pack.yaml" 2>&1); ST=$?
assert_eq "exit 0" 0 "$ST"
assert_contains "none line" "none: tracker declares no credential check — nothing proves its credential works" "$OUT"

echo "[many] one failure fails the whole check; the others still report"
OUT=$(bash "$CHECK" "a=$WORK/passing/pack.yaml" "b=$WORK/failing/pack.yaml" 2>&1); ST=$?
assert_eq "exit 1" 1 "$ST"
assert_contains "a ok" "ok: a repository-access" "$OUT"
assert_contains "b failed" "failed: b repository-access" "$OUT"

echo "[usage] refusals"
OUT=$(bash "$CHECK" 2>&1); ST=$?
assert_eq "no pack → exit 2" 2 "$ST"
OUT=$(bash "$CHECK" "x=$WORK/absent/pack.yaml" 2>&1); ST=$?
assert_eq "missing manifest → exit 2" 2 "$ST"
mkdir -p "$WORK/malformed"
printf 'kind: provider\nrole: design\noperations: {}\nunsupported: [fetch_reference]\ncredential_checks:\n  - check: a\n    probe: "true"\n' > "$WORK/malformed/pack.yaml"
OUT=$(bash "$CHECK" "x=$WORK/malformed/pack.yaml" 2>&1); ST=$?
assert_eq "malformed block → exit 2" 2 "$ST"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
