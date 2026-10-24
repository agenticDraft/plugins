#!/usr/bin/env bash
# Run: bash plugins/agentic-core/shared/lib/collect-pack-declarations.sh <config>
#
# collect-pack-declarations.sh <config> [--project-dir <dir>]
#
# Collects what the project must provide for the packs its config names: each
# pack's `env`, `hosts` and `ignore_paths` (shared/pack-manifest.md), then the
# core's own paths from shared/run-paths.txt. Only the packs under the config's
# `packs:` block are read; an installed pack that was not chosen adds nothing.
# Each pack is found through resolve-plugin-root.sh and its manifest checked by
# validate-pack-manifest.sh before anything is read from it. Names no pack.
# Deterministic, no model involved. Writes nothing.
#
# Output (stdout), one tab-separated line per declaration:
#   env<TAB><pack><TAB><NAME><TAB><source>          a variable to hold a placeholder
#   login<TAB><pack><TAB><NAME><TAB><login>         a variable a login replaces; no key is written
#   host<TAB><pack><TAB><host>
#   ignore<TAB><pack|core><TAB><path>
#   commit<TAB>core<TAB><path>
#   unresolved<TAB><pack><TAB><reason>              the resolver could not find it
#
# Exit codes:
#   0 — collected (unresolved packs are lines, not a failure)
#   1 — refused: no config, no `packs:` block, or a configured pack's manifest
#       is invalid (one line on stderr naming it; nothing on stdout)
#   2 — usage error

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_PATHS="$SCRIPT_DIR/../run-paths.txt"

usage() {
  echo "usage: collect-pack-declarations.sh <config> [--project-dir <dir>]" >&2
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

[[ -f "$CONFIG" ]] || { echo "refused: $CONFIG does not exist" >&2; exit 1; }

# The pack names under `packs:`, in file order; `none` is not a pack.
PACKS=$(awk '
  /^packs:[[:space:]]*$/ { inside = 1; next }
  inside && /^[^[:space:]]/ { inside = 0 }
  inside && /^  [a-z_]+:[[:space:]]*[^[:space:]]/ {
    v = $2; gsub(/"/, "", v); if (v != "none" && !seen[v]++) print v
  }' "$CONFIG")
grep -q '^packs:[[:space:]]*$' "$CONFIG" || { echo "refused: $CONFIG has no packs: block" >&2; exit 1; }

OUT=""
add() { OUT+="$1"$'\n'; }

# The double-quoted entries of a one-line bracket list, one per line.
quoted_entries() {
  local list="$1"
  grep -oE '"[^"]*"' <<< "$list" | sed 's/^"//; s/"$//'
}

while IFS= read -r pack; do
  [[ -n "$pack" ]] || continue
  if ! root=$(bash "$SCRIPT_DIR/resolve-plugin-root.sh" "$pack" ${RESOLVE_ARGS[@]+"${RESOLVE_ARGS[@]}"} 2>&1); then
    add "unresolved"$'\t'"$pack"$'\t'"${root//$'\n'/ }"
    continue
  fi
  manifest="$root/pack.yaml"
  if [[ ! -f "$manifest" ]]; then
    add "unresolved"$'\t'"$pack"$'\t'"no pack.yaml at $root"
    continue
  fi
  if ! verdict=$(bash "$SCRIPT_DIR/validate-pack-manifest.sh" "$manifest" 2>&1); then
    echo "refused: $pack — its manifest is invalid: ${verdict%%$'\n'*}" >&2
    exit 1
  fi

  # env: entries are a name, a source and an optional login_alternative, in
  # that order, as the validator just checked.
  name="" source=""
  flush() {
    [[ -n "$name" ]] || return 0
    if [[ -n "$login" ]]; then
      add "login"$'\t'"$pack"$'\t'"$name"$'\t'"$login"
    else
      add "env"$'\t'"$pack"$'\t'"$name"$'\t'"$source"
    fi
    name="" source="" login=""
  }
  login="" inside=0
  while IFS= read -r line; do
    if [[ "$line" == "env:" ]]; then inside=1; continue; fi
    (( inside )) || continue
    if [[ "$line" =~ ^\ \ -\ name:\ (.*)$ ]]; then
      flush; name="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^\ \ \ \ source:\ \"(.*)\"$ ]]; then
      source="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^\ \ \ \ login_alternative:\ \"(.*)\"$ ]]; then
      login="${BASH_REMATCH[1]}"
    else
      flush; inside=0
    fi
  done < "$manifest"
  flush

  hosts=$(sed -n 's/^hosts: \[\(.*\)\]$/\1/p' "$manifest")
  while IFS= read -r h; do [[ -n "$h" ]] && add "host"$'\t'"$pack"$'\t'"$h"; done < <(quoted_entries "$hosts")
  paths=$(sed -n 's/^ignore_paths: \[\(.*\)\]$/\1/p' "$manifest")
  while IFS= read -r p; do [[ -n "$p" ]] && add "ignore"$'\t'"$pack"$'\t'"$p"; done < <(quoted_entries "$paths")
done <<< "$PACKS"

while read -r kind path; do
  case "$kind" in
    ignore|commit) add "$kind"$'\t'"core"$'\t'"$path" ;;
  esac
done < "$RUN_PATHS"

printf '%s' "$OUT"
exit 0
