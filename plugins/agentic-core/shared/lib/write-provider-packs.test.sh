#!/usr/bin/env bash
# Tests for write-provider-packs.sh. Run with:
#   bash plugins/agentic-core/shared/lib/write-provider-packs.test.sh
#
# No framework — exits 0 on success, 1 on first failure. Mirrors the harness
# in write-detected-config.test.sh.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRITER="$SCRIPT_DIR/write-provider-packs.sh"

PASS=0
FAIL=0

assert_exit() {
  local desc="$1" expected="$2" actual="$3" output="$4"
  if [[ "$expected" == "$actual" ]]; then
    PASS=$((PASS + 1))
    echo "  ok: $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $desc"
    echo "    expected exit=$expected, got exit=$actual"
    [[ -n "$output" ]] && echo "    output: $output"
  fi
}

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    PASS=$((PASS + 1))
    echo "  ok: $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $desc"
    echo "    expected output to contain: $needle"
    echo "    got: $haystack"
  fi
}

assert_file_equals() {
  local desc="$1" expected="$2" path="$3"
  local actual
  actual="$(cat "$path" 2>/dev/null || echo "<no file>")"
  if [[ "$actual" == "$expected" ]]; then
    PASS=$((PASS + 1))
    echo "  ok: $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $desc"
    echo "    --- expected ---"
    echo "$expected"
    echo "    --- actual ---"
    echo "$actual"
  fi
}

TMPDIR_TEST="$(mktemp -d "${TMPDIR:-/tmp}/write-provider-packs-test.XXXXXX")"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

echo "=== write-provider-packs.sh tests ==="

echo "[insert] existing file with commands/paths but no packs: block gets all five roles inserted before commands:"
CFG="$TMPDIR_TEST/existing.yaml"
cat > "$CFG" <<'EOF'
version: 1

commands:
  lint: "run lint"
  test: ""
  build: ""
  serve: "start server"

paths:
  spec_dir: ".ai/specs"
  preview: "http://localhost:3000/preview"
EOF
OUT=$(bash "$WRITER" "$CFG" "platform-pack" "tracker-pack" "scm-pack" "design-pack" "browser-pack" 2>&1); ST=$?
assert_exit "insert succeeds (exit 0)" 0 $ST "$OUT"
assert_contains "reports updated, not written" "updated" "$OUT"
EXPECTED_INSERTED='version: 1

packs:
  platform: platform-pack
  tracker: tracker-pack
  scm: scm-pack
  design: design-pack
  browser: browser-pack

commands:
  lint: "run lint"
  test: ""
  build: ""
  serve: "start server"

paths:
  spec_dir: ".ai/specs"
  preview: "http://localhost:3000/preview"'
assert_file_equals "packs: block inserted right after version, rest untouched" "$EXPECTED_INSERTED" "$CFG"

echo "[cross-check] the written packs block plus limits and trigger passes validate-project-config.sh"
COMBINED="$TMPDIR_TEST/combined.yaml"
{
  cat "$CFG"
  echo
  echo "limits:"
  echo "  questions_per_run: 3"
  echo "  fix_attempts_default: 2"
  echo
  echo "trigger:"
  echo '  token: "@example-run"'
  echo "  allowed_identities:"
  echo '    - "example-identity-1"'
} > "$COMBINED"
OUT=$(bash "$SCRIPT_DIR/validate-project-config.sh" "$COMBINED" 2>&1); ST=$?
assert_exit "spliced file passes validate-project-config.sh (exit 0)" 0 $ST "$OUT"

echo "[create] fresh file gets version + packs, nothing else"
FRESH="$TMPDIR_TEST/fresh.yaml"
OUT=$(bash "$WRITER" "$FRESH" "platform-pack" "tracker-pack" "scm-pack" "design-pack" "browser-pack" 2>&1); ST=$?
assert_exit "fresh create succeeds (exit 0)" 0 $ST "$OUT"
assert_contains "reports the path written" "$FRESH" "$OUT"
EXPECTED_FRESH='version: 1

packs:
  platform: platform-pack
  tracker: tracker-pack
  scm: scm-pack
  design: design-pack
  browser: browser-pack'
assert_file_equals "fresh file matches expected shape exactly" "$EXPECTED_FRESH" "$FRESH"

echo "[update] re-running on a file that already has a five-role packs: block updates values in place, no duplication"
OUT=$(bash "$WRITER" "$CFG" "platform-2" "tracker-2" "scm-2" "design-pack-2" "browser-2" 2>&1); ST=$?
assert_exit "update succeeds (exit 0)" 0 $ST "$OUT"
assert_contains "reports updated" "updated" "$OUT"
EXPECTED_UPDATED='version: 1

packs:
  platform: platform-2
  tracker: tracker-2
  scm: scm-2
  design: design-pack-2
  browser: browser-2

commands:
  lint: "run lint"
  test: ""
  build: ""
  serve: "start server"

