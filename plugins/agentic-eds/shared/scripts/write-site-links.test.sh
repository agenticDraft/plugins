#!/usr/bin/env bash
# Tests for write-site-links.sh. Run with:
#   bash plugins/agentic-eds/shared/scripts/write-site-links.test.sh
#
# No framework — exits 0 on success, 1 on any failure.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/write-site-links.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/write-site-links.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
expect() {
  local desc="$1" want="$2" rc="$3" out="$4"
  if [[ "$rc" == "$want" ]]; then PASS=$((PASS + 1)); echo "  ok: $desc"
  else FAIL=$((FAIL + 1)); echo "  FAIL: $desc (expected exit=$want, got exit=$rc)"; echo "    $out"; fi
}
same() {
  local desc="$1" want="$2" got="$3"
  if [[ "$want" == "$got" ]]; then PASS=$((PASS + 1)); echo "  ok: $desc"
  else FAIL=$((FAIL + 1)); echo "  FAIL: $desc"; diff <(echo "$want") <(echo "$got") | sed 's/^/    /'; fi
}

P="$WORK/project"
git init -q "$P"
mkdir -p "$P/.ai"
config() {
  printf 'version: 1\nplatform:\n  preview_host_suffix: "--site-repo--example-org"\n%s' "$1" > "$P/.ai/project-config.yaml"
}
BLOCK_WITH='<!-- agentic-eds:site-links (written from .ai/project-config.yaml by the platform setup; edits inside are replaced) -->
## Site links

- Content editor: https://content.example.test/site-repo
- Preview: https://main--site-repo--example-org.aem.page/
- Live: https://main--site-repo--example-org.aem.live/
<!-- /agentic-eds:site-links -->'

echo "=== write-site-links.sh tests ==="

config '  content_source: "https://content.example.test/site-repo"
'
printf '# Site\n\nThe site.\n' > "$P/README.md"
OUT=$(cd "$P" && bash "$SCRIPT" 2>&1); RC=$?
expect "first write -> exit 0" 0 "$RC" "$OUT"
same "says it updated the file" "updated: README.md" "$OUT"
same "the block goes after the title, the rest is kept" "# Site

$BLOCK_WITH

The site." "$(cat "$P/README.md")"

OUT=$(cd "$P" && bash "$SCRIPT" 2>&1); RC=$?
same "a second run changes nothing" "unchanged: README.md" "$OUT"

config '  content_source: "https://content.example.test/moved"
'
OUT=$(cd "$P" && bash "$SCRIPT" 2>&1)
same "a changed config replaces the block in place" "# Site

${BLOCK_WITH//site-repo$'\n'/moved$'\n'}

The site." "$(cat "$P/README.md")"

config ''
rm "$P/README.md"
OUT=$(cd "$P" && bash "$SCRIPT" 2>&1); RC=$?
expect "no README -> created, exit 0" 0 "$RC" "$OUT"
same "says it created the file" "created: README.md" "$OUT"
same "without content_source the editor line says so" '<!-- agentic-eds:site-links (written from .ai/project-config.yaml by the platform setup; edits inside are replaced) -->
## Site links

- Content editor: not configured (platform.content_source)
- Preview: https://main--site-repo--example-org.aem.page/
- Live: https://main--site-repo--example-org.aem.live/
<!-- /agentic-eds:site-links -->' "$(cat "$P/README.md")"

printf 'No title here.\n' > "$P/README.md"
OUT=$(cd "$P" && bash "$SCRIPT" 2>&1)
same "no title -> the block goes first" "$(printf '%s\n\nNo title here.' "$(cat <<'EOF'
<!-- agentic-eds:site-links (written from .ai/project-config.yaml by the platform setup; edits inside are replaced) -->
## Site links

- Content editor: not configured (platform.content_source)
- Preview: https://main--site-repo--example-org.aem.page/
- Live: https://main--site-repo--example-org.aem.live/
<!-- /agentic-eds:site-links -->
EOF
)")" "$(cat "$P/README.md")"

printf 'version: 1\n' > "$P/.ai/project-config.yaml"
OUT=$(cd "$P" && bash "$SCRIPT" 2>&1); RC=$?
expect "no suffix in the config -> exit 1, nothing written" 1 "$RC" "$OUT"

config '  content_source: "javascript:alert(1)"
'
OUT=$(cd "$P" && bash "$SCRIPT" 2>&1); RC=$?
expect "a content_source that is not an https URL -> exit 1" 1 "$RC" "$OUT"

echo
echo "=== $PASS passed, $FAIL failed ==="
(( FAIL == 0 ))
