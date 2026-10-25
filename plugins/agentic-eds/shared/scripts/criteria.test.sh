#!/usr/bin/env bash
# Tests for list-criteria.sh, compose-fixture.sh and check-criteria-coverage.sh.
# Run with:
#   bash plugins/agentic-eds/shared/scripts/criteria.test.sh
#
# No framework — exits 0 on success, 1 on any failure. The spec below is the
# shape of a real empty-cell item: three criteria about empty content, two
# about content that must keep rendering, one about the page.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIST="$SCRIPT_DIR/list-criteria.sh"
COMPOSE="$SCRIPT_DIR/compose-fixture.sh"
COVERAGE="$SCRIPT_DIR/check-criteria-coverage.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/criteria.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
expect() {
  local desc="$1" want="$2" rc="$3" out="$4"
  if [[ "$rc" == "$want" ]]; then PASS=$((PASS + 1)); echo "  ok: $desc"
  else FAIL=$((FAIL + 1)); echo "  FAIL: $desc (expected exit=$want, got exit=$rc)"; echo "    $out"; fi
}
has() {
  local desc="$1" needle="$2" out="$3"
  if [[ "$out" == *"$needle"* ]]; then PASS=$((PASS + 1)); echo "  ok: $desc"
  else FAIL=$((FAIL + 1)); echo "  FAIL: $desc"; echo "    expected: $needle"; echo "    got: $out"; fi
}
lacks() {
  local desc="$1" needle="$2" out="$3"
  if [[ "$out" != *"$needle"* ]]; then PASS=$((PASS + 1)); echo "  ok: $desc"
  else FAIL=$((FAIL + 1)); echo "  FAIL: $desc"; echo "    unexpected: $needle"; fi
}

SPEC="$WORK/sanitized-spec.md"
cat > "$SPEC" <<'EOF'
# Cards block skips empty authored cells

## Description

AC-9 in a description is not a criterion.

## Acceptance criteria

AC-1 An authored card cell with no child elements and no text renders no element in the decorated block.
AC-2 An authored card cell containing only whitespace renders no element in the decorated block.
AC-3 An authored row whose cells are all empty renders no list item in the decorated block.
AC-4 A cell holding a single picture still renders with the class cards-card-image.
AC-5 A cell holding text still renders with the class cards-card-body.
AC-6 A page containing the cards block loads with no new console errors.

## Out of scope

AC-7 under another heading is not a criterion either.
EOF

echo "=== list-criteria.sh ==="
OUT=$(bash "$LIST" "$SPEC" 2>&1); RC=$?
expect "lists the criteria -> exit 0" 0 "$RC" "$OUT"
[[ "$OUT" == $'AC-1\nAC-2\nAC-3\nAC-4\nAC-5\nAC-6' ]] && { PASS=$((PASS + 1)); echo "  ok: only the ids under the criteria heading, in order"; } \
  || { FAIL=$((FAIL + 1)); echo "  FAIL: only the ids under the criteria heading, in order"; echo "    got: $OUT"; }
printf '# T\n\n## Acceptance criteria\n\n- no ids here\n' > "$WORK/noids.md"
OUT=$(bash "$LIST" "$WORK/noids.md" 2>&1); RC=$?
expect "no criterion id -> exit 1" 1 "$RC" "$OUT"
printf '## Acceptance criteria\nAC-1 a\nAC-1 b\n' > "$WORK/dup.md"
OUT=$(bash "$LIST" "$WORK/dup.md" 2>&1); RC=$?
expect "an id twice -> exit 1" 1 "$RC" "$OUT"
has "names the duplicate" "AC-1 appears twice" "$OUT"

echo "=== compose-fixture.sh ==="
P="$WORK/project"; mkdir -p "$P"
CASES="$WORK/cases.tsv"
printf 'AC-1\tempty\nAC-2\twhitespace\nAC-3\tempty-row\nAC-4\tpicture\nAC-5\ttext\nAC-6\tpage\n' > "$CASES"
OUT=$(cd "$P" && bash "$COMPOSE" --block cards --item EDS-31 --spec "$SPEC" --cases "$CASES" 2>&1); RC=$?
expect "composes the fixture -> exit 0" 0 "$RC" "$OUT"
has "reports what it wrote" "written: drafts/EDS-31.plain.html rows=5 criteria=6" "$OUT"
has "names the image it wrote" "written: drafts/EDS-31-fixture-image.svg" "$OUT"
F="$P/drafts/EDS-31.plain.html"
HTML="$(cat "$F" 2>/dev/null)"
has "holds an empty cell" "<div></div>" "$HTML"
WS_CELLS=$(grep -cE '^ *<div>[[:space:]]+$' "$F" 2>/dev/null)
[[ "$WS_CELLS" == 1 ]] && { PASS=$((PASS + 1)); echo "  ok: holds exactly one whitespace-only cell"; } \
  || { FAIL=$((FAIL + 1)); echo "  FAIL: holds exactly one whitespace-only cell (found $WS_CELLS)"; }
