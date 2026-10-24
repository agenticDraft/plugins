#!/usr/bin/env bash
# derive-config.sh — Derives this platform's project values from the
# repository's remote (D129, D138). No model involved. Declared as the pack's
# `config_derivation`; the core's setup runs it and writes what it prints.
#
# The preview host is `<branch>--<repo>--<owner>`, one DNS label of at most 63
# characters (G45). So the project's two values are:
#   platform.preview_host_suffix  `--<repo>--<owner>`, lower case
#   branch_name.max_length        63 minus the suffix's length
# preview-url.sh and check-branch-length.sh read them back from the config.
#
# Usage:
#   derive-config.sh --remote <remote URL>
#
# Accepts `git@<host>:<owner>/<repo>[.git]` and `<scheme>://[<user>@]<host>/<owner>/<repo>[.git]`.
#
# Output (stdout), on success only:
#   branch_name.max_length=<n>
#   platform.preview_host_suffix=--<repo>--<owner>
#
# Exit codes:
#   0 — derived
#   1 — refused, the reason on stderr: not an <owner>/<repo> remote; a name
#       holding a character a host label cannot (only a-z, 0-9 and - are kept,
#       and how the host rewrites any other is not documented); or a suffix
#       that leaves no room for a branch
#   2 — usage error

set -uo pipefail

LIMIT=63

usage() { echo "usage: derive-config.sh --remote <remote URL>" >&2; exit 2; }
refuse() { echo "refused: $1" >&2; exit 1; }

REMOTE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --remote) [[ $# -ge 2 ]] || usage; REMOTE="$2"; shift 2 ;;
    *) usage ;;
  esac
done
[[ -n "$REMOTE" ]] || usage

if [[ "$REMOTE" =~ ^[a-z][a-z0-9+.-]*://[^/]+/(.+)$ ]]; then
  path="${BASH_REMATCH[1]}"
elif [[ "$REMOTE" =~ ^[^/:[:space:]]+:([^/].*)$ ]]; then
  path="${BASH_REMATCH[1]}"
else
  refuse "'$REMOTE' is not a remote URL"
fi
path="${path%/}"
path="${path%.git}"
[[ "$path" =~ ^([^/]+)/([^/]+)$ ]] || refuse "'$REMOTE' does not end in <owner>/<repo>"
owner="${BASH_REMATCH[1]}"
repo="${BASH_REMATCH[2]}"

suffix="$(printf -- '--%s--%s' "$repo" "$owner" | tr '[:upper:]' '[:lower:]')"
[[ "$suffix" =~ ^--[a-z0-9-]+--[a-z0-9-]+$ ]] \
  || refuse "'$owner/$repo' holds a character a preview host label cannot hold (only a-z, 0-9 and -)"

max=$((LIMIT - ${#suffix}))
(( max >= 1 )) || refuse "the suffix '$suffix' is ${#suffix} characters; it leaves no room for a branch within $LIMIT"

echo "branch_name.max_length=$max"
echo "platform.preview_host_suffix=$suffix"
exit 0
