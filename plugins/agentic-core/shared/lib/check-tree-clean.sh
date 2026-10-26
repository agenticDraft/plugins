#!/usr/bin/env bash
# Run: bash plugins/agentic-core/shared/lib/check-tree-clean.sh <project-root>
#
# check-tree-clean.sh <project-root> [--exclude-file <working-paths file>]
# — the fresh-start tree guard. With --exclude-file, the run's declared
# working paths are not changes, exactly as the publish gate leaves them out.
#
# A fresh run must begin on a tree with nothing in it the run did not write.
# The publish gate reviews, and the deliver stage publishes, everything in
# list-changed-files.sh's change set; a path already in that set before the
# run began would be published unreviewed, or refused by the gate only at
# the end of the run. This guard asks the same script for the same set
# before anything of the run exists, so the two can never disagree: every
# tracked change against the merge base of origin/HEAD and HEAD (edited,
# staged, deleted, or committed on this branch only) and every untracked
# path the ignore rules do not exclude.
#
# It reads and never writes. A resumed run must not call this: its tree
# holds the run being resumed, and this check at its fresh start is what
# guarantees that everything dirty on resume is the run's own.
#
# A check made earlier, by the code that starts the session, is honoured: the
# marker file .ai/run-context/tree-prechecked holds the HEAD commit that check
# was made on. When it equals this checkout's HEAD the answer is "clean:
# checked before the session"; an absent, empty or different marker is
# ignored and the check below runs in full. The marker is written only after a
# clean answer from this script, run outside the session.
#
# Exit codes:
#   0 — "clean: no change and no untracked path", or
#       "clean: checked before the session"
#   1 — "refused: <n> paths changed before this run", then one
#       "changed: <path>" line per path, sorted, each once
#   2 — usage error, or the change set could not be computed (the
#       reason from list-changed-files.sh is passed through on stderr)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIST="$SCRIPT_DIR/list-changed-files.sh"

usage() { echo "usage: check-tree-clean.sh <project-root> [--exclude-file <working-paths file>]" >&2; exit 2; }

ROOT="${1:-}"
[[ -n "$ROOT" && -d "$ROOT" ]] || usage
shift
LIST_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --exclude-file) [[ $# -ge 2 && -n "$2" ]] || usage; LIST_ARGS=(--exclude-file "$2"); shift 2 ;;
    *) usage ;;
  esac
done

MARKER="$ROOT/.ai/run-context/tree-prechecked"
if [[ -s "$MARKER" ]]; then
  HEAD_NOW="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null)"
  if [[ -n "$HEAD_NOW" && "$(head -n 1 "$MARKER")" == "$HEAD_NOW" ]]; then
    echo "clean: checked before the session"
    exit 0
  fi
fi

CHANGED="$(bash "$LIST" "$ROOT" ${LIST_ARGS[@]+"${LIST_ARGS[@]}"})" || exit 2

if [[ -z "$CHANGED" ]]; then
  echo "clean: no change and no untracked path"
  exit 0
fi

COUNT="$(printf '%s\n' "$CHANGED" | grep -c .)"
echo "refused: $COUNT paths changed before this run"
printf '%s\n' "$CHANGED" | sed 's/^/changed: /'
exit 1
