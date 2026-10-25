#!/usr/bin/env bash
# Run: bash plugins/agentic-eds/shared/scripts/check-preview-config.sh [--config <path>]
#
# This pack's `preview-config` credential check (pack.yaml). Run in the
# project's checkout. Re-derives the preview host suffix and the branch limit
# from the current `origin` remote through derive-config.sh and compares them
# with what the project config holds. A repository moved to another owner or
# renamed after setup fails here, before a run builds a URL for a host that no
# longer belongs to it. Offline: reads the remote's URL, fetches nothing.
#
# Exit codes: 0 — the config agrees with the remote; 1 — it does not, or a
# value is missing (the reason on stderr); 2 — usage error.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG=".ai/project-config.yaml"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --config) [[ $# -ge 2 ]] || exit 2; CONFIG="$2"; shift 2 ;;
    *) echo "usage: check-preview-config.sh [--config <path>]" >&2; exit 2 ;;
  esac
done

refuse() { echo "stale: $1" >&2; exit 1; }

# config_value <section> <key> — a value in a two-level block, unquoted.
config_value() {
  awk -v s="$1:" -v k="  $2:" '
    $0 == s { inside = 1; next }
    /^[^ ]/ { inside = 0 }
    inside && index($0, k) == 1 { v = substr($0, length(k) + 1); gsub(/^[ \t"]+|[ \t"]+$/, "", v); print v; exit }
  ' "$CONFIG"
}

[[ -f "$CONFIG" ]] || refuse "$CONFIG does not exist; run setup"
origin="$(git remote get-url origin 2>/dev/null)" || refuse "no origin remote, so nothing can be derived"

derived="$(bash "$SCRIPT_DIR/derive-config.sh" --remote "$origin" 2>&1)" || refuse "$derived"
want_suffix="$(printf '%s\n' "$derived" | sed -n 's/^platform\.preview_host_suffix=//p')"
want_max="$(printf '%s\n' "$derived" | sed -n 's/^branch_name\.max_length=//p')"

have_suffix="$(config_value platform preview_host_suffix)"
have_max="$(config_value branch_name max_length)"
[[ -n "$have_suffix" ]] || refuse "$CONFIG has no platform.preview_host_suffix; run setup"
[[ -n "$have_max" ]] || refuse "$CONFIG has no branch_name.max_length; run setup"

[[ "$have_suffix" == "$want_suffix" ]] \
  || refuse "platform.preview_host_suffix is '$have_suffix'; the remote derives '$want_suffix'"
[[ "$have_max" == "$want_max" ]] \
  || refuse "branch_name.max_length is $have_max; the remote derives $want_max"
exit 0
