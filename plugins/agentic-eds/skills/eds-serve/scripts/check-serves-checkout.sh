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
# One request, no ladder: the caller has already seen the origin answer.
#
# Usage:
#   check-serves-checkout.sh <preview-url> <project-root>
#
# Output on success: one line,
#   serves-checkout: origin=<origin> root=<project-root>
#
# Exit codes:
#   0 — the server returned the nonce; it serves this checkout
#   1 — the server did not return the nonce; the reason is on stderr
#   2 — usage error, or the probe file could not be written

set -uo pipefail

URL="${1:-}"
ROOT="${2:-}"
PROBE_PATH=".ai/run-context/serve-probe.txt"

if [[ -z "$URL" || -z "$ROOT" ]]; then
  echo "usage: check-serves-checkout.sh <preview-url> <project-root>" >&2
  exit 2
fi

if [[ ! "$URL" =~ ^([A-Za-z][A-Za-z0-9+.-]*://[^/?#]+) ]]; then
  echo "not a URL with an origin: $URL" >&2
  exit 2
fi
ORIGIN="${BASH_REMATCH[1]}"

if [[ ! -d "$ROOT" ]]; then
  echo "no such project root: $ROOT" >&2
  exit 2
fi

PROBE="$ROOT/$PROBE_PATH"
BODY="$(mktemp "${TMPDIR:-/tmp}/check-serves-checkout.XXXXXX")" || exit 2
trap 'rm -f "$PROBE" "$BODY"' EXIT

NONCE="$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')"
if [[ -z "$NONCE" ]] || ! mkdir -p "$(dirname "$PROBE")" 2>/dev/null \
  || ! printf '%s' "$NONCE" > "$PROBE" 2>/dev/null; then
  echo "cannot write the probe file: $PROBE" >&2
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

if [[ -z "$STATUS" || "$STATUS" == "000" ]]; then
  echo "no-answer: nothing answered at $ORIGIN/$PROBE_PATH" >&2
else
  echo "foreign: $ORIGIN answered status=$STATUS without this run's nonce at /$PROBE_PATH; it does not serve $ROOT" >&2
fi
exit 1
