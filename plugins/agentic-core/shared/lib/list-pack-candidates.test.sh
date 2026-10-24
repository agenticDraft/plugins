#!/usr/bin/env bash
# Tests for list-pack-candidates.sh. Run with:
#   bash plugins/agentic-core/shared/lib/list-pack-candidates.test.sh
#
# No framework — exits 0 on success, 1 on any failure.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIST="$SCRIPT_DIR/list-pack-candidates.sh"
. "$SCRIPT_DIR/register-source-tree.sh"

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

[[ -n "${TMPDIR:-}" ]] || { echo "TMPDIR is empty; refusing to create test directories" >&2; exit 1; }
WORK="$(mktemp -d "$TMPDIR/list-pack-candidates-test.XXXXXX")" || exit 1
trap 'rm -rf "$WORK"' EXIT

# fake_pack <name> <pack.yaml head line(s)> — a plugin root registered under <name>.
fake_pack() {
  local name="$1" root="$WORK/roots/$1"; shift
  mkdir -p "$root/.claude-plugin" "$WORK/fake/.ai/run-context/plugin-roots"
  printf '{"name": "%s"}\n' "$name" > "$root/.claude-plugin/plugin.json"
  [[ $# -gt 0 ]] && printf '%s\n' "$@" > "$root/pack.yaml"
  (cd "$root" && pwd -P) > "$WORK/fake/.ai/run-context/plugin-roots/$name"
}

echo "=== list-pack-candidates.sh tests ==="

echo "[source tree] every shipped pack listed under its role, in role order; the core has no pack.yaml"
register_source_tree "$WORK/project" || { echo "cannot register the source tree" >&2; exit 1; }
OUT=$(bash "$LIST" --project-dir "$WORK/project" 2>&1); ST=$?
assert_eq "exit 0" "0" "$ST"
assert_eq "five roles, one pack each, in role order" $'platform\ntracker\nscm\ndesign\nbrowser' "$(printf '%s\n' "$OUT" | cut -f1)"
REGISTERED=$(ls "$WORK/project/.ai/run-context/plugin-roots")
while IFS=$'\t' read -r role name; do
  if printf '%s\n' "$REGISTERED" | grep -qx -- "$name"; then ok_name=1; else ok_name=0; fi
  assert_eq "$role candidate is a registered plugin" "1" "$ok_name"
done <<< "$OUT"

echo "[fixture] two candidates for one role, a role with none, a non-pack plugin"
fake_pack tracker-b "kind: provider" "role: tracker"
fake_pack tracker-a "kind: provider" "role: tracker"
fake_pack my-platform "kind: platform"
fake_pack knowledge-only
OUT=$(bash "$LIST" --project-dir "$WORK/fake" 2>&1); ST=$?
assert_eq "exit 0" "0" "$ST"
assert_eq "both trackers, sorted; no line for the non-pack plugin" $'platform\tmy-platform\ntracker\ttracker-a\ntracker\ttracker-b' "$OUT"

echo "[not resolved] an empty registry is the resolver's refusal, passed on"
mkdir -p "$WORK/empty"
OUT=$(bash "$LIST" --project-dir "$WORK/empty" 2>&1); ST=$?
assert_eq "exit 1" "1" "$ST"

echo "[usage]"
OUT=$(bash "$LIST" --nope 2>&1); ST=$?
assert_eq "unknown flag → exit 2" "2" "$ST"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
