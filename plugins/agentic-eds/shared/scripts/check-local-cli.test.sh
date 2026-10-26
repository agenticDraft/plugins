#!/usr/bin/env bash
# Tests for check-local-cli.sh. Run with:
#   bash plugins/agentic-eds/shared/scripts/check-local-cli.test.sh
#
# No framework — exits 0 on success, 1 on any failure. Nothing here depends on
# what is installed on the machine running it.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/check-local-cli.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/check-local-cli.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
expect() {
  local desc="$1" want="$2" rc="$3"
  if [[ "$rc" == "$want" ]]; then PASS=$((PASS + 1)); echo "  ok: $desc"
  else FAIL=$((FAIL + 1)); echo "  FAIL: $desc (expected exit=$want, got exit=$rc)"; fi
}

echo "=== check-local-cli.sh tests ==="

mkdir -p "$WORK/installed/node_modules/.bin"
printf '#!/usr/bin/env bash\n' > "$WORK/installed/node_modules/.bin/aem"
chmod +x "$WORK/installed/node_modules/.bin/aem"
(cd "$WORK/installed" && bash "$SCRIPT"); expect "the project's own install present -> exit 0" 0 $?

mkdir -p "$WORK/absent"
(cd "$WORK/absent" && bash "$SCRIPT"); expect "no local install -> exit 1" 1 $?

mkdir -p "$WORK/noexec/node_modules/.bin"
: > "$WORK/noexec/node_modules/.bin/aem"
(cd "$WORK/noexec" && bash "$SCRIPT"); expect "a binary that cannot run -> exit 1" 1 $?

mkdir -p "$WORK/global/bin"
printf '#!/usr/bin/env bash\n' > "$WORK/global/bin/aem"; chmod +x "$WORK/global/bin/aem"
(cd "$WORK/absent" && PATH="$WORK/global/bin:$PATH" bash "$SCRIPT"); expect "a global install alone does not count -> exit 1" 1 $?

# The CLI's install is declared once, in the manifest, for the core setup
# step to offer; this pack's own setup skill no longer checks it or shows it.
PACK_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
awk '/^  - tool: aem-cli$/ { f = 1; next } f && /^  - tool: / { exit } f && /^    install: \[/ { found = 1 } END { exit !found }' \
  "$PACK_ROOT/pack.yaml"; expect "the manifest declares an install argv for aem-cli" 0 $?
! grep -q 'check-requires' "$PACK_ROOT/skills/eds-setup/SKILL.md"; expect "eds-setup no longer runs the requires check" 0 $?
bash "$PACK_ROOT/core/lib/validate-pack-manifest.sh" "$PACK_ROOT/pack.yaml" >/dev/null 2>&1; expect "the manifest still validates" 0 $?

echo
echo "=== $PASS passed, $FAIL failed ==="
(( FAIL == 0 ))
