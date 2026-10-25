#!/usr/bin/env bash
# Run: bash plugins/agentic-eds/shared/scripts/check-instruction-hosts.sh [--config <path>]
#
# Flags every concrete preview or live host named in the project's tracked
# root-level `*.md` files (its instruction files and README) whose
# `--<repo>--<owner>` part disagrees with the config's
# `platform.preview_host_suffix`. A host a template filled in at creation,
# left behind by a move or a rename, points a run at a host that no longer
# belongs to this repository. A placeholder form (`{repo}`, `{owner}`) and a
# documentation host with no `--` are not hosts of this site and are skipped.
# Read-only.
#
# Output (stdout):
#   stale: <file>:<line> <host label>.aem.<page|live> — the config's suffix is <suffix>
#   ok: no stale preview or live host in <n> tracked root .md files
#
# Exit codes: 0 — none stale; 1 — at least one; 2 — usage error or no suffix
# in the config.

set -uo pipefail

CONFIG=".ai/project-config.yaml"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --config) [[ $# -ge 2 ]] || exit 2; CONFIG="$2"; shift 2 ;;
    *) echo "usage: check-instruction-hosts.sh [--config <path>]" >&2; exit 2 ;;
  esac
done

suffix=""
[[ -f "$CONFIG" ]] && suffix="$(awk '
  $0 == "platform:" { inside = 1; next }
  /^[^ ]/ { inside = 0 }
  inside && /^  preview_host_suffix:/ { v = $0; sub(/^  preview_host_suffix:[ \t]*/, "", v); gsub(/["[:space:]]/, "", v); print v; exit }
' "$CONFIG")"
[[ -n "$suffix" ]] || { echo "unconfigured: no platform.preview_host_suffix in $CONFIG; run setup" >&2; exit 2; }

FILES=()
while IFS= read -r f; do
  [[ "$f" == */* ]] && continue
  FILES+=("$f")
done < <(git ls-files -- '*.md' 2>/dev/null)

STALE=0
for f in "${FILES[@]:-}"; do
  [[ -n "$f" && -f "$f" ]] || continue
  while IFS= read -r hit; do
    line="${hit%%:*}"
    host="${hit#*:}"
    label="${host%.aem.*}"
    rest="${label#*--}"
    [[ "$label" == *--* ]] || continue
    [[ "$rest" == *"{"* ]] && continue
    lower="$(printf '%s' "$label" | tr '[:upper:]' '[:lower:]')"
    [[ "$lower" == *"$suffix" ]] && continue
    echo "stale: $f:$line $host — the config's suffix is $suffix"
    STALE=$((STALE + 1))
  done < <(grep -noE '[A-Za-z0-9{}-]+--[A-Za-z0-9{}-]+\.aem\.(page|live)' "$f")
done

(( STALE > 0 )) && exit 1
echo "ok: no stale preview or live host in ${#FILES[@]} tracked root .md files"
exit 0
