#!/usr/bin/env bash
# Run: bash plugins/agentic-core/shared/lib/name-files-to-commit.sh <declarations>
#
# name-files-to-commit.sh <declarations>
#
# Names the files setup leaves for the human to commit: every path the core
# commits on purpose (a `commit` line), then the ignore file and the committed
# settings file, each only when git shows it new or changed. A run's fresh
# start refuses a tree with anything uncommitted, so these are what must be
# committed before the first run. Run from the project root. Reads and never
# writes. Deterministic, no model involved.
#
# Output (stdout):
#   commit: <path>                                 one per path to commit, in that order
#   none: every file setup wrote is committed
#
# Exit codes: 0 — named (or none); 1 — not inside a git work tree;
#             2 — usage error, or the declarations file does not exist.

set -uo pipefail

[[ $# -eq 1 && -f "$1" ]] || { echo "usage: name-files-to-commit.sh <declarations>" >&2; exit 2; }
DECL="$1"

[[ "$(git rev-parse --is-inside-work-tree 2>/dev/null)" == "true" ]] \
  || { echo "refused: $(pwd) is not inside a git work tree"; exit 1; }

PATHS=()
while IFS=$'\t' read -r kind _owner path _rest; do
  [[ "$kind" == "commit" ]] && PATHS+=("$path")
done < "$DECL"
PATHS+=(".gitignore" ".claude/settings.json")

OUT=""
for path in "${PATHS[@]}"; do
  [[ -e "$path" ]] || continue
  [[ -n "$(git status --porcelain --untracked-files=all -- "$path" 2>/dev/null)" ]] && OUT+="commit: $path"$'\n'
done

if [[ -z "$OUT" ]]; then
  echo "none: every file setup wrote is committed"
else
  printf '%s' "$OUT"
fi
exit 0
