#!/usr/bin/env bash
# Tests for check-instruction-hosts.sh. Run with:
#   bash plugins/agentic-eds/shared/scripts/check-instruction-hosts.test.sh
#
# No framework — exits 0 on success, 1 on any failure.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/check-instruction-hosts.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/check-instruction-hosts.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
expect() {
  local desc="$1" want="$2" rc="$3" out="$4"
  if [[ "$rc" == "$want" ]]; then PASS=$((PASS + 1)); echo "  ok: $desc"
  else FAIL=$((FAIL + 1)); echo "  FAIL: $desc (expected exit=$want, got exit=$rc)"; echo "    $out"; fi
}
has() {
  local desc="$1" needle="$2" out="$3"
  if [[ "$out" == *"$needle"* ]]; then PASS=$((PASS + 1)); echo "  ok: $desc"
  else FAIL=$((FAIL + 1)); echo "  FAIL: $desc"; echo "    expected: $needle"; echo "    got: $out"; fi
}
lacks() {
  local desc="$1" needle="$2" out="$3"
  if [[ "$out" != *"$needle"* ]]; then PASS=$((PASS + 1)); echo "  ok: $desc"
  else FAIL=$((FAIL + 1)); echo "  FAIL: $desc"; echo "    unexpected: $needle"; echo "    got: $out"; fi
}

P="$WORK/project"
git init -q "$P"
mkdir -p "$P/.ai" "$P/docs"
printf 'version: 1\nplatform:\n  preview_host_suffix: "--site-repo--new-owner"\n' > "$P/.ai/project-config.yaml"
cat > "$P/README.md" <<'EOF'
# Site
- Preview: https://main--Site-Repo--New-Owner.aem.page/
- Live: https://main--site-repo--old-owner.aem.live/
- Docs: https://www.aem.live/docs/
EOF
cat > "$P/AGENTS.md" <<'EOF'
Placeholder form: {branch}--{repo}--{owner}.aem.page
- A PR without a `{branch}--site-repo--old-owner.aem.page/{path}` link is rejected.
EOF
printf 'https://main--site-repo--old-owner.aem.page/\n' > "$P/docs/nested.md"
printf 'https://main--site-repo--old-owner.aem.page/\n' > "$P/untracked.md"
git -C "$P" add README.md AGENTS.md docs/nested.md .ai/project-config.yaml

echo "=== check-instruction-hosts.sh tests ==="

OUT=$(cd "$P" && bash "$SCRIPT" 2>&1); RC=$?
expect "a stale host in a tracked root instruction file -> exit 1" 1 "$RC" "$OUT"
has "flags the stale live host with file and line" "stale: README.md:3 main--site-repo--old-owner.aem.live — the config's suffix is --site-repo--new-owner" "$OUT"
has "flags the stale host in AGENTS.md" "stale: AGENTS.md:2 {branch}--site-repo--old-owner.aem.page" "$OUT"
lacks "a host matching the suffix in another case is not flagged" "README.md:2" "$OUT"
lacks "the placeholder form is not flagged" "AGENTS.md:1" "$OUT"
lacks "a documentation host is not flagged" "www.aem.live" "$OUT"
lacks "a nested file is not read" "docs/nested.md" "$OUT"
lacks "an untracked file is not read" "untracked.md" "$OUT"

printf '# Site\n- Preview: https://main--site-repo--new-owner.aem.page/\n' > "$P/README.md"
printf 'Placeholder form: {branch}--{repo}--{owner}.aem.page\n' > "$P/AGENTS.md"
OUT=$(cd "$P" && bash "$SCRIPT" 2>&1); RC=$?
expect "every host agrees -> exit 0" 0 "$RC" "$OUT"
has "says how many files it read" "ok: no stale preview or live host in 2 tracked root .md files" "$OUT"

printf 'version: 1\n' > "$P/.ai/project-config.yaml"
OUT=$(cd "$P" && bash "$SCRIPT" 2>&1); RC=$?
expect "no suffix in the config -> exit 2" 2 "$RC" "$OUT"

echo
echo "=== $PASS passed, $FAIL failed ==="
(( FAIL == 0 ))
