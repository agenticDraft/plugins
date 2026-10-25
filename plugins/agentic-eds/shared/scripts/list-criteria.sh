#!/usr/bin/env bash
# Run: bash plugins/agentic-eds/shared/scripts/list-criteria.sh <sanitized-spec.md>
#
# Prints the work item's acceptance-criterion ids, one per line, in order: each
# line under the `## Acceptance criteria` heading (any case) that starts with
# `AC-<n>`, up to the next `## ` heading. An id anywhere else is not a
# criterion. No model involved; compose-fixture.sh and
# check-criteria-coverage.sh read the same list.
#
# Exit codes: 0 — at least one id; 1 — none, or an id twice (reason on
# stdout); 2 — usage error or a missing file.

set -uo pipefail

SPEC="${1:-}"
[[ -n "$SPEC" ]] || { echo "usage: list-criteria.sh <sanitized-spec.md>"; exit 2; }
[[ -f "$SPEC" ]] || { echo "refused: $SPEC does not exist"; exit 2; }

awk -v file="$SPEC" '
  /^##[ \t]/ {
    h = tolower($0); sub(/^##[ \t]+/, "", h); sub(/[ \t]+$/, "", h)
    inside = (h == "acceptance criteria"); next
  }
  inside && match($0, /^AC-[0-9]+([ \t]|$)/) {
    id = substr($0, 1, RLENGTH); sub(/[ \t]$/, "", id)
    if (id in seen) { print "refused: " id " appears twice"; bad = 1; exit }
    seen[id] = 1; ids[++n] = id
  }
  END {
    if (bad) exit 1
    if (n == 0) { print "none: no AC-<n> criterion under \"## Acceptance criteria\" in " file; exit 1 }
    for (i = 1; i <= n; i++) print ids[i]
  }
' "$SPEC"
