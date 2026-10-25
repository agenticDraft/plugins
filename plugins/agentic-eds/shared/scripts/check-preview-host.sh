#!/usr/bin/env bash
# Run: bash plugins/agentic-eds/shared/scripts/check-preview-host.sh [--config <path>]
#
# This pack's `preview-host` credential check (pack.yaml). Run in the
# project's checkout. Asks the default branch's preview host for a code file
# every project of this platform serves, `/scripts/aem.js`. The host serves
# code only once the code-sync app covers the repository, so a host that does
# not answer means the app is not installed for this owner and repository (or
# the host is down). Content is not asked for: a new site has none yet.
#
# The default branch is the one `origin/HEAD` records, else `main`; lower
# case, `/` as `-`, as the host label takes it. The suffix is read from the
# project config; whether it is still right is check-preview-config.sh's
# question. The request is bounded in time.
#
# Exit codes: 0 — the host answered; 1 — it did not, or no suffix is
# configured (the reason on stderr); 2 — usage error.

set -uo pipefail

CONFIG=".ai/project-config.yaml"
TIMEOUT_SECONDS=15
while [[ $# -gt 0 ]]; do
  case "$1" in
    --config) [[ $# -ge 2 ]] || exit 2; CONFIG="$2"; shift 2 ;;
    *) echo "usage: check-preview-host.sh [--config <path>]" >&2; exit 2 ;;
  esac
done

suffix=""
[[ -f "$CONFIG" ]] && suffix="$(awk '
  $0 == "platform:" { inside = 1; next }
  /^[^ ]/ { inside = 0 }
  inside && /^  preview_host_suffix:/ { v = $0; sub(/^  preview_host_suffix:[ \t]*/, "", v); gsub(/["[:space:]]/, "", v); print v; exit }
' "$CONFIG")"
[[ -n "$suffix" ]] || { echo "unconfigured: no platform.preview_host_suffix in $CONFIG; run setup" >&2; exit 1; }

branch="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)"
branch="${branch#origin/}"
[[ -n "$branch" ]] || branch="main"
branch="$(printf '%s' "$branch" | tr '[:upper:]/' '[:lower:]-')"

host="${branch}${suffix}.aem.page"
if curl -fsS -o /dev/null --max-time "$TIMEOUT_SECONDS" "https://$host/scripts/aem.js" 2>/dev/null; then
  exit 0
fi
echo "unanswered: https://$host/scripts/aem.js" >&2
exit 1
