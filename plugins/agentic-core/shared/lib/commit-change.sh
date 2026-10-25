#!/usr/bin/env bash
# Run: bash plugins/agentic-core/shared/lib/commit-change.sh <project-root> <message>
#
# commit-change.sh <project-root> <message> [--exclude-file <working-paths file>]
#
# Commits the change a run publishes: every change in the working tree except
# the run's working paths (filter-working-paths.sh's definition). Everything
# is staged, then each working path is reset in the index, so a working path
# is left out whether it is untracked, already tracked, or was staged before
# this call. A left-out path stays in the working tree as it was. An absent
# file leaves nothing out. Deterministic, no model involved.
#
# Output (stdout):
#   committed: <short sha> (<n> files)      or
#   nothing: no change to commit outside the working paths
#   left-out: <path>                        one per working path that had a change
#
# Exit codes:
#   0 — committed, or nothing to commit
#   1 — git refused a step; its stderr passed through
#   2 — usage error, or <project-root> is not a git work tree

set -uo pipefail

usage() { echo "usage: commit-change.sh <project-root> <message> [--exclude-file <file>]" >&2; exit 2; }

[[ $# -ge 2 && -n "$1" && -n "$2" ]] || usage
ROOT="$1"; MESSAGE="$2"; shift 2
EXCLUDE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --exclude-file) [[ $# -ge 2 ]] || usage; EXCLUDE="$2"; shift 2 ;;
    *) usage ;;
  esac
done

[[ "$(git -C "$ROOT" rev-parse --is-inside-work-tree 2>/dev/null)" == "true" ]] \
  || { echo "invalid: not a git work tree: $ROOT" >&2; exit 2; }

ENTRIES=()
if [[ -n "$EXCLUDE" && -f "$EXCLUDE" ]]; then
  while IFS= read -r entry || [[ -n "$entry" ]]; do
    [[ -z "$entry" || "$entry" == \#* ]] && continue
    ENTRIES+=("$entry")
  done < "$EXCLUDE"
fi

ERR="$(git -C "$ROOT" add -A 2>&1)" || { printf '%s\n' "$ERR" >&2; exit 1; }
if (( ${#ENTRIES[@]} > 0 )); then
  ERR="$(git -C "$ROOT" reset -q -- "${ENTRIES[@]}" 2>&1)" || { printf '%s\n' "$ERR" >&2; exit 1; }
fi

# The paths that had a change and were left out: everything git now reports
# as changed but unstaged or untracked, kept only when it is a working path.
LEFT_OUT=""
if (( ${#ENTRIES[@]} > 0 )); then
  ALL="$(git -C "$ROOT" status --porcelain --untracked-files=all -- "${ENTRIES[@]}" 2>/dev/null | cut -c4-)"
  LEFT_OUT="$(printf '%s\n' "$ALL" | grep . | sort -u)"
fi

if git -C "$ROOT" diff --cached --quiet; then
  echo "nothing: no change to commit outside the working paths"
else
  N="$(git -C "$ROOT" diff --cached --numstat | grep -c .)"
  ERR="$(git -C "$ROOT" commit -q -m "$MESSAGE" 2>&1)" || { printf '%s\n' "$ERR" >&2; exit 1; }
  echo "committed: $(git -C "$ROOT" rev-parse --short HEAD) ($N files)"
fi
[[ -n "$LEFT_OUT" ]] && printf '%s\n' "$LEFT_OUT" | sed 's/^/left-out: /'
exit 0
