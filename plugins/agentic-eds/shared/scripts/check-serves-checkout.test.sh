#!/usr/bin/env bash
# check-serves-checkout.test.sh — the checkout probe, with `curl` and `lsof`
# stubbed first on PATH. The curl stub plays a server: it serves files from
# $STUB_ROOT, answers $STUB_STATUS when that is set, and records its
# arguments. The lsof stub names $STUB_PID and $STUB_CWD as the listener when
# they are set, and nothing otherwise.
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

mkdir -p "$WORK/bin" "$WORK/lsofbin" "$WORK/checkout" "$WORK/other"
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
cat > "$WORK/lsofbin/lsof" <<'STUB'
#!/usr/bin/env bash
[ -n "${STUB_PID:-}" ] || exit 1
case " $* " in
  *" -t "*) echo "$STUB_PID"; echo "$STUB_PID" ;;
  *" cwd "*) [ -n "${STUB_CWD:-}" ] && printf 'p%s\nfcwd\nn%s\n' "$STUB_PID" "$STUB_CWD" ;;
esac
exit 0
STUB
chmod +x "$WORK/bin/curl" "$WORK/lsofbin/lsof"
export STUB_CALLS="$WORK/curl-calls"
STUBBED_PATH="$WORK/bin:$WORK/lsofbin:/usr/bin:/bin"
NO_LSOF_PATH="$WORK/bin:/usr/bin:/bin"

URL="http://localhost:3000/drafts/table?x=1#top"
STARTED=no

