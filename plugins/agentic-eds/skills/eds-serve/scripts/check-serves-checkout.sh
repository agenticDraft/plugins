#!/usr/bin/env bash
# check-serves-checkout.sh — Deterministic check that the server answering at
# a preview URL serves this checkout, not some other directory. No model
# involved.
#
# A poll only says that something is bound to the origin. A server left
# running from another checkout, another worktree or another project answers
# the same way, and every later stage would then render and measure code this
# run never wrote. This script settles which directory the server serves: it
# writes a one-off nonce file into this checkout, fetches it through the
# server, and deletes it again. Only a server whose project directory is this
# checkout can return the nonce. A server that serves files from disk serves
# them as they are now, so a match also means it serves this checkout's
# current files, whatever branch they belong to.
#
# The probe path sits under `.ai/run-context/`, the run's own scratch
# directory. The serve command's local file handling serves dotfiles and
# serves a non-HTML file unchanged, falling back to its upstream only when
# the file is missing — so a missing nonce means another directory, never a
# transformed one.
#
# When the check fails, the run stops on this stage, and the driver shows the
# human nothing but the stage's one-sentence summary. So the script names
# what holds the port — the listening process id and its working directory,
# through `lsof` when it is installed — and builds that summary itself: what
# is wrong, which process, and what to do, within the envelope's 200
# characters. Detail that does not fit is dropped from the summary, never
# from the `listener:` line the report keeps.
#
# One request, no ladder: the caller has already seen the origin answer.
#
# Usage:
#   check-serves-checkout.sh <preview-url> <project-root> <started-here: yes|no>
#
# Output on success: one line,
#   serves-checkout: origin=<origin> root=<project-root>
#
# Output on a failed check (exit 1, or exit 2 for an unwritable probe), four
# lines:
#   reason: foreign | no-answer | probe-unwritable
#   detail: <what happened>
#   listener: pid=<pid|unknown> cwd=<path|unknown>
#   summary: <one sentence, 200 characters or fewer, for the envelope>
#
# Exit codes:
#   0 — the server returned the nonce; it serves this checkout
#   1 — the server did not return the nonce
#   2 — the probe file could not be written (the four lines above), or a
#       usage error (stderr only)

set -uo pipefail

URL="${1:-}"
ROOT="${2:-}"
STARTED="${3:-}"
PROBE_PATH=".ai/run-context/serve-probe.txt"
REPORT_PATH=".ai/run-context/serve-report.md"
SUMMARY_MAX=200

if [[ -z "$URL" || -z "$ROOT" || ( "$STARTED" != "yes" && "$STARTED" != "no" ) ]]; then
  echo "usage: check-serves-checkout.sh <preview-url> <project-root> <started-here: yes|no>" >&2
  exit 2
fi

