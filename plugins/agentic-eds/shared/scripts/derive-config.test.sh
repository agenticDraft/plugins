#!/usr/bin/env bash
# derive-config.test.sh — the project-value derivation from the remote (D129,
# D138). No framework; exits 0 when every case passes, 1 otherwise. Every
# remote is a fixture string; nothing is read from the repository the suite
# sits in.
#
# Usage:
#   bash derive-config.test.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DERIVE="$SCRIPT_DIR/derive-config.sh"
CHECK="$SCRIPT_DIR/check-branch-length.sh"

PASS=0
FAIL=0

ok()  { echo "  ok: $1"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "    $2"; FAIL=$((FAIL + 1)); }

assert_eq()  { if [ "$2" == "$3" ]; then ok "$1"; else bad "$1" "expected: $2 — got: $3"; fi; }
assert_has() { if [[ "$3" == *"$2"* ]]; then ok "$1"; else bad "$1" "expected to contain: $2 — got: $3"; fi; }

name_of_length() { printf 'b%.0s' $(seq 1 "$1"); }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/derive-config.XXXXXX")
[ -n "$WORK" ] && [ -d "$WORK" ] || { echo "cannot create a temporary directory"; exit 1; }
trap 'rm -rf "$WORK"' EXIT

run() { OUT=$(bash "$DERIVE" "$@" 2>&1); CODE=$?; }

# expect_for <remote> <repo> <owner> — the arithmetic, done here independently:
# suffix "--<repo>--<owner>" lower case, limit 63 minus its length.
expect_for() {
  local suffix="--$2--$3"
  suffix=$(printf '%s' "$suffix" | tr '[:upper:]' '[:lower:]')
  printf 'branch_name.max_length=%s\nplatform.preview_host_suffix=%s' "$((63 - ${#suffix}))" "$suffix"
}

echo "[derived] every remote form gives the same two lines"
for remote in "git@github.com:Fixture-Org/A-Site-Repo.git" \
              "https://github.com/Fixture-Org/A-Site-Repo.git" \
              "https://github.com/Fixture-Org/A-Site-Repo" \
              "ssh://git@github.com/Fixture-Org/A-Site-Repo.git"; do
  run --remote "$remote"
  assert_eq "$remote → exit 0" "0" "$CODE"
  assert_eq "$remote → lines" "$(expect_for "$remote" A-Site-Repo Fixture-Org)" "$OUT"
done

echo "[arithmetic] a 40-character suffix gives 23, a 41-character one 22"
run --remote "git@github.com:fixture-org/a-fixture-site-repository.git"
assert_has "40 → 23" "branch_name.max_length=23" "$OUT"
assert_has "40 → suffix" "platform.preview_host_suffix=--a-fixture-site-repository--fixture-org" "$OUT"
run --remote "git@github.com:fixture-orgs/a-fixture-site-repository.git"
assert_has "41 → 22" "branch_name.max_length=22" "$OUT"

echo "[consumer] the derived limit is exactly what the branch check enforces"
run --remote "git@github.com:fixture-org/a-fixture-site-repository.git"
MAX=$(printf '%s\n' "$OUT" | sed -n 's/^branch_name\.max_length=//p')
SUFFIX=$(printf '%s\n' "$OUT" | sed -n 's/^platform\.preview_host_suffix=//p')
printf 'version: 1\n\nbranch_name:\n  max_length: %s\n\nplatform:\n  preview_host_suffix: "%s"\n' "$MAX" "$SUFFIX" > "$WORK/config.yaml"
OUT=$(bash "$CHECK" "$(name_of_length "$MAX")" --config "$WORK/config.yaml" 2>&1); CODE=$?
assert_eq "a branch of the limit passes" "0" "$CODE"
OUT=$(bash "$CHECK" "$(name_of_length $((MAX + 1)))" --config "$WORK/config.yaml" 2>&1); CODE=$?
assert_eq "one more character is refused" "1" "$CODE"
assert_eq "branch + suffix at the limit is one 63-character label" "63" "$(( MAX + ${#SUFFIX} ))"

echo "[refused] what the preview host cannot hold, and what is not a remote"
for remote in "git@github.com:fixture-org/site.with.dots.git" \
              "git@github.com:fixture_org/site.git" \
              "not a remote" \
              "git@github.com:only-one-segment" \
              "git@github.com:fixture-org/$(name_of_length 60).git"; do
  run --remote "$remote"
  assert_eq "'$remote' → exit 1" "1" "$CODE"
  assert_eq "'$remote' → nothing on stdout" "" "$(bash "$DERIVE" --remote "$remote" 2>/dev/null)"
done

echo "[usage]"
run
assert_eq "no argument → exit 2" "2" "$CODE"
run --remote ""
assert_eq "empty remote → exit 2" "2" "$CODE"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
