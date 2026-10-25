#!/usr/bin/env bash
# Tests for check-pack-environment.sh. Run with:
#   bash plugins/agentic-core/shared/lib/check-pack-environment.test.sh
#
# No framework — exits 0 on success, 1 on any failure. Every value set here is
# a fixture; the real credentials file is never read.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SCRIPT_DIR/check-pack-environment.sh"
FIXDIR="$SCRIPT_DIR/../fixtures/pack-manifest"

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
WORK="$(mktemp -d "$TMPDIR/check-pack-environment-test.XXXXXX")" || exit 1
trap 'rm -rf "$WORK"' EXIT

# pack <dir> <declarations> — a valid provider with the given declarations appended.
pack() {
  mkdir -p "$WORK/$1"
  printf 'kind: provider\nrole: design\noperations: {}\nunsupported: [fetch_reference]\n%s\n' "$2" > "$WORK/$1/pack.yaml"
}

pack tracker 'env:
  - name: EXAMPLE_SITE
    source: "the host name of your example tracker site"
  - name: EXAMPLE_API_TOKEN
    source: "example account settings, API tokens"
hosts: ["*.example-tracker.test"]'
pack scm 'env:
  - name: EXAMPLE_SCM_TOKEN
    source: "an access token for the example code host"
    login_alternative: "example-cli auth login"
hosts: ["api.example-scm.test"]'
pack bare ''

SETTINGS="$WORK/settings.json"
printf '{"sandbox":{"network":{"allowedDomains":["*.example-tracker.test","api.example-scm.test"]}}}\n' > "$SETTINGS"

SECRET="fixture-value-0000-do-not-print"

run() { env -u EXAMPLE_SITE -u EXAMPLE_API_TOKEN -u EXAMPLE_SCM_TOKEN "$@"; }

echo "[env] every variable set → presence only, value never printed"
OUT=$(run EXAMPLE_SITE="$SECRET" EXAMPLE_API_TOKEN="$SECRET" EXAMPLE_SCM_TOKEN="$SECRET" \
  bash "$CHECK" --settings "$SETTINGS" "tracker=$WORK/tracker/pack.yaml" "scm=$WORK/scm/pack.yaml" 2>&1); ST=$?
assert_eq "exit 0" 0 "$ST"
assert_contains "a set variable says presence only" "set: tracker EXAMPLE_API_TOKEN — presence only, not proof that it works" "$OUT"
assert_not_contains "no value printed" "$SECRET" "$OUT"

echo "[env] a missing variable is named with its source"
OUT=$(run EXAMPLE_SITE="$SECRET" bash "$CHECK" --settings "$SETTINGS" "tracker=$WORK/tracker/pack.yaml" 2>&1); ST=$?
assert_eq "exit 1" 1 "$ST"
assert_contains "missing named" "missing: tracker EXAMPLE_API_TOKEN — not set; example account settings, API tokens" "$OUT"
assert_not_contains "no value printed" "$SECRET" "$OUT"

echo "[env] an empty variable counts as missing"
OUT=$(run EXAMPLE_SITE="" EXAMPLE_API_TOKEN="$SECRET" bash "$CHECK" --settings "$SETTINGS" "tracker=$WORK/tracker/pack.yaml" 2>&1); ST=$?
assert_eq "exit 1" 1 "$ST"
assert_contains "empty is missing" "missing: tracker EXAMPLE_SITE" "$OUT"

echo "[env] a placeholder is named as unfilled, value not printed"
OUT=$(run EXAMPLE_SITE="FILL-IN: the host name of your example tracker site" EXAMPLE_API_TOKEN="$SECRET" \
  bash "$CHECK" --settings "$SETTINGS" "tracker=$WORK/tracker/pack.yaml" 2>&1); ST=$?
assert_eq "exit 1" 1 "$ST"
assert_contains "unfilled named" "unfilled: tracker EXAMPLE_SITE — holds a FILL-IN: placeholder" "$OUT"
assert_not_contains "placeholder text not printed" "the host name of your example tracker site" "$OUT"

