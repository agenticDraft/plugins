#!/usr/bin/env bash
# Run: bash plugins/agentic-core/shared/lib/filter-working-paths.sh <working-paths file> < paths
#
# filter-working-paths.sh <working-paths file>
#
# Drops the run's working paths from a list of project-relative paths on
# stdin and prints the rest, in input order. The file holds one path per
# line, as write-working-paths.sh writes it: an entry ending in `/` drops
# every path under that directory, any other entry drops exactly that path.
# Blank and `#` lines in the file are not entries. A file that does not exist
# drops nothing, so a run that never wrote one sees the change set it always
# saw. One definition, read by every reader of the change set and by the
# commit. Deterministic, no model involved. Writes nothing.
#
# Exit codes: 0 — filtered; 2 — usage error.

set -uo pipefail

[[ $# -eq 1 && -n "$1" ]] || { echo "usage: filter-working-paths.sh <working-paths file>" >&2; exit 2; }
FILE="$1"

ENTRIES=()
if [[ -f "$FILE" ]]; then
  while IFS= read -r entry || [[ -n "$entry" ]]; do
    [[ -z "$entry" || "$entry" == \#* ]] && continue
    ENTRIES+=("$entry")
  done < "$FILE"
fi

while IFS= read -r path || [[ -n "$path" ]]; do
  [[ -z "$path" ]] && continue
  drop=0
  for entry in "${ENTRIES[@]+"${ENTRIES[@]}"}"; do
    if [[ "$entry" == */ ]]; then
      [[ "$path" == "$entry"* ]] && { drop=1; break; }
    else
      [[ "$path" == "$entry" ]] && { drop=1; break; }
    fi
  done
  (( drop )) || printf '%s\n' "$path"
done
exit 0
