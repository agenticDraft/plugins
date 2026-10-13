#!/usr/bin/env bash
# Run: bash scripts/check-plugin-versions.sh <base-ref> [repo-dir]
#
# Two rules, both read from git and the manifests:
#   1. A plugin with a file changed since the merge-base with <base-ref> carries a different
#      `version` in its plugin.json than it had there. A plugin that did not exist there is new
#      and needs no bump.
#   2. Every catalog entry's `version` equals the `version` in that plugin's plugin.json.
# Prints one `ok:` / `bump:` / `drift:` line per finding and exits 1 on any `bump:` or `drift:`.
set -uo pipefail

BASE="${1:-}"
[ -n "$BASE" ] || { echo "usage: check-plugin-versions.sh <base-ref> [repo-dir]" >&2; exit 2; }
cd "${2:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}" || exit 2
command -v jq >/dev/null || { echo "jq is required" >&2; exit 2; }

MB=$(git merge-base "$BASE" HEAD) || { echo "no merge-base with $BASE" >&2; exit 2; }
bad=0

for dir in plugins/*/; do
  dir="${dir%/}"
  manifest="$dir/.claude-plugin/plugin.json"
  [ -f "$manifest" ] || continue
  now=$(jq -r '.version' "$manifest")
  if ! before_json=$(git show "$MB:$manifest" 2>/dev/null); then
    echo "ok: $dir is new since $BASE (version $now)"
    continue
  fi
  before=$(jq -r '.version' <<<"$before_json")
  if [ -z "$(git diff --name-only "$MB" HEAD -- "$dir")" ]; then
    echo "ok: $dir unchanged"
  elif [ "$now" = "$before" ]; then
    echo "bump: $dir changed since $BASE but its version is still $now"
    bad=1
  else
    echo "ok: $dir changed, version $before -> $now"
  fi
done

while IFS=$'\t' read -r name source version; do
  manifest="$source/.claude-plugin/plugin.json"
  [ -f "$manifest" ] || { echo "drift: catalog entry $name has no manifest at $manifest"; bad=1; continue; }
  have=$(jq -r '.version' "$manifest")
  if [ "$have" = "$version" ]; then
    echo "ok: catalog $name is $version"
  else
    echo "drift: catalog says $name is $version, $manifest says $have"
    bad=1
  fi
done < <(jq -r '.plugins[] | [.name, .source, .version] | @tsv' .claude-plugin/marketplace.json)

exit "$bad"