EMPTY_ROW=$(awk '/<div><\/div>/ { if (prev ~ /<div><\/div>/) n++ } { prev = $0 } END { print n + 0 }' "$F")
[[ "$EMPTY_ROW" == 1 ]] && { PASS=$((PASS + 1)); echo "  ok: holds one row whose cells are all empty"; } \
  || { FAIL=$((FAIL + 1)); echo "  FAIL: holds one row whose cells are all empty (found $EMPTY_ROW)"; }
has "the picture cell holds only the picture" '<div><picture><img src="./EDS-31-fixture-image.svg" alt="cards fixture image — AC-4" width="1600" height="900"></picture></div>' "$HTML"
has "a text cell names its criterion" "<div>cards fixture — AC-5, cell 1</div>" "$HTML"
has "the block is not the first section" "cards fixture — leading section" "$HTML"
lacks "a page-level criterion adds no row" "AC-6" "$HTML"
[[ -f "$P/drafts/EDS-31.cases.tsv" ]] && cmp -s "$CASES" "$P/drafts/EDS-31.cases.tsv" \
  && { PASS=$((PASS + 1)); echo "  ok: the cases are kept beside the fixture"; } \
  || { FAIL=$((FAIL + 1)); echo "  FAIL: the cases are kept beside the fixture"; }
ROWS=$(grep -c '^    <div>$' "$F")
[[ "$ROWS" == 5 ]] && { PASS=$((PASS + 1)); echo "  ok: one block row per row-level case"; } \
  || { FAIL=$((FAIL + 1)); echo "  FAIL: one block row per row-level case (found $ROWS)"; }

OUT=$(cd "$P" && bash "$COMPOSE" --block cards --item EDS-31 --spec "$SPEC" --cases "$CASES" 2>&1); RC=$?
expect "an existing fixture is never overwritten -> exit 1" 1 "$RC" "$OUT"

printf 'AC-1\tempty\nAC-2\twhitespace\nAC-3\tempty-row\nAC-4\tpicture\nAC-6\tpage\n' > "$WORK/missing.tsv"
OUT=$(cd "$P" && bash "$COMPOSE" --block cards --item EDS-32 --spec "$SPEC" --cases "$WORK/missing.tsv" 2>&1); RC=$?
expect "a criterion with no case line -> exit 1" 1 "$RC" "$OUT"
has "names it" "AC-5 has no case" "$OUT"
[[ ! -e "$P/drafts/EDS-32.plain.html" ]] && { PASS=$((PASS + 1)); echo "  ok: nothing written on a refusal"; } \
  || { FAIL=$((FAIL + 1)); echo "  FAIL: nothing written on a refusal"; }

printf 'AC-1\tempty\nAC-2\twhitespace\nAC-3\tempty-row\nAC-4\tpicture\nAC-5\ttext\nAC-6\tpage\nAC-8\ttext\n' > "$WORK/unknown.tsv"
OUT=$(cd "$P" && bash "$COMPOSE" --block cards --item EDS-33 --spec "$SPEC" --cases "$WORK/unknown.tsv" 2>&1); RC=$?
expect "a case for a criterion the item does not have -> exit 1" 1 "$RC" "$OUT"
printf 'AC-1\tempty\nAC-2\twhitespace\nAC-3\tempty-row\nAC-4\tpicture\nAC-5\ttooltip\nAC-6\tpage\n' > "$WORK/vocab.tsv"
OUT=$(cd "$P" && bash "$COMPOSE" --block cards --item EDS-34 --spec "$SPEC" --cases "$WORK/vocab.tsv" 2>&1); RC=$?
expect "a case outside the vocabulary -> exit 1" 1 "$RC" "$OUT"
has "names the vocabulary" "text, picture, empty, whitespace, empty-row, page or none" "$OUT"
printf 'AC-1\tempty\nAC-2\twhitespace\nAC-3\tempty-row\nAC-4\tpicture\nAC-5\tnone\nAC-6\tpage\n' > "$WORK/noreason.tsv"
OUT=$(cd "$P" && bash "$COMPOSE" --block cards --item EDS-35 --spec "$SPEC" --cases "$WORK/noreason.tsv" 2>&1); RC=$?
expect "a 'none' case without a reason -> exit 1" 1 "$RC" "$OUT"
printf 'AC-1\tnone\tno vocabulary case holds this\nAC-2\tnone\tx\nAC-3\tnone\tx\nAC-4\tnone\tx\nAC-5\tnone\tx\nAC-6\tpage\n' > "$WORK/allnone.tsv"
OUT=$(cd "$P" && bash "$COMPOSE" --block cards --item EDS-36 --spec "$SPEC" --cases "$WORK/allnone.tsv" 2>&1); RC=$?
expect "no row-level case still renders the block -> exit 0" 0 "$RC" "$OUT"
has "with one text row" "rows=1" "$OUT"
OUT=$(cd "$P" && bash "$COMPOSE" --block cards --item ../x --spec "$SPEC" --cases "$CASES" 2>&1); RC=$?
expect "an item id that is a path -> exit 2" 2 "$RC" "$OUT"

