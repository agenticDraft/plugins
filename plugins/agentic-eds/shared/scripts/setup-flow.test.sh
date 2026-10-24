#!/usr/bin/env bash
# setup-flow.test.sh — the core's setup scripts, in the order setup runs them,
# in a fixture project with every pack of this source tree registered and a
# fixture remote (D138). No framework; exits 0 when every case passes, 1
# otherwise. Nothing is read from the repository the suite sits in.
#
# Usage:
#   bash setup-flow.test.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_LIB="$SCRIPT_DIR/../../core/lib"
. "$CORE_LIB/register-source-tree.sh"

PASS=0
FAIL=0

ok()  { echo "  ok: $1"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "    $2"; FAIL=$((FAIL + 1)); }

assert_eq()  { if [ "$2" == "$3" ]; then ok "$1"; else bad "$1" "expected: $2 — got: $3"; fi; }
assert_has() { if [[ "$3" == *"$2"* ]]; then ok "$1"; else bad "$1" "expected to contain: $2 — got: $3"; fi; }

[[ -n "${TMPDIR:-}" ]] || { echo "TMPDIR is empty; refusing to create test directories" >&2; exit 1; }
WORK=$(mktemp -d "$TMPDIR/setup-flow.XXXXXX") || exit 1
trap 'rm -rf "$WORK"' EXIT

PROJECT="$WORK/project"
CONFIG="$PROJECT/.ai/project-config.yaml"
OWNER="fixture-org"
REPO="a-fixture-site-repository"

mkdir -p "$PROJECT"
git -C "$PROJECT" init -q
git -C "$PROJECT" remote add origin "git@github.com:$OWNER/$REPO.git"
register_source_tree "$PROJECT" || { echo "cannot register the source tree" >&2; exit 1; }

echo "[scan] one installed candidate per role, so nothing is asked and no pack is generated"
CANDIDATES=$(bash "$CORE_LIB/list-pack-candidates.sh" --project-dir "$PROJECT"); CODE=$?
assert_eq "scan exit 0" "0" "$CODE"
for role in platform tracker scm design browser; do
  assert_eq "$role → exactly one candidate" "1" "$(printf '%s\n' "$CANDIDATES" | awk -F'\t' -v r="$role" '$1 == r' | wc -l | tr -d ' ')"
done
pick() { printf '%s\n' "$CANDIDATES" | awk -F'\t' -v r="$1" '$1 == r { print $2 }'; }
assert_eq "the platform candidate is this pack" "agentic-eds" "$(pick platform)"

echo "[write] commands and paths, the spec directory fixed"
OUT=$(bash "$CORE_LIB/write-detected-config.sh" "$CONFIG" "npm run lint" "" "" "npx -y @adobe/aem-cli up" ".ai/specs" "http://localhost:3000/preview" 2>&1); CODE=$?
assert_eq "commands/paths exit 0" "0" "$CODE"
OUT=$(bash "$CORE_LIB/write-provider-packs.sh" "$CONFIG" "$(pick platform)" "$(pick tracker)" "$(pick scm)" "$(pick design)" "$(pick browser)" 2>&1); CODE=$?
assert_eq "packs exit 0" "0" "$CODE"

echo "[derive] through the platform pack's declared script, from the fixture remote"
REMOTE=$(git -C "$PROJECT" remote get-url origin)
ROOT=$(bash "$CORE_LIB/resolve-plugin-root.sh" "$(pick platform)" --project-dir "$PROJECT"); CODE=$?
assert_eq "platform pack resolved" "0" "$CODE"
bash "$CORE_LIB/derive-project-values.sh" "$ROOT" --remote "$REMOTE" > "$WORK/derived.txt"; CODE=$?
assert_eq "derive exit 0" "0" "$CODE"
OUT=$(bash "$CORE_LIB/write-run-config.sh" "$CONFIG" --derived "$WORK/derived.txt" 2>&1); CODE=$?
assert_eq "limits/trigger/derived exit 0" "0" "$CODE"

echo "[derived keys] match the arithmetic, done here: 63 minus len(--<repo>--<owner>)"
SUFFIX="--$REPO--$OWNER"
assert_has "suffix written" "  preview_host_suffix: \"$SUFFIX\"" "$(cat "$CONFIG")"
assert_has "max_length written" "  max_length: $((63 - ${#SUFFIX}))" "$(cat "$CONFIG")"
assert_eq "this fixture's numbers" "40 23" "${#SUFFIX} $((63 - ${#SUFFIX}))"

echo "[placeholder] the identity holds a placeholder until the fixture fills it"
OUT=$(bash "$CORE_LIB/find-placeholders.sh" "$CONFIG"); CODE=$?
assert_eq "placeholder found → exit 1 (setup does not validate yet)" "1" "$CODE"
LINE=$(grep -n 'FILL-IN:' "$CONFIG" | cut -d: -f1)
assert_has "names the file and the line" "placeholder: $CONFIG:$LINE:" "$OUT"
assert_eq "that line is under trigger.allowed_identities" "  allowed_identities:" "$(sed -n "$((LINE - 1))p" "$CONFIG")"

sed -i.bak 's/"FILL-IN: [^"]*"/"fixture-identity-0000"/' "$CONFIG" && rm -f "$CONFIG.bak"
OUT=$(bash "$CORE_LIB/find-placeholders.sh" "$CONFIG"); CODE=$?
assert_eq "after the fixture fills it → exit 0" "0" "$CODE"
OUT=$(bash "$CORE_LIB/validate-project-config.sh" "$CONFIG" 2>&1); CODE=$?
assert_eq "the written config passes the validator" "0" "$CODE"
assert_eq "validator says valid" "valid" "$OUT"

echo "[contents] the spec directory and the defaults"
BODY=$(cat "$CONFIG")
assert_has "spec_dir is .ai/specs" '  spec_dir: ".ai/specs"' "$BODY"
assert_has "default questions_per_run" "  questions_per_run: 3" "$BODY"
assert_has "default token" '  token: "@agentic-run"' "$BODY"

echo "[re-run] a second setup keeps the filled identity and stays valid"
bash "$CORE_LIB/derive-project-values.sh" "$ROOT" --remote "$REMOTE" > "$WORK/derived.txt"
OUT=$(bash "$CORE_LIB/write-run-config.sh" "$CONFIG" --derived "$WORK/derived.txt" 2>&1); CODE=$?
assert_eq "re-run exit 0" "0" "$CODE"
assert_eq "re-run never prints the identity" "" "$(printf '%s' "$OUT" | grep -o 'fixture-identity' || true)"
OUT=$(bash "$CORE_LIB/find-placeholders.sh" "$CONFIG"); CODE=$?
assert_eq "no placeholder re-added" "0" "$CODE"
OUT=$(bash "$CORE_LIB/validate-project-config.sh" "$CONFIG" 2>&1); CODE=$?
assert_eq "still valid" "0" "$CODE"

echo "[consumers] the platform pack's own readers accept what setup wrote"
OUT=$(bash "$SCRIPT_DIR/check-branch-length.sh" "phase-62-task-2-setup" --config "$CONFIG" 2>&1); CODE=$?
assert_eq "a 21-character branch passes the 23 limit" "0" "$CODE"
OUT=$(bash "$CORE_LIB/check-branch-name.sh" "$(printf 'b%.0s' $(seq 1 24))" --config "$CONFIG" --project-dir "$PROJECT" 2>&1); CODE=$?
assert_eq "the core's branch check refuses 24" "1" "$CODE"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
