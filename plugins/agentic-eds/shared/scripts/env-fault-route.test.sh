#!/usr/bin/env bash
# env-fault-route.test.sh — a route fixture whose draft server cannot start
# (no local CLI) ends the run blocked with the remedy, and the tree is left
# as it was. Chains the scripts the route runs at that point, in order:
# start-draft-server.sh (curl, npx and sleep stubbed first on PATH) → the
# envelope eds-verify's Report question writes → run-stage.sh's decision →
# resolve-terminal-state.sh blocked → check-tree-unchanged.sh compare.
# No model runs; the envelope is written with the emitter as the stage does.
#
# Usage:
#   bash env-fault-route.test.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACK_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CORE="$PACK_ROOT/core/lib"
START="$SCRIPT_DIR/start-draft-server.sh"

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
has() {
  local desc="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    PASS=$((PASS + 1)); echo "  ok: $desc"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: $desc"; echo "    expected to contain: $needle"; echo "    got: $haystack"
  fi
}

[[ -n "${TMPDIR:-}" ]] || { echo "TMPDIR is empty; refusing to create test directories" >&2; exit 1; }
WORK="$(mktemp -d "$TMPDIR/env-fault-route-test.XXXXXX")" || exit 1
[[ -n "$WORK" && -d "$WORK" ]] || { echo "cannot create a temp dir" >&2; exit 1; }
trap 'rm -rf "$WORK"' EXIT

# Stubs: nothing answers (curl 000), the CLI is not installed (npx exits at
# once, as `npx --no-install` does without a local install), and the poll
# ladder's waits are shortened. The one-second wait for an immediate exit is
# kept whole: shortened, it can end before the stubbed server has exited.
mkdir -p "$WORK/bin"
printf '#!/usr/bin/env bash\nprintf 000\n' > "$WORK/bin/curl"
printf '#!/usr/bin/env bash\necho "npm ERR! could not determine executable to run"\nexit 1\n' > "$WORK/bin/npx"
printf '#!/bin/sh\n[ "$1" = 1 ] && exec /bin/sleep 1\nexec /bin/sleep 0.3\n' > "$WORK/bin/sleep"
chmod +x "$WORK/bin/curl" "$WORK/bin/npx" "$WORK/bin/sleep"
export PATH="$WORK/bin:$PATH"

# The fixture project: a committed tree with the ignore rules setup writes,
# on the run's own branch.
P="$WORK/project"
git init -q -b main "$P"
git -C "$P" config user.email t@t
git -C "$P" config user.name t
mkdir -p "$P/.ai" "$P/blocks/cards"
printf '.ai/run-context/\n.ai/logs/\ndrafts/\n' > "$P/.gitignore"
printf 'version: 1\n\nbranch_name:\n  max_length: 23\n' > "$P/.ai/project-config.yaml"
printf '{ "name": "fixture", "devDependencies": {} }\n' > "$P/package.json"
printf '.cards {}\n' > "$P/blocks/cards/cards.css"
git -C "$P" add -A && git -C "$P" commit -q -m base
git -C "$P" switch -q -c ex-1

echo "=== env-fault-route.test.sh ==="

bash "$CORE/check-tree-unchanged.sh" snapshot "$P" "$WORK/tree-before.txt" >/dev/null

echo "[verify] the draft server cannot start without the local CLI"
SERVER_ERR="$(cd "$P" && bash "$START" "http://localhost:3000/" "$P/.ai/logs/draft-server.log" "$P/.ai/logs/draft-server.pid" 2>&1 >/dev/null)"; ST=$?
check "start-draft-server.sh exits 1" 1 "$ST"
has "names the start failure" "start-failed: the draft server exited immediately" "$SERVER_ERR"
START_LINE="$(printf '%s\n' "$SERVER_ERR" | grep -m1 '^start-failed: ')"

echo "[verify] the stage reports the environment fault with its class and the pack's declared remedy"
CLI_REMEDY="$(awk '/^  - tool: aem-cli$/ { f = 1 } f && /^    remedy: "/ { sub(/^    remedy: "/, ""); sub(/"$/, ""); print; exit }' "$PACK_ROOT/pack.yaml")"
has "the pack declares a remedy for the CLI" "npm install --save-dev" "$CLI_REMEDY"
ENV_FILE="$P/.ai/run-context/envelope-verify.txt"
mkdir -p "$P/.ai/run-context"
bash "$CORE/emit-envelope.sh" "$ENV_FILE" --verdict question \
  --summary "The draft server never came up, so the fixture could not be rendered." \
  --error-class TRANSIENT \
  --question "The draft server this stage needs never came up." \
  --blocker "$START_LINE; $CLI_REMEDY; then start the run again" >/dev/null
check "the envelope validates" "verdict: question" "$(bash "$CORE/validate-result-envelope.sh" "$ENV_FILE" 2>&1)"

echo "[driver] the decision is blocked, never a question to a human"
DECISION="$(bash "$CORE/run-stage.sh" "$PACK_ROOT/pack.yaml" verify "$ENV_FILE" 2>&1)"; ST=$?
check "run-stage.sh exits 4" 4 "$ST"
has "decision: terminate-blocked" "decision: terminate-blocked" "$DECISION"
REMEDY="$(printf '%s\n' "$DECISION" | sed -n 's/^remedy: //p')"
has "the remedy carries the start failure" "$START_LINE" "$REMEDY"
has "the remedy is the pack's declared one" "$CLI_REMEDY; then start the run again" "$REMEDY"

echo "[driver] the run ends blocked with that remedy"
TERMINAL="$(bash "$CORE/resolve-terminal-state.sh" blocked "$REMEDY" "nowhere — an environment fault in verify" 2>&1)"
check "the terminal line" "terminal: blocked" "$(printf '%s\n' "$TERMINAL" | head -1)"
check "the missing line is the remedy" "missing: $REMEDY" "$(printf '%s\n' "$TERMINAL" | sed -n 2p)"

echo "[tree] nothing tracked changed: no install, no package file edit"
TREE="$(bash "$CORE/check-tree-unchanged.sh" compare "$P" "$WORK/tree-before.txt" 2>&1)"; ST=$?
check "check-tree-unchanged.sh compare exits 0" 0 "$ST"
check "package.json is the committed one" "" "$(git -C "$P" status --porcelain -- package.json)"

echo ""
echo "passed: $PASS, failed: $FAIL"
[[ "$FAIL" -eq 0 ]]