paths:
  spec_dir: ".ai/specs"
  preview: "http://localhost:3000/preview"'
assert_file_equals "packs: values updated in place, no dup blocks" "$EXPECTED_UPDATED" "$CFG"

for role in platform tracker scm design browser; do
  echo "[reject] empty $role name"
  CFGE="$TMPDIR_TEST/empty-$role.yaml"
  args=("platform-pack" "tracker-pack" "scm-pack" "design-pack" "browser-pack")
  case "$role" in
    platform) args[0]="" ;; tracker) args[1]="" ;; scm) args[2]="" ;; design) args[3]="" ;; browser) args[4]="" ;;
  esac
  OUT=$(bash "$WRITER" "$CFGE" "${args[@]}" 2>&1); ST=$?
  assert_exit "empty $role rejected (exit 1)" 1 $ST "$OUT"
  assert_contains "reason names $role" "packs.$role is empty" "$OUT"
  if [[ -f "$CFGE" ]]; then
    FAIL=$((FAIL + 1))
    echo "  FAIL: no file written when $role is empty"
  else
    PASS=$((PASS + 1))
    echo "  ok: no file written when $role is empty"
  fi
done

echo "[reject] a value containing a double quote"
CFG4="$TMPDIR_TEST/bad-quote.yaml"
OUT=$(bash "$WRITER" "$CFG4" "platform-pack" 'tracker"2' "scm-pack" "design-pack" "browser-pack" 2>&1); ST=$?
assert_exit "quote-containing value rejected (exit 1)" 1 $ST "$OUT"

echo "[usage] wrong argument count"
OUT=$(bash "$WRITER" "$TMPDIR_TEST/x.yaml" "tracker-pack" 2>&1); ST=$?
assert_exit "two arguments -> usage error (exit 2)" 2 $ST "$OUT"
OUT=$(bash "$WRITER" "$TMPDIR_TEST/x.yaml" "tracker-pack" "scm-pack" "design-pack" 2>&1); ST=$?
assert_exit "the old four-argument form -> usage error (exit 2)" 2 $ST "$OUT"
assert_contains "usage line names the platform argument" "<platform>" "$OUT"
assert_contains "usage line names the browser argument" "<browser>" "$OUT"

echo "[create] parent directory does not exist yet — script creates it"
CFG5="$TMPDIR_TEST/nested/dir/config.yaml"
OUT=$(bash "$WRITER" "$CFG5" "platform-pack" "tracker-pack" "scm-pack" "design-pack" "browser-pack" 2>&1); ST=$?
assert_exit "create under a missing parent directory succeeds (exit 0)" 0 $ST "$OUT"
if [[ -f "$CFG5" ]]; then
  PASS=$((PASS + 1))
  echo "  ok: file exists under the newly created parent directory"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: file was not created under the newly created parent directory"
fi

for shape in two three; do
  echo "[upgrade] a packs: block written by an earlier version ($shape provider roles) becomes the five-role block, in place"
  CFG_OLD="$TMPDIR_TEST/old-shape-$shape.yaml"
  {
    printf 'version: 1\n\npacks:\n  tracker: tracker-pack\n  scm: scm-pack\n'
    [[ "$shape" == three ]] && printf '  design: design-pack\n'
    printf '\ncommands:\n  lint: ""\n'
  } > "$CFG_OLD"
  OUT=$(bash "$WRITER" "$CFG_OLD" "platform-pack" "tracker-pack" "scm-pack" "design-pack" "browser-pack" 2>&1); ST=$?
  assert_exit "old $shape-role block accepted (exit 0)" 0 $ST "$OUT"
  EXPECTED_UPGRADED='version: 1

packs:
  platform: platform-pack
  tracker: tracker-pack
  scm: scm-pack
  design: design-pack
  browser: browser-pack

commands:
  lint: ""'
  assert_file_equals "old $shape-role block replaced, nothing duplicated" "$EXPECTED_UPGRADED" "$CFG_OLD"
done

echo "[reject] existing packs: block not in a shape this script wrote"
CFG6="$TMPDIR_TEST/malformed-packs.yaml"
cat > "$CFG6" <<'EOF'
version: 1

packs:
  scm: example-scm
  tracker: example-tracker

commands:
  lint: ""
EOF
OUT=$(bash "$WRITER" "$CFG6" "platform-pack" "tracker-pack" "scm-pack" "design-pack" "browser-pack" 2>&1); ST=$?
assert_exit "malformed existing packs: block rejected (exit 1)" 1 $ST "$OUT"

echo "[reject] no 'version:' line to anchor an insertion against"
CFG7="$TMPDIR_TEST/no-version.yaml"
cat > "$CFG7" <<'EOF'
commands:
  lint: ""
EOF
OUT=$(bash "$WRITER" "$CFG7" "platform-pack" "tracker-pack" "scm-pack" "design-pack" "browser-pack" 2>&1); ST=$?
assert_exit "missing version: line rejected (exit 1)" 1 $ST "$OUT"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
