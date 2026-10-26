#!/usr/bin/env bash
# Tests for find-pr-template.sh. Run with:
#   bash plugins/agentic-github/skills/publish-change/scripts/find-pr-template.test.sh
#
# No framework — exits 0 on success, 1 on any failure.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIND="$SCRIPT_DIR/find-pr-template.sh"

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
WORK="$(mktemp -d "$TMPDIR/find-pr-template-test.XXXXXX")" || exit 1
[[ -n "$WORK" && -d "$WORK" ]] || { echo "cannot create a temp dir" >&2; exit 1; }
trap 'rm -rf "$WORK"' EXIT

repo() { rm -rf "$WORK/r"; mkdir -p "$WORK/r"; echo "$WORK/r"; }

echo "=== find-pr-template.sh tests ==="

echo "[none] a repository with no template"
R="$(repo)"
OUT="$(bash "$FIND" "$R")"; ST=$?
check "exit 3" 3 "$ST"
check "says none" "none: no pull request template in this repository" "$OUT"

for loc in .github/pull_request_template.md pull_request_template.md docs/pull_request_template.md \
           .github/PULL_REQUEST_TEMPLATE.md; do
  echo "[found] $loc"
  R="$(repo)"
  mkdir -p "$R/$(dirname "$loc")"
  printf 'Fix #<id>\n' > "$R/$loc"
  OUT="$(bash "$FIND" "$R")"; ST=$?
  check "exit 0" 0 "$ST"
  check "prints the path relative to the root" "template: $loc" "$OUT"
done

echo "[order] .github wins over the root, the root over docs/"
R="$(repo)"
mkdir -p "$R/.github" "$R/docs"
printf 'a\n' > "$R/.github/pull_request_template.md"
printf 'b\n' > "$R/pull_request_template.md"
printf 'c\n' > "$R/docs/pull_request_template.md"
check ".github first" "template: .github/pull_request_template.md" "$(bash "$FIND" "$R")"
rm "$R/.github/pull_request_template.md"
check "then the root" "template: pull_request_template.md" "$(bash "$FIND" "$R")"

echo "[directory only] several templates in a directory are not a default body"
R="$(repo)"
mkdir -p "$R/.github/PULL_REQUEST_TEMPLATE"
printf 'x\n' > "$R/.github/PULL_REQUEST_TEMPLATE/feature.md"
OUT="$(bash "$FIND" "$R")"; ST=$?
check "exit 3" 3 "$ST"
check "says why" "none: only a template directory (.github/PULL_REQUEST_TEMPLATE/), which applies by query parameter only" "$OUT"

echo "[empty file] an empty template is no template"
R="$(repo)"
mkdir -p "$R/.github"
: > "$R/.github/pull_request_template.md"
OUT="$(bash "$FIND" "$R")"; ST=$?
check "exit 3" 3 "$ST"

echo "[usage] a missing directory"
bash "$FIND" "$WORK/absent" >/dev/null 2>&1; ST=$?
check "exit 2" 2 "$ST"

echo ""
echo "passed: $PASS, failed: $FAIL"
[[ "$FAIL" -eq 0 ]]
