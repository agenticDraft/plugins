#!/usr/bin/env bash
# deliver-working-paths.test.sh — deliver on a branch with drafts/ present:
# the pull request's files exclude it. The project has no ignore rule for
# drafts/ (the state the run met in a project setup had not yet written), so
# only the pack's declaration keeps the fixture out. Chains the scripts the
# route runs, in order: write-working-paths.sh (this pack's real manifest,
# resolved through the plugin registry) → check-publish-criteria.sh →
# commit-change.sh → the scm pack's publish-change.sh (gh stubbed, origin a
# local bare repository) → the files of the pushed branch.
#
# Usage:
#   bash deliver-working-paths.test.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACK_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CORE="$PACK_ROOT/core/lib"

PASS=0
FAIL=0
check() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    PASS=$((PASS + 1)); echo "  ok: $desc"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: $desc"; echo "    expected: $expected"; echo "    actual:   $actual"
  fi
}

[[ -n "${TMPDIR:-}" ]] || { echo "TMPDIR is empty; refusing to create test directories" >&2; exit 1; }
WORK="$(mktemp -d "$TMPDIR/deliver-working-paths-test.XXXXXX")" || exit 1
[[ -n "$WORK" && -d "$WORK" ]] || { echo "cannot create a temp dir" >&2; exit 1; }
trap 'rm -rf "$WORK"' EXIT

# A gh with no open pull request, whose `pr create` succeeds.
mkdir -p "$WORK/bin"
cat > "$WORK/bin/gh" <<'GH'
#!/usr/bin/env bash
case "${1:-} ${2:-}" in
  "auth status") exit 0 ;;
  "repo view") echo main ;;
  "pr list") exit 0 ;;
  "pr create") echo "https://example.invalid/pull/1" ;;
  "pr view") echo '{}' ;;
  *) exit 1 ;;
esac
GH
chmod +x "$WORK/bin/gh"
export PATH="$WORK/bin:$PATH"

# The project: origin is a local bare repository; .gitignore covers the run
# context but not drafts/.
git init -q --bare --initial-branch=main "$WORK/origin.git"
P="$WORK/project"
git clone -q "$WORK/origin.git" "$P" 2>/dev/null
git -C "$P" config user.email t@t
git -C "$P" config user.name t
mkdir -p "$P/.ai" "$P/blocks/cards"
printf '.ai/run-context/\n' > "$P/.gitignore"
printf '.cards {}\n' > "$P/blocks/cards/cards.css"
cat > "$P/.ai/project-config.yaml" <<'EOF'
version: 1

packs:
  platform: agentic-eds
  scm: agentic-github
EOF
git -C "$P" add -A && git -C "$P" commit -q -m base && git -C "$P" push -q origin HEAD:main
git -C "$P" remote set-head origin main >/dev/null
git -C "$P" switch -q -c ex-1

. "$CORE/register-source-tree.sh"
register_source_tree "$P" || { echo "the source tree's plugins could not be registered" >&2; exit 1; }

# The run's change, and its fixture.
printf '.cards { gap: 1rem; }\n' > "$P/blocks/cards/cards.css"
mkdir -p "$P/drafts"
printf '<div class="cards"><div><div></div></div></div>\n' > "$P/drafts/EX-1.plain.html"
printf '<svg/>\n' > "$P/drafts/EX-1-fixture-image.svg"

echo "=== deliver-working-paths.test.sh ==="

echo "[driver] the working paths file names this pack's drafts/"
WP="$P/.ai/run-context/working-paths.txt"
OUT="$(bash "$CORE/write-working-paths.sh" "$P/.ai/project-config.yaml" "$WP" --project-dir "$P" 2>&1)"; ST=$?
check "write-working-paths.sh exits 0" 0 "$ST"
check "drafts/ is listed" "drafts/" "$(grep -x 'drafts/' "$WP")"

echo "[publish-gate] the change under review is the block, not the fixture"
OUT="$(bash "$CORE/check-publish-criteria.sh" "$P" --exclude-file "$WP" 2>&1)"; ST=$?
check "exit 0" 0 "$ST"
check "one file" "valid: publish (1 files changed)" "$OUT"

echo "[deliver] the commit leaves the fixture out"
OUT="$(bash "$CORE/commit-change.sh" "$P" "EX-1 cards gap" --exclude-file "$WP" 2>&1)"; ST=$?
check "commit-change.sh exits 0" 0 "$ST"
check "both fixture files are named as left out" 'left-out: drafts/EX-1-fixture-image.svg
left-out: drafts/EX-1.plain.html' "$(printf '%s\n' "$OUT" | grep '^left-out: ' | sort)"

echo "[deliver] publish_change pushes the branch; its files exclude drafts/"
printf 'Item: EX-1 (Story)\n' > "$WORK/body.md"
SCM_ROOT="$(bash "$CORE/resolve-plugin-root.sh" agentic-github --project-dir "$P")"
OUT="$(cd "$P" && bash "$SCM_ROOT/skills/publish-change/scripts/publish-change.sh" ex-1 "EX-1 cards gap" "$WORK/body.md" 2>&1)"
check "publish_change passes" "verdict: pass" "$(printf '%s\n' "$OUT" | grep -m1 '^verdict: ')"
PR_FILES="$(git --git-dir="$WORK/origin.git" diff --name-status main ex-1 | cut -f2)"
check "the pull request's files are the block only" "blocks/cards/cards.css" "$PR_FILES"

echo ""
echo "passed: $PASS, failed: $FAIL"
[[ "$FAIL" -eq 0 ]]
