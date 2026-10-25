#!/usr/bin/env bash
# Tests for check-pr-body.sh. Run with:
#   bash plugins/agentic-github/skills/publish-change/scripts/check-pr-body.test.sh
#
# No framework — exits 0 on success, 1 on any failure.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SCRIPT_DIR/check-pr-body.sh"

PASS=0
FAIL=0
check() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    PASS=$((PASS + 1)); echo "  ok: $desc"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: $desc"; echo "    expected: $expected"; echo "    actual:   $actual"
  fi
}

[[ -n "${TMPDIR:-}" ]] || { echo "TMPDIR is empty; refusing to create test directories" >&2; exit 1; }
WORK="$(mktemp -d "$TMPDIR/check-pr-body-test.XXXXXX")" || exit 1
[[ -n "$WORK" && -d "$WORK" ]] || { echo "cannot create a temp dir" >&2; exit 1; }
trap 'rm -rf "$WORK"' EXIT

# A template with headings, placeholders and an HTML comment.
cat > "$WORK/headed.md" <<'EOF'
## Summary
<!-- what changed and why -->

## Issue
Fix #<issue-id>

## Test URLs
- Before: https://main--{repo}--{owner}.example.test/
- After: https://<branch>--{repo}--{owner}.example.test/

## Screenshots
EOF

# The caller's body: what deliver composed.
cat > "$WORK/source.md" <<'EOF'
Item: EX-1 (Story)

## Requirements
- req-1: an empty cell renders as an empty cell
EOF

echo "=== check-pr-body.sh tests ==="

echo "[filled] every heading has content, every placeholder is replaced, the source is carried"
cat > "$WORK/filled.md" <<'EOF'
## Summary
Empty cells keep their row height.

## Issue
Empty: the work item is EX-1 in the tracker, not an issue in this repository.

## Test URLs
- Before: https://main--site--org.example.test/
- After: https://ex-1--site--org.example.test/

## Screenshots
Empty: the run attached its captures to EX-1.

---

Item: EX-1 (Story)

## Requirements
- req-1: an empty cell renders as an empty cell
EOF
OUT="$(bash "$CHECK" "$WORK/headed.md" "$WORK/filled.md" --source "$WORK/source.md")"; ST=$?
check "exit 0" 0 "$ST"
check "one line with the counts" "filled: 4 headings, 4 placeholders replaced" "$OUT"

echo "[heading missing] a template heading absent from the body"
sed '/^## Screenshots$/,$d' "$WORK/filled.md" > "$WORK/no-heading.md"
cat "$WORK/source.md" >> "$WORK/no-heading.md"
OUT="$(bash "$CHECK" "$WORK/headed.md" "$WORK/no-heading.md")"; ST=$?
check "exit 1" 1 "$ST"
check "names the heading" "unfilled: heading '## Screenshots' is missing" "$OUT"

echo "[heading empty] a heading with nothing under it, and no Empty: reason"
awk '{print} /^## Screenshots$/{getline; getline; next}' "$WORK/filled.md" > "$WORK/blank-section.md"
OUT="$(bash "$CHECK" "$WORK/headed.md" "$WORK/blank-section.md")"; ST=$?
check "exit 1" 1 "$ST"
check "names the empty heading" "unfilled: heading '## Screenshots' has no content and no 'Empty: <reason>'" "$OUT"

echo "[empty without reason] 'Empty:' alone is not a reason"
sed 's/^Empty: the run attached its captures to EX-1\.$/Empty:/' "$WORK/filled.md" > "$WORK/no-reason.md"
OUT="$(bash "$CHECK" "$WORK/headed.md" "$WORK/no-reason.md")"; ST=$?
check "exit 1" 1 "$ST"
check "names the heading" "unfilled: heading '## Screenshots' has no content and no 'Empty: <reason>'" "$OUT"

echo "[placeholder left] a template placeholder survives into the body"
sed 's#https://ex-1--site--org#https://<branch>--site--org#' "$WORK/filled.md" > "$WORK/placeholder.md"
OUT="$(bash "$CHECK" "$WORK/headed.md" "$WORK/placeholder.md")"; ST=$?
check "exit 1" 1 "$ST"
check "names the placeholder" "unfilled: placeholder '<branch>' is still in the body" "$OUT"

echo "[order] headings out of the template's order"
cat > "$WORK/reordered.md" <<'EOF'
## Issue
Empty: no issue.

## Summary
Text.

## Test URLs
- Before: https://main--site--org.example.test/
- After: https://ex-1--site--org.example.test/

## Screenshots
Empty: none.
EOF
OUT="$(bash "$CHECK" "$WORK/headed.md" "$WORK/reordered.md")"; ST=$?
check "exit 1" 1 "$ST"
check "names the heading found out of order" "unfilled: heading '## Issue' is out of the template's order" "$OUT"

echo "[source dropped] the caller's body is not carried verbatim"
sed '/^- req-1/d' "$WORK/filled.md" > "$WORK/dropped.md"
OUT="$(bash "$CHECK" "$WORK/headed.md" "$WORK/dropped.md" --source "$WORK/source.md")"; ST=$?
check "exit 1" 1 "$ST"
check "says so" "unfilled: the composed body is not carried verbatim" "$OUT"

echo "[no headings] a template of prose and placeholders only (the shape this project's template has)"
cat > "$WORK/flat.md" <<'EOF'
Please always provide the issue your PR is for, as well as test URLs:

Fix #<gh-issue-id>

Test URLs:
- Before: https://main--{repo}--{owner}.example.test/
- After: https://<branch>--{repo}--{owner}.example.test/
EOF
cat > "$WORK/flat-filled.md" <<'EOF'
Fix: Empty: the work item is EX-1 in the tracker, not an issue in this repository.

Test URLs:
- Before: https://main--site--org.example.test/
- After: https://ex-1--site--org.example.test/
EOF
OUT="$(bash "$CHECK" "$WORK/flat.md" "$WORK/flat-filled.md")"; ST=$?
check "exit 0" 0 "$ST"
check "counts zero headings" "filled: 0 headings, 4 placeholders replaced" "$OUT"
cp "$WORK/flat.md" "$WORK/flat-copy.md"
OUT="$(bash "$CHECK" "$WORK/flat.md" "$WORK/flat-copy.md")"; ST=$?
check "the template pasted unchanged → exit 1" 1 "$ST"
check "first placeholder named" "unfilled: placeholder '<gh-issue-id>' is still in the body" "$(printf '%s\n' "$OUT" | head -1)"

echo "[usage] a missing file"
bash "$CHECK" "$WORK/headed.md" "$WORK/absent.md" >/dev/null 2>&1; ST=$?
check "exit 2" 2 "$ST"

echo ""
echo "passed: $PASS, failed: $FAIL"
[[ "$FAIL" -eq 0 ]]
