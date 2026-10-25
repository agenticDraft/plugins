#!/usr/bin/env bash
# Run: bash plugins/agentic-core/shared/lib/resolve-configured-packs.sh <config>
#
# resolve-configured-packs.sh <config> [--project-dir <dir>]
#
# Resolves every role the project config's `packs:` block names, and says
# whether the pack found there can fill that role. A pack is found through
# resolve-plugin-root.sh, its manifest checked by validate-pack-manifest.sh,
# and its kind compared with the role: `kind: platform` for `platform`,
# `kind: provider` with a matching `role:` for every other role. Names no
# pack. Deterministic, no model involved. Writes nothing.
#
# Output (stdout), one tab-separated line per role, in the config's order,
# then one line per required role the block does not name:
#   resolved<TAB><role><TAB><pack><TAB><path to pack.yaml>
#   none<TAB><role>                                   the config says `none`
#   unresolved<TAB><role><TAB><pack><TAB><reason>     the resolver's own line
#   invalid<TAB><role><TAB><pack><TAB><reason>        its manifest does not validate
#   mismatch<TAB><role><TAB><pack><TAB><reason>       the wrong kind or role
#   missing<TAB><role>                                a required role is not named
#
# Exit codes:
#   0 — every named role resolved or is `none`, and no required role is missing
#   1 — at least one line is unresolved, invalid, mismatch or missing
#   2 — usage error, no config, or no `packs:` block

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REQUIRED_ROLES=(platform tracker scm design browser)

usage() {
  echo "usage: resolve-configured-packs.sh <config> [--project-dir <dir>]" >&2
  exit 2
}

[[ $# -ge 1 ]] || usage
CONFIG="$1"; shift
RESOLVE_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-dir) [[ $# -ge 2 ]] || usage; RESOLVE_ARGS=(--project-dir "$2"); shift 2 ;;
    *) usage ;;
  esac
done

[[ -f "$CONFIG" ]] || { echo "refused: $CONFIG does not exist" >&2; exit 2; }
grep -q '^packs:[[:space:]]*$' "$CONFIG" || { echo "refused: $CONFIG has no packs: block" >&2; exit 2; }

# '<role> <pack>' per line under `packs:`, in file order.
ENTRIES=$(awk '
  /^packs:[[:space:]]*$/ { inside = 1; next }
  inside && /^[^[:space:]]/ { inside = 0 }
  inside && /^  [a-z_]+:[[:space:]]*[^[:space:]]/ {
    r = $1; sub(/:$/, "", r); v = $2; gsub(/"/, "", v); print r, v
  }' "$CONFIG")

STATUS=0
named=" "
while read -r role pack; do
  [[ -n "$role" ]] || continue
  named+="$role "
  if [[ "$pack" == "none" ]]; then
    echo "none"$'\t'"$role"
    continue
  fi
  if ! root=$(bash "$SCRIPT_DIR/resolve-plugin-root.sh" "$pack" ${RESOLVE_ARGS[@]+"${RESOLVE_ARGS[@]}"} 2>&1); then
    echo "unresolved"$'\t'"$role"$'\t'"$pack"$'\t'"${root//$'\n'/ }"
    STATUS=1; continue
  fi
  manifest="$root/pack.yaml"
  if [[ ! -f "$manifest" ]]; then
    echo "unresolved"$'\t'"$role"$'\t'"$pack"$'\t'"no pack.yaml at $root"
    STATUS=1; continue
  fi
  if ! verdict=$(bash "$SCRIPT_DIR/validate-pack-manifest.sh" "$manifest" 2>&1); then
    echo "invalid"$'\t'"$role"$'\t'"$pack"$'\t'"${verdict%%$'\n'*}"
    STATUS=1; continue
  fi
  if [[ "$role" == "platform" ]]; then
    if [[ "$verdict" != "valid: platform" ]]; then
      echo "mismatch"$'\t'"$role"$'\t'"$pack"$'\t'"not a platform pack (${verdict#valid: })"
      STATUS=1; continue
    fi
  else
    declared=$(sed -n 's/^role: *//p' "$manifest" | head -1)
    if [[ "$verdict" != "valid: provider" ]]; then
      echo "mismatch"$'\t'"$role"$'\t'"$pack"$'\t'"not a provider pack (${verdict#valid: })"
      STATUS=1; continue
    elif [[ "$declared" != "$role" ]]; then
      echo "mismatch"$'\t'"$role"$'\t'"$pack"$'\t'"declares role '$declared'"
      STATUS=1; continue
    fi
  fi
  echo "resolved"$'\t'"$role"$'\t'"$pack"$'\t'"$manifest"
done <<< "$ENTRIES"

for role in "${REQUIRED_ROLES[@]}"; do
  if [[ "$named" != *" $role "* ]]; then
    echo "missing"$'\t'"$role"
    STATUS=1
  fi
done

exit "$STATUS"
