#!/usr/bin/env bash
# Tests for derive-project-values.sh. Run with:
#   bash plugins/agentic-core/shared/lib/derive-project-values.test.sh
#
# No framework — exits 0 on success, 1 on any failure.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DERIVE="$SCRIPT_DIR/derive-project-values.sh"

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
WORK="$(mktemp -d "$TMPDIR/derive-project-values-test.XXXXXX")" || exit 1
trap 'rm -rf "$WORK"' EXIT

# make_pack <dir> <script body | ""> — a platform pack declaring a derivation
# script with the given body; an empty body declares none.
make_pack() {
  local dir="$WORK/$1" body="$2"
  mkdir -p "$dir/scripts"
  printf 'kind: platform\nstages: []\n' > "$dir/pack.yaml"
  if [[ -n "$body" ]]; then
    printf '%s\n' "#!/usr/bin/env bash" "$body" > "$dir/scripts/derive.sh"
    printf 'ignore_paths: ["out/"]\nconfig_derivation: "scripts/derive.sh"\nreference_docs: "https://docs.example.org/"\n' \
      >> "$dir/pack.yaml"
  fi
  echo "$dir"
}

echo "=== derive-project-values.sh tests ==="

echo "[derived] the pack's lines pass through, the remote reaches the script"
P=$(make_pack ok 'echo "branch_name.max_length=30"; echo "platform.remote_seen=${2//[^a-z]/}"')
OUT=$(bash "$DERIVE" "$P" --remote "git@host.example:owner/repo.git" 2>/dev/null); ST=$?
assert_eq "exit 0" "0" "$ST"
assert_eq "both lines, in order" $'branch_name.max_length=30\nplatform.remote_seen=githostexampleownerrepogit' "$OUT"

echo "[not-declared] a platform pack with no config_derivation → exit 3, says so"
P=$(make_pack none "")
OUT=$(bash "$DERIVE" "$P" --remote "git@host.example:owner/repo.git" 2>&1); ST=$?
assert_eq "exit 3" "3" "$ST"
assert_contains "says not declared" "not-declared" "$OUT"

echo "[refused] a malformed line refuses the whole output"
for body in 'echo "branch_name.max_length=30"; echo "commands.lint=rm -rf ."' \
            'echo "branch_name.max_length=-1"' \
            'echo "platform.Key=x"' \
            'echo "platform.key=a\"b"' \
            'echo "just text"'; do
  P=$(make_pack "bad-$RANDOM" "$body")
  OUT=$(bash "$DERIVE" "$P" --remote "r" 2>/dev/null); ST=$?
  assert_eq "malformed → exit 1 ($body)" "1" "$ST"
  assert_eq "nothing on stdout ($body)" "" "$OUT"
done

echo "[refused] a script that exits non-zero, or prints nothing"
P=$(make_pack fails 'echo "cannot parse" >&2; exit 4')
OUT=$(bash "$DERIVE" "$P" --remote "r" 2>&1); ST=$?
assert_eq "non-zero script → exit 1" "1" "$ST"
assert_contains "the script's own message is relayed" "cannot parse" "$OUT"
P=$(make_pack silent ':')
OUT=$(bash "$DERIVE" "$P" --remote "r" 2>&1); ST=$?
assert_eq "empty output → exit 1" "1" "$ST"

echo "[usage]"
OUT=$(bash "$DERIVE" 2>&1); ST=$?
assert_eq "no argument → exit 2" "2" "$ST"
OUT=$(bash "$DERIVE" "$WORK/ok" 2>&1); ST=$?
assert_eq "no --remote → exit 2" "2" "$ST"
OUT=$(bash "$DERIVE" "$WORK/ok" --remote "" 2>&1); ST=$?
assert_eq "empty remote → exit 2" "2" "$ST"
OUT=$(bash "$DERIVE" "$WORK/absent" --remote "r" 2>&1); ST=$?
assert_eq "no pack.yaml → exit 2" "2" "$ST"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
