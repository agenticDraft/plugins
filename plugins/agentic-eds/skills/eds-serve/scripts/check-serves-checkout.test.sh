#!/usr/bin/env bash
# check-serves-checkout.test.sh — the checkout probe, with `curl` stubbed first
# on PATH. The stub plays a server: it serves files from $STUB_ROOT, answers
# $STUB_STATUS when that is set, and records its arguments.
#
# Usage:
#   bash check-serves-checkout.test.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SCRIPT_DIR/check-serves-checkout.sh"

PASS=0
FAIL=0

ok()  { echo "  ok: $1"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "    $2"; FAIL=$((FAIL + 1)); }

assert_eq()    { if [ "$2" == "$3" ]; then ok "$1"; else bad "$1" "expected: $2 — got: $3"; fi; }
assert_has()   { if [[ "$3" == *"$2"* ]]; then ok "$1"; else bad "$1" "expected to contain: $2 — got: $3"; fi; }
assert_lacks() { if [[ "$3" != *"$2"* ]]; then ok "$1"; else bad "$1" "expected not to contain: $2 — got: $3"; fi; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/check-serves-checkout.XXXXXX") || { echo "cannot create a temp dir" >&2; exit 2; }
[ -n "$WORK" ] && [ -d "$WORK" ] || { echo "cannot create a temp dir" >&2; exit 2; }
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/bin" "$WORK/checkout" "$WORK/other"
cat > "$WORK/bin/curl" <<'STUB'
#!/usr/bin/env bash
printf '[%s]' "$@" >> "$STUB_CALLS"; echo >> "$STUB_CALLS"
OUT=""
while [ $# -gt 1 ]; do
  [ "$1" == "-o" ] && OUT="$2"
  shift
done
URL="$1"
if [ -n "${STUB_STATUS:-}" ]; then printf '%s' "$STUB_STATUS"; exit 0; fi
FILE="$STUB_ROOT/${URL#*://*/}"
if [ -f "$FILE" ]; then cat "$FILE" > "$OUT"; printf 200; else printf 404; fi
STUB
chmod +x "$WORK/bin/curl"
export PATH="$WORK/bin:$PATH"
export STUB_CALLS="$WORK/curl-calls"

run() { OUT=$(env -u HTTP_PROXY -u http_proxy "$@" bash "$CHECK" "$URL" "$WORK/checkout" 2>&1); CODE=$?; }

URL="http://localhost:3000/drafts/table?x=1#top"

echo "[match] the server serves this checkout"
rm -f "$STUB_CALLS"
run STUB_ROOT="$WORK/checkout"
assert_eq "exit 0" "0" "$CODE"
assert_has "names the origin" "serves-checkout: origin=http://localhost:3000 root=$WORK/checkout" "$OUT"
assert_has "probe fetched at the origin, path and query dropped" "[http://localhost:3000/.ai/run-context/serve-probe.txt]" "$(cat "$STUB_CALLS")"
assert_eq "probe file removed afterwards" "no" "$([ -e "$WORK/checkout/.ai/run-context/serve-probe.txt" ] && echo yes || echo no)"
assert_lacks "no proxy in the environment: no --noproxy" "--noproxy" "$(cat "$STUB_CALLS")"

echo "[foreign] the server serves another directory"
run STUB_ROOT="$WORK/other"
assert_eq "exit 1" "1" "$CODE"
assert_has "says it does not serve this checkout" "foreign: http://localhost:3000 answered status=404" "$OUT"
assert_has "names the root" "does not serve $WORK/checkout" "$OUT"

echo "[foreign] another directory holding an old probe of its own"
mkdir -p "$WORK/other/.ai/run-context"
printf 'stale-nonce' > "$WORK/other/.ai/run-context/serve-probe.txt"
run STUB_ROOT="$WORK/other"
assert_eq "exit 1" "1" "$CODE"
assert_has "a 200 without this run's nonce is foreign" "foreign: http://localhost:3000 answered status=200" "$OUT"

echo "[no answer] the server went away"
run STUB_ROOT="$WORK/checkout" STUB_STATUS=000
assert_eq "exit 1" "1" "$CODE"
assert_has "says nothing answered" "no-answer:" "$OUT"

echo "[proxy] with a proxy in the environment, the probe goes through it"
rm -f "$STUB_CALLS"
OUT=$(STUB_ROOT="$WORK/checkout" HTTP_PROXY="http://localhost:3128" bash "$CHECK" "$URL" "$WORK/checkout" 2>&1); CODE=$?
assert_eq "exit 0" "0" "$CODE"
assert_has "curl told to proxy every host" "[--noproxy][]" "$(cat "$STUB_CALLS")"

echo "[usage] missing arguments, a URL without an origin, a missing root"
OUT=$(bash "$CHECK" 2>&1); CODE=$?
assert_eq "no arguments: exit 2" "2" "$CODE"
OUT=$(bash "$CHECK" "localhost:3000" "$WORK/checkout" 2>&1); CODE=$?
assert_eq "no scheme: exit 2" "2" "$CODE"
OUT=$(bash "$CHECK" "$URL" "$WORK/missing" 2>&1); CODE=$?
assert_eq "missing root: exit 2" "2" "$CODE"

echo "=== $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
