#!/usr/bin/env bash
# list-pack-candidates.sh — Lists every registered plugin that is a pack,
# under the project-config role it can fill (see shared/project-config.md).
# Deterministic, no model involved; names no pack.
#
# A `kind: platform` pack is a `platform` candidate; a `kind: provider` pack is
# a candidate for the `role:` it declares. A plugin with no pack.yaml is not a
# pack and is not listed. The plugins come only from
# `resolve-plugin-root.sh --list`.
#
# Usage:
#   list-pack-candidates.sh [--project-dir <dir>]
#
# Output (stdout): one '<role><TAB><name>' line per candidate, in the config's
# role order (platform, tracker, scm, design, browser, then any other role),
# names sorted within a role. A role with no line has no candidate.
#
# Exit codes:
#   0 — listed (possibly nothing)
#   1 — the resolver listed nothing; its line on stderr
#   2 — usage error

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RESOLVE_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-dir) [[ $# -ge 2 ]] || { echo "usage: list-pack-candidates.sh [--project-dir <dir>]" >&2; exit 2; }
                   RESOLVE_ARGS=(--project-dir "$2"); shift 2 ;;
    *) echo "usage: list-pack-candidates.sh [--project-dir <dir>]" >&2; exit 2 ;;
  esac
done

LISTED=$(bash "$SCRIPT_DIR/resolve-plugin-root.sh" --list ${RESOLVE_ARGS[@]+"${RESOLVE_ARGS[@]}"}) || exit 1

role_rank() {
  case "$1" in
    platform) echo 1 ;; tracker) echo 2 ;; scm) echo 3 ;; design) echo 4 ;; browser) echo 5 ;; *) echo 9 ;;
  esac
}

while IFS=$'\t' read -r name root; do
  [[ -n "$root" && -f "$root/pack.yaml" ]] || continue
  kind=$(awk '/^kind:/ { print $2; exit }' "$root/pack.yaml")
  case "$kind" in
    platform) role=platform ;;
    provider) role=$(awk '/^role:/ { print $2; exit }' "$root/pack.yaml") ;;
    *) continue ;;
  esac
  [[ -n "$role" ]] || continue
  printf '%s\t%s\t%s\n' "$(role_rank "$role")" "$role" "$name"
done <<< "$LISTED" | sort -t $'\t' -k1,1n -k2,2 -k3,3 | cut -f2,3
exit 0