if [[ ! "$URL" =~ ^(([A-Za-z][A-Za-z0-9+.-]*)://([^/?#]+)) ]]; then
  echo "not a URL with an origin: $URL" >&2
  exit 2
fi
ORIGIN="${BASH_REMATCH[1]}"
SCHEME="$(printf '%s' "${BASH_REMATCH[2]}" | tr '[:upper:]' '[:lower:]')"
AUTHORITY="${BASH_REMATCH[3]}"
if [[ "$AUTHORITY" =~ :([0-9]+)$ ]]; then
  PORT="${BASH_REMATCH[1]}"
elif [[ "$SCHEME" == "https" ]]; then
  PORT=443
else
  PORT=80
fi

if [[ ! -d "$ROOT" ]]; then
  echo "no such project root: $ROOT" >&2
  exit 2
fi

# The process listening on the port, and its working directory — the
# directory a dev server serves from. `unknown` when lsof is missing or
# finds nothing; the summary then names the port instead of a process.
find_listener() {
  PID=unknown
  CWD=unknown
  command -v lsof >/dev/null 2>&1 || return 0
  local found
  found="$(lsof -nP -iTCP:"$PORT" -sTCP:LISTEN -t 2>/dev/null | head -1)"
  [[ "$found" =~ ^[0-9]+$ ]] || return 0
  PID="$found"
  found="$(lsof -a -p "$PID" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -1)"
  [[ -n "$found" ]] && CWD="$found"
  return 0
}

# Print the first candidate that fits the envelope's summary cap; the last
# candidate is cut to the cap if even it does not fit.
pick_summary() {
  local candidate
  for candidate in "$@"; do
    if (( ${#candidate} <= SUMMARY_MAX )); then
      printf '%s' "$candidate"
      return
    fi
  done
  printf '%s' "${candidate:0:SUMMARY_MAX}"
}

# reason, detail, then the summary candidates, most detailed first.
report_failure() {
  local reason="$1" detail="$2"
  shift 2
  echo "reason: $reason"
  echo "detail: $detail"
  echo "listener: pid=$PID cwd=$CWD"
  echo "summary: $(pick_summary "$@" "Server at $ORIGIN does not serve this checkout; details in $REPORT_PATH.")"
}

PROBE="$ROOT/$PROBE_PATH"
BODY="$(mktemp "${TMPDIR:-/tmp}/check-serves-checkout.XXXXXX")" || exit 2
trap 'rm -f "$PROBE" "$BODY"' EXIT

NONCE="$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')"
if [[ -z "$NONCE" ]] || ! mkdir -p "$(dirname "$PROBE")" 2>/dev/null \
  || ! printf '%s' "$NONCE" > "$PROBE" 2>/dev/null; then
  PID=unknown
  CWD=unknown
  report_failure probe-unwritable "cannot write the probe file: $PROBE" \
    "Could not write $PROBE_PATH to check the server at $ORIGIN serves this checkout; make .ai/run-context writable, then rerun."
  exit 2
fi

# Same proxy handling as poll-preview.sh: with a proxy in the environment,
# every address goes through it, local ones included.
PROXY_ARGS=()
if [[ -n "${HTTP_PROXY:-${http_proxy:-}}" ]]; then
  PROXY_ARGS=(--noproxy '')
fi

STATUS=$(curl -s -o "$BODY" -w '%{http_code}' --max-time 3 ${PROXY_ARGS[@]+"${PROXY_ARGS[@]}"} "$ORIGIN/$PROBE_PATH" 2>/dev/null)

if [[ "$STATUS" == "200" && "$(cat "$BODY" 2>/dev/null)" == "$NONCE" ]]; then
  echo "serves-checkout: origin=$ORIGIN root=$ROOT"
  exit 0
fi

find_listener

if [[ -z "$STATUS" || "$STATUS" == "000" ]]; then
  if [[ "$STARTED" == "yes" ]]; then
    report_failure no-answer "nothing answered at $ORIGIN/$PROBE_PATH" \
      "The server this run started at $ORIGIN stopped answering during the checkout check; see .ai/run-context/serve.log, then rerun."
  else
    report_failure no-answer "nothing answered at $ORIGIN/$PROBE_PATH" \
      "The server at $ORIGIN stopped answering during the checkout check; start this checkout's server there (commands.serve), then rerun."
  fi
  exit 1
fi

DETAIL="$ORIGIN answered status=$STATUS without this run's nonce at /$PROBE_PATH; it does not serve $ROOT"
# Only what was actually found goes into a candidate: a process id and a
# directory each appear only when lsof named them.
CANDIDATES=()
if [[ "$STARTED" == "yes" ]]; then
  [[ "$PID" != "unknown" && "$CWD" != "unknown" ]] && CANDIDATES+=(
    "commands.serve started a server at $ORIGIN (pid $PID, serving $CWD) that does not serve this checkout; make it serve the project root, stop it (kill $PID), then rerun.")
  [[ "$PID" != "unknown" ]] && CANDIDATES+=(
    "commands.serve started a server at $ORIGIN (pid $PID) that does not serve this checkout; make it serve the project root, stop it (kill $PID), then rerun.")
  CANDIDATES+=(
    "commands.serve started a server at $ORIGIN that does not serve this checkout; make it serve the project root, stop what listens on port $PORT, then rerun.")
else
  [[ "$PID" != "unknown" && "$CWD" != "unknown" ]] && CANDIDATES+=(
    "Server at $ORIGIN (pid $PID, serving $CWD) is not this checkout's and was not started by this run; stop it (kill $PID) or point paths.preview at this checkout's server, then rerun.")
  [[ "$PID" != "unknown" ]] && CANDIDATES+=(
    "Server at $ORIGIN (pid $PID) does not serve this checkout and was not started by this run; stop it (kill $PID) or point paths.preview at this checkout's server, then rerun.")
  CANDIDATES+=(
    "Server at $ORIGIN does not serve this checkout and was not started by this run; stop what listens on port $PORT or point paths.preview at this checkout's server, then rerun.")
fi
report_failure foreign "$DETAIL" "${CANDIDATES[@]}"
exit 1
