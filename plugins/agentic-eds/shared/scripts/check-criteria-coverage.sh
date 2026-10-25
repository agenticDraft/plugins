#!/usr/bin/env bash
# Run: bash plugins/agentic-eds/shared/scripts/check-criteria-coverage.sh --spec <sanitized-spec.md> --results <results.tsv> [--cases <cases.tsv>]
#
# Decides whether every acceptance criterion of the work item was exercised.
# `verify` records one result per criterion; this script, not the stage, judges
# coverage, so a criterion nobody checked can never read as a pass.
#
# Results file: one line per criterion, tab-separated,
# `<AC-id> <passed|failed|not-attempted> <evidence>` — evidence required.
# Cases file (compose-fixture.sh's copy beside a generated fixture): when
# given, a criterion with no line there, or with case `none`, was not
# exercised, whatever its result says — the fixture never held it.
#
# A criterion is exercised when it has a `passed` or `failed` result and, when
# a cases file is given, a case other than `none`. A failed criterion is
# exercised; failing the stage on it is the stage's own rule.
#
# Output (stdout), one line per criterion, then a count:
#   exercised: <id> <passed|failed> — <evidence>
#   not-exercised: <id> — <why>
#   criteria=<n> exercised=<e> passed=<p> failed=<f> not-exercised=<k>
#
# Exit codes: 0 — every criterion exercised; 1 — at least one not, or no
# results file; 2 — usage error, or a malformed results line (bad status, no
# evidence, an unknown id, an id twice).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPEC="" RESULTS="" CASES=""
usage() { echo "usage: check-criteria-coverage.sh --spec <sanitized-spec.md> --results <results.tsv> [--cases <cases.tsv>]" >&2; exit 2; }
while [[ $# -gt 0 ]]; do
  [[ $# -ge 2 ]] || usage
  case "$1" in
    --spec) SPEC="$2" ;;
    --results) RESULTS="$2" ;;
    --cases) CASES="$2" ;;
    *) usage ;;
  esac
  shift 2
done
[[ -n "$SPEC" && -n "$RESULTS" ]] || usage

CRITERIA="$(bash "$SCRIPT_DIR/list-criteria.sh" "$SPEC")"
rc=$?
(( rc == 0 )) || { echo "$CRITERIA" >&2; exit 2; }
[[ -z "$CASES" || -f "$CASES" ]] || { echo "refused: $CASES does not exist" >&2; exit 2; }

R="$RESULTS"; [[ -f "$R" ]] || R=/dev/null
C="${CASES:-/dev/null}"

awk -F'\t' -v criteria="$(printf '%s\n' "$CRITERIA" | tr '\n' ' ')" -v have_cases="${CASES:+1}" '
  BEGIN { n = split(criteria, ids, " "); for (i = 1; i <= n; i++) known[ids[i]] = 1 }
  FNR == 1 { file++ }
  /^[[:space:]]*$/ { next }
  file == 1 {
    if (!($1 in known)) { print "malformed: a result for " $1 ", which is not a criterion of this item"; bad = 1; next }
    if ($1 in status) { print "malformed: " $1 " has two results"; bad = 1; next }
    if ($2 != "passed" && $2 != "failed" && $2 != "not-attempted") { print "malformed: " $1 ": status \"" $2 "\" is not passed, failed or not-attempted"; bad = 1; next }
    if ($3 ~ /^[[:space:]]*$/) { print "malformed: " $1 ": a result needs its evidence"; bad = 1; next }
    status[$1] = $2; evidence[$1] = $3; next
  }
  file == 2 { cs[$1] = $2; reason[$1] = $3 }
  END {
    if (bad) exit 2
    for (i = 1; i <= n; i++) {
      id = ids[i]
      if (have_cases && !(id in cs)) why = "the fixture holds no case for it"
      else if (have_cases && cs[id] == "none") why = "no fixture case: " reason[id]
      else if (!(id in status)) why = "no result recorded"
      else if (status[id] == "not-attempted") why = "not attempted: " evidence[id]
      else why = ""
      if (why != "") { print "not-exercised: " id " — " why; k++ }
      else { print "exercised: " id " " status[id] " — " evidence[id]; e++; if (status[id] == "passed") p++; else f++ }
    }
    printf "criteria=%d exercised=%d passed=%d failed=%d not-exercised=%d\n", n, e, p, f, k
    exit (k > 0) ? 1 : 0
  }
' "$R" "$C"