echo "[env] a login alternative: unset is accepted, pending the credential check"
OUT=$(run bash "$CHECK" --settings "$SETTINGS" "scm=$WORK/scm/pack.yaml" 2>&1); ST=$?
assert_eq "exit 0" 0 "$ST"
assert_contains "login line" "login: scm EXAMPLE_SCM_TOKEN — not set; \"example-cli auth login\" may stand in, proven only by a credential check" "$OUT"

echo "[env] a login alternative: a placeholder breaks the login and fails"
OUT=$(run EXAMPLE_SCM_TOKEN="FILL-IN: an access token" bash "$CHECK" --settings "$SETTINGS" "scm=$WORK/scm/pack.yaml" 2>&1); ST=$?
assert_eq "exit 1" 1 "$ST"
assert_contains "unfilled, and why" "unfilled: scm EXAMPLE_SCM_TOKEN — holds a FILL-IN: placeholder, which breaks \"example-cli auth login\"" "$OUT"

echo "[hosts] a declared host missing from the allowlist is blocked"
printf '{"sandbox":{"network":{"allowedDomains":["*.example-tracker.test"]}}}\n' > "$WORK/partial.json"
OUT=$(run bash "$CHECK" --settings "$WORK/partial.json" "scm=$WORK/scm/pack.yaml" 2>&1); ST=$?
assert_eq "exit 1" 1 "$ST"
assert_contains "blocked host named" "blocked: scm api.example-scm.test — not in sandbox.network.allowedDomains of $WORK/partial.json" "$OUT"

echo "[hosts] a literal host is covered by a wildcard; a wildcard only by itself"
pack literal 'hosts: ["site.example-tracker.test"]'
OUT=$(run bash "$CHECK" --settings "$WORK/partial.json" "x=$WORK/literal/pack.yaml" 2>&1); ST=$?
assert_eq "covered literal → exit 0" 0 "$ST"
assert_contains "allowed line" "allowed: x site.example-tracker.test" "$OUT"
printf '{"sandbox":{"network":{"allowedDomains":["site.example-tracker.test","api.example-scm.test"]}}}\n' > "$WORK/literal.json"
OUT=$(run EXAMPLE_SITE=a EXAMPLE_API_TOKEN=b bash "$CHECK" --settings "$WORK/literal.json" "tracker=$WORK/tracker/pack.yaml" 2>&1); ST=$?
assert_eq "wildcard not met by one literal → exit 1" 1 "$ST"
assert_contains "blocked wildcard" "blocked: tracker *.example-tracker.test" "$OUT"

echo "[hosts] no settings file → every host blocked"
OUT=$(run bash "$CHECK" --settings "$WORK/absent.json" "scm=$WORK/scm/pack.yaml" 2>&1); ST=$?
assert_eq "exit 1" 1 "$ST"
assert_contains "blocked" "blocked: scm api.example-scm.test" "$OUT"

echo "[none] a pack declaring nothing says so"
OUT=$(run bash "$CHECK" --settings "$SETTINGS" "b=$WORK/bare/pack.yaml" 2>&1); ST=$?
assert_eq "exit 0" 0 "$ST"
assert_contains "none line" "none: b declares no variable and no host" "$OUT"

echo "[usage] refusals"
OUT=$(bash "$CHECK" 2>&1); ST=$?
assert_eq "no pack → exit 2" 2 "$ST"
OUT=$(bash "$CHECK" "x=$WORK/absent/pack.yaml" 2>&1); ST=$?
assert_eq "missing manifest → exit 2" 2 "$ST"
printf '[1,2]\n' > "$WORK/array.json"
OUT=$(run bash "$CHECK" --settings "$WORK/array.json" "scm=$WORK/scm/pack.yaml" 2>&1); ST=$?
assert_eq "settings not an object → exit 2" 2 "$ST"
OUT=$(run bash "$CHECK" --settings "$SETTINGS" "p=$FIXDIR/platform-valid/pack.yaml" 2>&1); ST=$?
assert_eq "a platform manifest is read the same way → exit 0" 0 "$ST"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
