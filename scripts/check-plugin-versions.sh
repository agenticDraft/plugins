#!/usr/bin/env bash
# Run: bash scripts/check-plugin-versions.sh <base-ref> [repo-dir]
#
# Two rules, both read from git and the manifests:
#   1. A plugin with a file changed since the merge-base with <base-ref> carries a different
#      `version` in its plugin.json than it had there. A plugin that did not exist there is new
#      and needs no bump. A symlink tracked inside a plugin counts its target as the plugin's
#      own files: the installed copy holds what the link pointed at when that version was
#      installed, so a change behind the link reaches it only through a bump.
#   2. Every catalog entry's `version` equals the `version` in that plugin's plugin.json.
# Prints one `ok:` / `bump:` / `drift:` line per finding and exits 1 on any `bump:` or `drift:`.
set -uo pipefail

BASE="${1:-}"
[ -n "$BASE" ] || { echo "usage: check-plugin-versions.sh <base-ref> [repo-dir]" >&2; exit 2; }
cd "${2:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}" || exit 2
command -v jq >/dev/null || { echo "jq is required" >&2; exit 2; }

MB=$(git merge-base "$BASE" HEAD) || { echo "no merge-base with $BASE" >&2; exit 2; }
ROOT=$(pwd -P)
bad=0

# linked_change <plugin dir> — prints "<link> -> <target>" for the first tracked symlink in the
# plugin whose target, a folder in this repository, changed since the merge-base.
linked_change() {
  local link target resolved
  while IFS= read -r link; do
    target=$(cd "$(dirname "$link")" 2>/dev/null && cd "$(readlink "$(basename "$link")")" 2>/dev/null && pwd -P) || continue
    case "$target" in "$ROOT"/*) resolved="${target#"$ROOT"/}" ;; *) continue ;; esac
    if [ -n "$(git diff --name-only "$MB" HEAD -- "$resolved")" ]; then
      echo "$link -> $resolved"
      return 0
    fi
  done < <(git ls-files -s -- "$1" | awk '$1 == "120000" { sub(/^[^\t]*\t/, ""); print }')
  return 1
}

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
  via=""
  if [ -z "$(git diff --name-only "$MB" HEAD -- "$dir")" ]; then
    via=$(linked_change "$dir") || { echo "ok: $dir unchanged"; continue; }
    via=" (through its link $via)"
  fi
  if [ "$now" = "$before" ]; then
    echo "bump: $dir changed since $BASE$via but its version is still $now"
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