# Runs the check with the stubs on PATH and the given env assignments;
# sets OUT, CODE and SUMMARY (the text after "summary: ").
run() {
  OUT=$(env -u HTTP_PROXY -u http_proxy PATH="$STUBBED_PATH" "$@" bash "$CHECK" "$URL" "$WORK/checkout" "$STARTED" 2>&1); CODE=$?
  SUMMARY="$(printf '%s\n' "$OUT" | sed -n 's/^summary: //p')"
}
assert_fits() { if (( ${#SUMMARY} > 0 && ${#SUMMARY} <= 200 )); then ok "$1"; else bad "$1" "summary is ${#SUMMARY} characters: $SUMMARY"; fi; }

echo "[match] the server serves this checkout"
rm -f "$STUB_CALLS"
run STUB_ROOT="$WORK/checkout"
assert_eq "exit 0" "0" "$CODE"
assert_has "names the origin" "serves-checkout: origin=http://localhost:3000 root=$WORK/checkout" "$OUT"
assert_has "probe fetched at the origin, path and query dropped" "[http://localhost:3000/.ai/run-context/serve-probe.txt]" "$(cat "$STUB_CALLS")"
assert_eq "probe file removed afterwards" "no" "$([ -e "$WORK/checkout/.ai/run-context/serve-probe.txt" ] && echo yes || echo no)"
assert_lacks "no proxy in the environment: no --noproxy" "--noproxy" "$(cat "$STUB_CALLS")"
assert_lacks "no summary on success" "summary:" "$OUT"

echo "[foreign] a server this run did not start, listener named in full"
run STUB_ROOT="$WORK/other" STUB_PID=4321 STUB_CWD=/srv/old
assert_eq "exit 1" "1" "$CODE"
assert_has "reason line" "reason: foreign" "$OUT"
assert_has "detail names the status and root" "answered status=404 without this run's nonce" "$OUT"
assert_has "listener line" "listener: pid=4321 cwd=/srv/old" "$OUT"
assert_has "summary names origin, pid and directory" "Server at http://localhost:3000 (pid 4321, serving /srv/old)" "$SUMMARY"
assert_has "summary says what to do" "stop it (kill 4321) or point paths.preview at this checkout's server, then rerun." "$SUMMARY"
assert_fits "summary fits the envelope"
assert_eq "probe file removed after a failure too" "no" "$([ -e "$WORK/checkout/.ai/run-context/serve-probe.txt" ] && echo yes || echo no)"

echo "[foreign] a directory too long for the summary is dropped from it, kept on the listener line"
LONG_CWD="/Users/someone/projects/$(printf 'a%.0s' {1..90})/checkout"
run STUB_ROOT="$WORK/other" STUB_PID=4321 STUB_CWD="$LONG_CWD"
assert_has "listener line keeps the directory" "listener: pid=4321 cwd=$LONG_CWD" "$OUT"
assert_lacks "summary drops the directory" "serving" "$SUMMARY"
assert_has "summary keeps the pid and the action" "(pid 4321) does not serve this checkout and was not started by this run; stop it (kill 4321)" "$SUMMARY"
assert_fits "summary fits the envelope"

echo "[foreign] a pid without a directory names only the pid"
run STUB_ROOT="$WORK/other" STUB_PID=4321
assert_has "listener line" "listener: pid=4321 cwd=unknown" "$OUT"
assert_lacks "no unknown in the summary" "unknown" "$SUMMARY"
assert_has "summary keeps the pid" "(pid 4321)" "$SUMMARY"

echo "[foreign] lsof not installed: the summary names the port"
OUT=$(env -u HTTP_PROXY -u http_proxy PATH="$NO_LSOF_PATH" STUB_ROOT="$WORK/other" bash "$CHECK" "http://localhost:39871/x" "$WORK/checkout" no 2>&1); CODE=$?
SUMMARY="$(printf '%s\n' "$OUT" | sed -n 's/^summary: //p')"
assert_eq "exit 1" "1" "$CODE"
assert_has "listener unknown" "listener: pid=unknown cwd=unknown" "$OUT"
assert_has "summary names the port" "stop what listens on port 39871" "$SUMMARY"
assert_fits "summary fits the envelope"

echo "[foreign] https with no port: the default port"
OUT=$(env -u HTTP_PROXY -u http_proxy PATH="$STUBBED_PATH" STUB_ROOT="$WORK/other" bash "$CHECK" "https://dev.local/page" "$WORK/checkout" no 2>&1)
assert_has "port 443" "port 443" "$OUT"

echo "[foreign] another directory holding an old probe of its own"
mkdir -p "$WORK/other/.ai/run-context"
printf 'stale-nonce' > "$WORK/other/.ai/run-context/serve-probe.txt"
run STUB_ROOT="$WORK/other"
assert_eq "exit 1" "1" "$CODE"
assert_has "a 200 without this run's nonce is foreign" "answered status=200 without this run's nonce" "$OUT"

echo "[foreign] a server this run started: the serve command is the cause"
STARTED=yes
run STUB_ROOT="$WORK/other" STUB_PID=777 STUB_CWD=/srv/elsewhere
assert_has "summary blames commands.serve" "commands.serve started a server at http://localhost:3000 (pid 777, serving /srv/elsewhere)" "$SUMMARY"
assert_has "summary says what to do" "make it serve the project root, stop it (kill 777), then rerun." "$SUMMARY"
assert_fits "summary fits the envelope"
STARTED=no

echo "[no answer] the server went away"
run STUB_ROOT="$WORK/checkout" STUB_STATUS=000
assert_eq "exit 1" "1" "$CODE"
assert_has "reason line" "reason: no-answer" "$OUT"
assert_has "summary: start this checkout's server" "stopped answering during the checkout check; start this checkout's server there" "$SUMMARY"
STARTED=yes
run STUB_ROOT="$WORK/checkout" STUB_STATUS=000
assert_has "started here: summary points at the serve log" "see .ai/run-context/serve.log" "$SUMMARY"
assert_fits "summary fits the envelope"
STARTED=no

echo "[probe] the probe file cannot be written"
mkdir -p "$WORK/readonly"
printf 'not a directory' > "$WORK/readonly/.ai"
OUT=$(env -u HTTP_PROXY -u http_proxy PATH="$STUBBED_PATH" STUB_ROOT="$WORK/readonly" bash "$CHECK" "$URL" "$WORK/readonly" no 2>&1); CODE=$?
SUMMARY="$(printf '%s\n' "$OUT" | sed -n 's/^summary: //p')"
assert_eq "exit 2" "2" "$CODE"
assert_has "reason line" "reason: probe-unwritable" "$OUT"
assert_has "summary says what to do" "make .ai/run-context writable, then rerun." "$SUMMARY"
assert_fits "summary fits the envelope"

echo "[proxy] with a proxy in the environment, the probe goes through it"
rm -f "$STUB_CALLS"
OUT=$(PATH="$STUBBED_PATH" STUB_ROOT="$WORK/checkout" HTTP_PROXY="http://localhost:3128" bash "$CHECK" "$URL" "$WORK/checkout" no 2>&1); CODE=$?
assert_eq "exit 0" "0" "$CODE"
assert_has "curl told to proxy every host" "[--noproxy][]" "$(cat "$STUB_CALLS")"

echo "[draft] the draft server: the remedy is freeing the derived port, never paths.preview"
OUT=$(env -u HTTP_PROXY -u http_proxy PATH="$STUBBED_PATH" STUB_ROOT="$WORK/other" STUB_PID=555 STUB_CWD=/srv/old bash "$CHECK" "http://localhost:3001" "$WORK/checkout" no draft 2>&1); CODE=$?
SUMMARY="$(printf '%s\n' "$OUT" | sed -n 's/^summary: //p')"
assert_eq "exit 1" "1" "$CODE"
assert_has "names the port, pid and directory" "Draft server port 3001 is held by pid 555 (serving /srv/old)" "$SUMMARY"
assert_has "says what to do" "stop it (kill 555), then rerun so a draft server starts from this checkout." "$SUMMARY"
assert_lacks "never paths.preview" "paths.preview" "$SUMMARY"
assert_lacks "never commands.serve" "commands.serve" "$SUMMARY"
assert_fits "summary fits the envelope"
OUT=$(env -u HTTP_PROXY -u http_proxy PATH="$NO_LSOF_PATH" STUB_ROOT="$WORK/other" bash "$CHECK" "http://localhost:39873" "$WORK/checkout" yes draft 2>&1)
SUMMARY="$(printf '%s\n' "$OUT" | sed -n 's/^summary: //p')"
assert_has "no pid: names the port" "stop what listens on port 39873, then rerun" "$SUMMARY"
OUT=$(env -u HTTP_PROXY -u http_proxy PATH="$STUBBED_PATH" STUB_ROOT="$WORK/checkout" STUB_STATUS=000 bash "$CHECK" "http://localhost:3001" "$WORK/checkout" yes draft 2>&1)
SUMMARY="$(printf '%s\n' "$OUT" | sed -n 's/^summary: //p')"
assert_has "started here, gone: the draft server's log" "see .ai/logs/draft-server.log, then rerun." "$SUMMARY"
OUT=$(env -u HTTP_PROXY -u http_proxy PATH="$STUBBED_PATH" STUB_ROOT="$WORK/checkout" bash "$CHECK" "http://localhost:3001" "$WORK/checkout" no draft 2>&1); CODE=$?
assert_eq "the draft server serving this checkout: exit 0" "0" "$CODE"

echo "[usage] missing arguments, a bad started value, a URL without an origin, a missing root"
OUT=$(bash "$CHECK" 2>&1); CODE=$?
assert_eq "no arguments: exit 2" "2" "$CODE"
OUT=$(bash "$CHECK" "$URL" "$WORK/checkout" 2>&1); CODE=$?
assert_eq "no started value: exit 2" "2" "$CODE"
OUT=$(bash "$CHECK" "$URL" "$WORK/checkout" maybe 2>&1); CODE=$?
assert_eq "started not yes or no: exit 2" "2" "$CODE"
OUT=$(bash "$CHECK" "$URL" "$WORK/checkout" no other 2>&1); CODE=$?
assert_eq "server not preview or draft: exit 2" "2" "$CODE"
OUT=$(bash "$CHECK" "localhost:3000" "$WORK/checkout" no 2>&1); CODE=$?
assert_eq "no scheme: exit 2" "2" "$CODE"
OUT=$(bash "$CHECK" "$URL" "$WORK/missing" no 2>&1); CODE=$?
assert_eq "missing root: exit 2" "2" "$CODE"

echo "=== $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
