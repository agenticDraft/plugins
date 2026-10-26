#!/usr/bin/env bash
# Tests for check-getting-started.sh. Run with:
#   bash scripts/check-getting-started.test.sh
#
# No framework — exits 0 on success, 1 on any failure.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
CHECK="$SCRIPT_DIR/check-getting-started.sh"
RENDER="$SCRIPT_DIR/render-guide-declarations.sh"
FIX="$REPO/plugins/agentic-core/shared/fixtures"

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
WORK="$(mktemp -d "$TMPDIR/check-getting-started-test.XXXXXX")" || exit 1
trap 'rm -rf "$WORK"' EXIT

ROOT="$WORK/repo"
mkdir -p "$ROOT/plugins/agentic-core/shared"
cp "$REPO/plugins/agentic-core/shared/run-paths.txt" "$ROOT/plugins/agentic-core/shared/run-paths.txt"
cp -R "$FIX/pack-manifest/platform-valid" "$ROOT/plugins/agentic-eds"
cp -R "$FIX/pack-manifest/provider-valid" "$ROOT/plugins/agentic-jira"
cat >> "$ROOT/plugins/agentic-eds/pack.yaml" <<'EOF'
hosts: ["*.example-preview.test"]
EOF
cat >> "$ROOT/plugins/agentic-jira/pack.yaml" <<'EOF'
env:
  - name: EXAMPLE_SITE
    source: "the host of your tracker"
  - name: EXAMPLE_TOKEN
    source: "a token"
hosts: ["*.example-tracker.test"]
EOF

GUIDE="$ROOT/plugins/getting-started.md"
printf '# Guide\n\nintro\n\n<!-- guide-declarations:begin -->\nold\n<!-- guide-declarations:end -->\n\noutro\n' > "$GUIDE"
bash "$RENDER" --root "$ROOT" --write "$GUIDE" >/dev/null 2>&1 || { echo "setup: render failed" >&2; exit 1; }

echo "[valid] a guide whose block is fresh and names every declared variable and host"
OUT=$(bash "$CHECK" --root "$ROOT" 2>&1); ST=$?
assert_eq "exit 0" 0 "$ST"
assert_contains "valid line with counts" "valid: getting-started (2 packs, 2 variables, 2 hosts)" "$OUT"

echo "[stale] a pack declares a new host after the block was rendered"
sed -i.bak 's/^hosts: \["\*.example-tracker.test"\]$/hosts: ["*.example-tracker.test", "*.new.test"]/' "$ROOT/plugins/agentic-jira/pack.yaml"; rm -f "$ROOT/plugins/agentic-jira/pack.yaml.bak"
OUT=$(bash "$CHECK" --root "$ROOT" 2>&1); ST=$?
assert_eq "exit 1" 1 "$ST"
assert_contains "names the stale block" "stale: the generated block differs from the packs' declarations" "$OUT"
assert_contains "names the way to refresh it" "render-guide-declarations.sh --write" "$OUT"
assert_contains "names the missing host" "missing: host *.new.test" "$OUT"

echo "[stale] a hand edit inside the block"
sed -i.bak 's/, "\*.new.test"//' "$ROOT/plugins/agentic-jira/pack.yaml"; rm -f "$ROOT/plugins/agentic-jira/pack.yaml.bak"
bash "$RENDER" --root "$ROOT" --write "$GUIDE" >/dev/null 2>&1
sed -i.bak 's/`EXAMPLE_TOKEN` — a token/`EXAMPLE_TOKEN` — a different text/' "$GUIDE"; rm -f "$GUIDE.bak"
OUT=$(bash "$CHECK" --root "$ROOT" 2>&1); ST=$?
assert_eq "exit 1" 1 "$ST"
assert_contains "names the stale block" "stale:" "$OUT"
bash "$RENDER" --root "$ROOT" --write "$GUIDE" >/dev/null 2>&1

echo "[names-only] a declared variable or host the guide does not name"
printf '# Guide\n\nonly prose\n\n<!-- guide-declarations:begin -->\n<!-- guide-declarations:end -->\n' > "$WORK/bare.md"
cp "$WORK/bare.md" "$GUIDE"
OUT=$(bash "$CHECK" --root "$ROOT" --names-only 2>&1); ST=$?
assert_eq "exit 1" 1 "$ST"
assert_contains "a missing variable" "missing: variable EXAMPLE_SITE" "$OUT"
assert_contains "the other missing variable" "missing: variable EXAMPLE_TOKEN" "$OUT"
assert_contains "a missing host" 'missing: host *.example-tracker.test' "$OUT"
assert_contains "the platform host" 'missing: host *.example-preview.test' "$OUT"

echo "[refused] a guide with no markers, no guide, a missing flag value"
printf '# Guide\n' > "$GUIDE"
bash "$CHECK" --root "$ROOT" >/dev/null 2>&1; assert_eq "no markers: exit 2" 2 "$?"
rm -f "$GUIDE"
bash "$CHECK" --root "$ROOT" >/dev/null 2>&1; assert_eq "no guide: exit 2" 2 "$?"
bash "$CHECK" --root >/dev/null 2>&1; assert_eq "--root without a value: exit 2" 2 "$?"

echo "[this repository] the shipped guide passes"
OUT=$(bash "$CHECK" 2>&1); ST=$?
assert_eq "exit 0" 0 "$ST"
assert_contains "valid line" "valid: getting-started" "$OUT"

echo
echo "pass=$PASS fail=$FAIL"
[[ "$FAIL" -eq 0 ]]