echo "=== check-criteria-coverage.sh ==="
RES="$WORK/results.tsv"
printf 'AC-1\tpassed\tno cards-card-body for the empty cell (measure)\nAC-2\tpassed\tsame for the whitespace cell\nAC-3\tpassed\t4 list items for 5 rows\nAC-4\tpassed\tcards-card-image present\nAC-5\tfailed\tcards-card-body missing\nAC-6\tpassed\tconsole_errors 0\n' > "$RES"
OUT=$(bash "$COVERAGE" --spec "$SPEC" --results "$RES" --cases "$CASES" 2>&1); RC=$?
expect "every criterion exercised, one failed -> exit 0 (verify fails it on its own)" 0 "$RC" "$OUT"
has "counts them" "criteria=6 exercised=6 passed=5 failed=1 not-exercised=0" "$OUT"
has "names the failed one with its evidence" "exercised: AC-5 failed — cards-card-body missing" "$OUT"

grep -v '^AC-3' "$CASES" > "$WORK/cases-removed.tsv"
OUT=$(bash "$COVERAGE" --spec "$SPEC" --results "$RES" --cases "$WORK/cases-removed.tsv" 2>&1); RC=$?
expect "a criterion's case removed from the fixture -> exit 1, even with a passed result" 1 "$RC" "$OUT"
has "reports it not exercised" "not-exercised: AC-3 — the fixture holds no case for it" "$OUT"
has "the count shows it" "not-exercised=1" "$OUT"

sed 's/^AC-2\tpassed/AC-2\tnot-attempted/' "$RES" > "$WORK/na.tsv"
OUT=$(bash "$COVERAGE" --spec "$SPEC" --results "$WORK/na.tsv" --cases "$CASES" 2>&1); RC=$?
expect "a criterion reported not attempted -> exit 1" 1 "$RC" "$OUT"
has "says why" "not-exercised: AC-2 — not attempted: same for the whitespace cell" "$OUT"

grep -v '^AC-6' "$RES" > "$WORK/nores.tsv"
OUT=$(bash "$COVERAGE" --spec "$SPEC" --results "$WORK/nores.tsv" 2>&1); RC=$?
expect "a criterion with no result, no fixture -> exit 1" 1 "$RC" "$OUT"
has "says no result was recorded" "not-exercised: AC-6 — no result recorded" "$OUT"

sed 's/^AC-4\tpicture$/AC-4\tnone\tno case expresses it/' "$CASES" > "$WORK/cases-none.tsv"
OUT=$(bash "$COVERAGE" --spec "$SPEC" --results "$RES" --cases "$WORK/cases-none.tsv" 2>&1); RC=$?
expect "a 'none' case cannot pass -> exit 1" 1 "$RC" "$OUT"
has "quotes the reason" "not-exercised: AC-4 — no fixture case: no case expresses it" "$OUT"

printf 'AC-1\tpassed\t\n' > "$WORK/noevidence.tsv"
OUT=$(bash "$COVERAGE" --spec "$SPEC" --results "$WORK/noevidence.tsv" 2>&1); RC=$?
expect "a result without evidence -> exit 2" 2 "$RC" "$OUT"
printf 'AC-1\tlooks fine\tx\n' > "$WORK/badstatus.tsv"
OUT=$(bash "$COVERAGE" --spec "$SPEC" --results "$WORK/badstatus.tsv" 2>&1); RC=$?
expect "a status outside passed/failed/not-attempted -> exit 2" 2 "$RC" "$OUT"
printf 'AC-1\tpassed\tx\nAC-1\tfailed\ty\n' > "$WORK/dupres.tsv"
OUT=$(bash "$COVERAGE" --spec "$SPEC" --results "$WORK/dupres.tsv" 2>&1); RC=$?
expect "a criterion with two results -> exit 2" 2 "$RC" "$OUT"
printf 'AC-8\tpassed\tx\n' > "$WORK/unknownres.tsv"
OUT=$(bash "$COVERAGE" --spec "$SPEC" --results "$WORK/unknownres.tsv" 2>&1); RC=$?
expect "a result for a criterion the item does not have -> exit 2" 2 "$RC" "$OUT"
OUT=$(bash "$COVERAGE" --spec "$SPEC" --results "$WORK/absent.tsv" 2>&1); RC=$?
expect "no results file -> exit 1, every criterion not exercised" 1 "$RC" "$OUT"
has "all six counted" "not-exercised=6" "$OUT"

echo
echo "=== $PASS passed, $FAIL failed ==="
(( FAIL == 0 ))
