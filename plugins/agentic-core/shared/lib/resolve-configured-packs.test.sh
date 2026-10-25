#!/usr/bin/env bash
# Tests for resolve-configured-packs.sh. Run with:
#   bash plugins/agentic-core/shared/lib/resolve-configured-packs.test.sh
#
# No framework — exits 0 on success, 1 on any failure.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOLVE="$SCRIPT_DIR/resolve-configured-packs.sh"
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

[[ -n "${TMPDIR:-}" ]] || { echo "TMPDIR is empty; refusing to create test directories" >&2; exit 1; }
WORK="$(mktemp -d "$TMPDIR/resolve-configured-packs-test.XXXXXX")" || exit 1
trap 'rm -rf "$WORK"' EXIT

PROJECT="$WORK/project"
mkdir -p "$PROJECT/.ai/run-context/plugin-roots"

# register <name> <root> — the registry entry a plugin's SessionStart hook writes.
register() { (cd "$2" && pwd -P) > "$PROJECT/.ai/run-context/plugin-roots/$1"; }

# provider_pack <name> <role> <unsupported ops> — a valid provider declaring every operation unsupported.
provider_pack() {
  local root="$WORK/plugins/$1"
  mkdir -p "$root/.claude-plugin"
  printf 'kind: provider\nrole: %s\noperations: {}\nunsupported: [%s]\n' "$2" "$3" > "$root/pack.yaml"
  register "$1" "$root"
}

mkdir -p "$WORK/plugins"
cp -R "$FIXDIR/platform-valid" "$WORK/plugins/example-platform"
mkdir -p "$WORK/plugins/example-platform/.claude-plugin"
register example-platform "$WORK/plugins/example-platform"
provider_pack example-tracker tracker 'fetch_item, post_note, attach_file, list_types, create_item, update_item'
provider_pack example-scm scm 'create_branch, publish_change, check_status'
provider_pack example-browser browser 'render, capture, measure, interact'
provider_pack example-design design 'fetch_reference'

config() {
  printf 'packs:\n'
  printf '%s\n' "$@"
  printf 'paths:\n  spec_dir: .ai/specs\n'
}

echo "[resolve] every role resolved by kind — a platform pack has no role: line"
config '  platform: example-platform' '  tracker: example-tracker' '  scm: example-scm' \
  '  design: none' '  browser: example-browser' > "$WORK/all.yaml"
OUT=$(bash "$RESOLVE" "$WORK/all.yaml" --project-dir "$PROJECT" 2>&1); ST=$?
assert_eq "exit 0" 0 "$ST"
assert_contains "platform resolved on kind: platform" $'resolved\tplatform\texample-platform\t' "$OUT"
assert_contains "tracker resolved on role: tracker" $'resolved\ttracker\texample-tracker\t' "$OUT"
assert_contains "design none is reported, not resolved" $'none\tdesign' "$OUT"
assert_contains "the manifest path is printed" "example-platform/pack.yaml" "$OUT"

echo "[resolve] a provider pack configured as the platform is a mismatch"
config '  platform: example-tracker' '  tracker: example-tracker' '  scm: example-scm' \
  '  design: none' '  browser: example-browser' > "$WORK/wrong-kind.yaml"
OUT=$(bash "$RESOLVE" "$WORK/wrong-kind.yaml" --project-dir "$PROJECT" 2>&1); ST=$?
assert_eq "exit 1" 1 "$ST"
assert_contains "platform named as mismatch" $'mismatch\tplatform\texample-tracker\t' "$OUT"
assert_contains "the other roles still resolve" $'resolved\tscm\texample-scm\t' "$OUT"

echo "[resolve] a provider of another role is a mismatch"
config '  platform: example-platform' '  tracker: example-scm' '  scm: example-scm' \
  '  design: example-design' '  browser: example-browser' > "$WORK/wrong-role.yaml"
OUT=$(bash "$RESOLVE" "$WORK/wrong-role.yaml" --project-dir "$PROJECT" 2>&1); ST=$?
assert_eq "exit 1" 1 "$ST"
assert_contains "the declared role is named" "declares role 'scm'" "$OUT"
assert_contains "design resolves when configured" $'resolved\tdesign\texample-design\t' "$OUT"

echo "[resolve] a configured pack nobody registered is unresolved, with the resolver's line"
config '  platform: example-platform' '  tracker: example-absent' '  scm: example-scm' \
  '  design: none' '  browser: example-browser' > "$WORK/absent.yaml"
OUT=$(bash "$RESOLVE" "$WORK/absent.yaml" --project-dir "$PROJECT" 2>&1); ST=$?
assert_eq "exit 1" 1 "$ST"
assert_contains "unresolved line" $'unresolved\ttracker\texample-absent\tnot resolved' "$OUT"

echo "[resolve] a required role missing from packs: is named (G217)"
config '  tracker: example-tracker' '  scm: example-scm' '  design: none' > "$WORK/missing.yaml"
OUT=$(bash "$RESOLVE" "$WORK/missing.yaml" --project-dir "$PROJECT" 2>&1); ST=$?
assert_eq "exit 1" 1 "$ST"
assert_contains "platform missing" $'missing\tplatform' "$OUT"
assert_contains "browser missing" $'missing\tbrowser' "$OUT"

echo "[resolve] usage and refusals"
OUT=$(bash "$RESOLVE" 2>&1); ST=$?
assert_eq "no argument → exit 2" 2 "$ST"
OUT=$(bash "$RESOLVE" "$WORK/nothing.yaml" 2>&1); ST=$?
assert_eq "no config → exit 2" 2 "$ST"
printf 'paths:\n  spec_dir: .ai/specs\n' > "$WORK/no-packs.yaml"
OUT=$(bash "$RESOLVE" "$WORK/no-packs.yaml" --project-dir "$PROJECT" 2>&1); ST=$?
assert_eq "no packs: block → exit 2" 2 "$ST"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
