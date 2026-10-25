#!/usr/bin/env bash
# Run: bash plugins/agentic-eds/shared/scripts/compose-fixture.sh --block <name> --item <id> --spec <sanitized-spec.md> --cases <cases.tsv>
#
# Builds the test fixture for a block from the work item's criteria: one
# authored case per criterion. The caller picks each criterion's case; this
# script writes the markup, so the content a criterion needs is always there.
#
# Cases file: one line per criterion, tab-separated, `<AC-id> <case> [<reason>]`.
# Every criterion list-criteria.sh prints appears exactly once, and no other.
#   text        a row of two text cells
#   picture     a row whose first cell holds only a picture, then a text cell
#   empty       a row whose first cell is empty (no child, no text), then text
#   whitespace  a row whose first cell holds only whitespace, then text
#   empty-row   a row whose cells are all empty
#   page        about the page as a whole; adds no row
#   none        no case can hold it; the reason is required, and the
#               criterion can never be reported exercised
# A fixture with no row-level case gets one text row, so the block renders.
#
# Writes, in the current directory: drafts/<id>.plain.html, a copy of the cases
# as drafts/<id>.cases.tsv (check-criteria-coverage.sh reads it), and
# drafts/<id>-fixture-image.svg when a picture case exists. The block is the
# second section, after a one-line text section: the page's first section has
# its first image made eager by the page's own loader, whatever the block does.
# Every text cell names its criterion and cell, so it is never read as copy.
# An existing fixture is never overwritten.
#
# Output (stdout): `written: <path> …` per file. Exit codes: 0 — written;
# 1 — refused (a cases problem, or a fixture already there), nothing written;
# 2 — usage error.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BLOCK="" ITEM="" SPEC="" CASES=""
usage() { echo "usage: compose-fixture.sh --block <name> --item <id> --spec <sanitized-spec.md> --cases <cases.tsv>" >&2; exit 2; }
while [[ $# -gt 0 ]]; do
  [[ $# -ge 2 ]] || usage
  case "$1" in
    --block) BLOCK="$2" ;;
    --item) ITEM="$2" ;;
    --spec) SPEC="$2" ;;
    --cases) CASES="$2" ;;
    *) usage ;;
  esac
  shift 2
done
[[ -n "$BLOCK" && -n "$ITEM" && -n "$SPEC" && -n "$CASES" ]] || usage
[[ "$ITEM" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]] || { echo "refused: item id '$ITEM' is not a plain name" >&2; exit 2; }
[[ "$BLOCK" =~ ^[a-z0-9][a-z0-9-]*$ ]] || { echo "refused: block '$BLOCK' is not a block name" >&2; exit 2; }
[[ -f "$CASES" ]] || { echo "refused: $CASES does not exist" >&2; exit 2; }

CRITERIA="$(bash "$SCRIPT_DIR/list-criteria.sh" "$SPEC")" || { echo "$CRITERIA" >&2; exit 1; }

OUT="drafts/$ITEM.plain.html"
IMG="drafts/$ITEM-fixture-image.svg"
KEPT="drafts/$ITEM.cases.tsv"
[[ -e "$OUT" ]] && { echo "refused: $OUT already exists; delete it first for a fresh fixture" >&2; exit 1; }

# Validate the cases against the criteria; print each criterion's case in
# criterion order, or the problems.
PLAN="$(awk -F'\t' -v criteria="$(printf '%s\n' "$CRITERIA" | tr '\n' ' ')" '
  BEGIN {
    n = split(criteria, ids, " "); for (i = 1; i <= n; i++) known[ids[i]] = 1
    split("text picture empty whitespace empty-row page none", v, " "); for (i in v) vocab[v[i]] = 1
  }
  /^[[:space:]]*$/ { next }
  {
    id = $1; c = $2; r = $3
    if (!(id in known)) { err = err "\n" id " is not a criterion of this item"; next }
    if (id in got) { err = err "\n" id " has two cases"; next }
    if (!(c in vocab)) { err = err "\n" id ": case \"" c "\" is not one of text, picture, empty, whitespace, empty-row, page or none"; next }
    if (c == "none" && r ~ /^[[:space:]]*$/) { err = err "\n" id ": case none needs a reason"; next }
    got[id] = c
  }
  END {
    for (i = 1; i <= n; i++) if (!(ids[i] in got) && index(err, ids[i] " ") == 0) err = err "\n" ids[i] " has no case"
    if (err != "") { print substr(err, 2); exit 1 }
    for (i = 1; i <= n; i++) print ids[i] "\t" got[ids[i]]
  }
' "$CASES")" || { while IFS= read -r l; do echo "refused: $l" >&2; done < <(printf '%s\n' "$PLAN"); exit 1; }

text_cell() { printf '      <div>%s fixture — %s, cell %s</div>\n' "$BLOCK" "$1" "$2"; }
open_row() { printf '    <div>\n'; }
close_row() { printf '    </div>\n'; }

ROWS=0
PICTURE=0
BODY=""
while IFS=$'\t' read -r id c; do
  case "$c" in
    text) row="$(open_row; text_cell "$id" 1; text_cell "$id" 2; close_row)" ;;
    picture) PICTURE=1
             row="$(open_row
                    printf '      <div><picture><img src="./%s-fixture-image.svg" alt="%s fixture image — %s" width="1600" height="900"></picture></div>\n' "$ITEM" "$BLOCK" "$id"
                    text_cell "$id" 2; close_row)" ;;
    empty) row="$(open_row; printf '      <div></div>\n'; text_cell "$id" 2; close_row)" ;;
    whitespace) row="$(open_row; printf '      <div>   \n      </div>\n'; text_cell "$id" 2; close_row)" ;;
    empty-row) row="$(open_row; printf '      <div></div>\n      <div></div>\n'; close_row)" ;;
    *) continue ;;
  esac
  BODY="$BODY$row"$'\n'
  ROWS=$((ROWS + 1))
done < <(printf '%s\n' "$PLAN")
if (( ROWS == 0 )); then
  BODY="$(open_row; text_cell "baseline row" 1; text_cell "baseline row" 2; close_row)"$'\n'
  ROWS=1
fi

mkdir -p drafts
{
  printf '<div>\n  <p>%s fixture — leading section, so the block under test is not the page'"'"'s first section</p>\n</div>\n' "$BLOCK"
  printf '<div>\n  <div class="%s">\n' "$BLOCK"
  printf '%s' "$BODY"
  printf '  </div>\n</div>\n'
} > "$OUT"
echo "written: $OUT rows=$ROWS criteria=$(printf '%s\n' "$CRITERIA" | grep -c .)"

if (( PICTURE )); then
  cat > "$IMG" <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1600 900" width="1600" height="900" role="img" aria-label="fixture placeholder image">
  <rect width="1600" height="900" fill="#d8dee9"/>
  <text x="800" y="470" text-anchor="middle" font-family="monospace" font-size="72" fill="#4c566a">fixture placeholder</text>
</svg>
SVG
  echo "written: $IMG"
fi

if [[ ! "$CASES" -ef "$KEPT" ]]; then
  cp "$CASES" "$KEPT"
fi
echo "written: $KEPT"
exit 0
