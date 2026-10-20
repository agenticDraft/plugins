#!/usr/bin/env bash
# check-spec.test.sh — Coverage for check-spec.py: one case per form rule it
# enforces, plus the readiness case a draft can fail without breaking any form
# rule (a visual change with no design reference attached).
#
# Every case is the conforming draft with one thing changed, written inline
# rather than shipped as a fixture file, so a case and the rule it covers stay
# in one place. The packs the checker resolves are the fixture packs under
# shared/fixtures/write-specs/, registered under other names in a project of
# this suite's own.
#
# Usage:
#   bash check-spec.test.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECKER="$SCRIPT_DIR/check-spec.py"
WRITER="$SCRIPT_DIR/write-item.py"
FIXTURES="$(cd "$SCRIPT_DIR/../../../shared/fixtures/write-specs" && pwd)"
# An explicit template, not a bare "mktemp -d": on this platform the bare form
# ignores TMPDIR and picks a per-user directory a sandboxed run may not write to.
TMP="$(mktemp -d "${TMPDIR:-/tmp}/check-spec.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0

# A project of its own: the fixture config, and a registry naming copies of
# the fixture packs in a folder with another name. No entry names the core.
PROJ="$TMP/project"
CACHE="$TMP/cache"
REG="$PROJ/.ai/run-context/plugin-roots"
mkdir -p "$PROJ/.ai" "$REG" "$CACHE"
cp "$FIXTURES/project-config.yaml" "$PROJ/.ai/project-config.yaml"
role_pack() { sed -n "s/^  $1: *//p" "$PROJ/.ai/project-config.yaml"; }
register() { printf '%s\n' "$2" > "$REG/$1"; }
PLATFORM="$(role_pack platform)"
TRACKER="$(role_pack tracker)"
cp -R "$FIXTURES/platform-pack" "$CACHE/$PLATFORM"
cp -R "$FIXTURES/tracker-pack" "$CACHE/$TRACKER"
register "$PLATFORM" "$CACHE/$PLATFORM"
register "$TRACKER" "$CACHE/$TRACKER"

# A draft that satisfies every rule.
clean_draft() {
  cat <<'EOF'
---
item_type: Story
summary: Features carousel component
---

## Description

Add a features carousel to components/features-carousel/, authored through the
project's standard table-based content model.

## Design reference

https://design.example/files/sample?node=1-167

## Acceptance criteria

AC-1 A component directory components/features-carousel/ exists.
AC-2 Every spacing value resolves to an adopted design-system token.

## Out of scope

Any change to another component.
EOF
}

# run_in <label> <expected exit> <expected substring> <command...> — in $PROJ
run_in() {
  local label="$1" expected_exit="$2" expected="$3" out actual_exit
  shift 3
  out="$(cd "$PROJ" && CLAUDE_PROJECT_DIR="$PROJ" "$@" 2>&1)"
  actual_exit=$?
  if [[ "$actual_exit" == "$expected_exit" && "$out" == *"$expected"* ]]; then
    echo "  ok: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label"
    echo "    expected exit $expected_exit containing: $expected"
    echo "    got exit $actual_exit:"
    echo "$out" | sed 's/^/      /'
    FAIL=$((FAIL + 1))
  fi
}

# run_case <label> <expected exit> <expected substring> <draft text>
# The draft arrives as an argument rather than on stdin: a pipeline would run
# this function in a subshell, and the pass/fail counters would never survive it.
run_case() {
  local label="$1" expected_exit="$2" expected="$3" draft_text="$4"
  local draft="$TMP/${label// /-}.md"
  printf '%s\n' "$draft_text" > "$draft"
  run_in "$label" "$expected_exit" "$expected" python3 "$CHECKER" "$draft"
}

echo "[accepts a conforming draft]"
run_case "clean story" 0 "valid: write-specs" "$(clean_draft)"

echo "[form violations]"
run_case "criterion with no id" 1 "carries no AC-<n> id" \
  "$(clean_draft | sed 's|^AC-1 A component directory|- A component directory|')"

run_case "ids not sequential" 1 "not sequential from 1" \
  "$(clean_draft | sed 's|^AC-2 |AC-4 |')"

run_case "semicolon in a criterion" 1 "semicolon" \
  "$(clean_draft | sed 's|^AC-2 .*|AC-2 Spacing resolves to a token; colour does too.|')"

run_case "unverifiable wording" 1 "no pass/fail threshold" \
  "$(clean_draft | sed 's|^AC-2 .*|AC-2 The component renders properly.|')"

run_case "two sentences in a criterion" 1 "more than one sentence" \
  "$(clean_draft | sed 's|^AC-2 .*|AC-2 The list renders. The button renders.|')"

run_case "no out-of-scope section" 1 "an out-of-scope section" \
  "$(clean_draft | sed '/^## Out of scope$/,$d')"

run_case "summary is a sentence" 1 "ends in a full stop" \
  "$(clean_draft | sed 's|^summary: .*|summary: Add a features carousel component to the project.|')"

run_case "summary too long" 1 "more than 8" \
  "$(clean_draft | sed 's|^summary: .*|summary: Features carousel component with a numbered list and a button image|')"

run_case "component path without its slash" 1 "no trailing slash" \
  "$(clean_draft | sed 's|components/features-carousel/ exists|components/features-carousel exists|')"

echo "[readiness, not form]"
run_case "visual change with no design reference" 1 "readiness would fail" \
  "$(clean_draft | sed '/^https:\/\/design.example/d')"

echo "[item type with its own rules]"
run_case "bug with no reproduction steps" 1 "reproduction steps" \
  "$(clean_draft | sed 's|^item_type: Story|item_type: Bug|')"

echo "[content an item cites]"
run_case "keyed item citing another item's content" 1 "requires 'reproduction_content_ok'" \
  "$(clean_draft | sed 's|^item_type: Story|item_type: Story\
item_id: ITEM-99|; s|^project.s standard.*|&\
Open https://content.example/items/ITEM-18 to see it.|')"
run_case "keyless draft citing content" 0 "review: reproduction_content_ok not checked" \
  "$(clean_draft | sed 's|^project.s standard.*|&\
Open https://content.example/items/new-item to see it.|')"

echo "[review notes do not fail the run]"
run_case "criterion joined with and" 0 "review: AC-2 contains 'and'" \
  "$(clean_draft | sed 's|^AC-2 .*|AC-2 The list and the button render through the global styles.|')"

echo "[the component-path rule comes from the platform pack]"
NOSLASH="$(clean_draft | sed 's|components/features-carousel/ exists|components/features-carousel exists|')"
cp -R "$CACHE/$PLATFORM" "$CACHE/no-key"
sed -i.bak '/^authoring_examples_path:/d' "$CACHE/no-key/pack.yaml"
register "$PLATFORM" "$CACHE/no-key"
run_case "no authoring_examples_path, rule not run" 0 "not run: component-path rule" "$NOSLASH"
run_in "no authoring_examples_path, no examples" 0 "examples: none" \
  python3 "$CHECKER" --examples

cp -R "$CACHE/$PLATFORM" "$CACHE/no-file"
rm "$CACHE/no-file/examples/component-path.txt"
register "$PLATFORM" "$CACHE/no-file"
run_case "no component-path.txt, rule not run" 0 "not run: component-path rule" "$NOSLASH"

cp -R "$CACHE/$PLATFORM" "$CACHE/bad-pattern"
printf '%s\n' 'components/[' > "$CACHE/bad-pattern/examples/component-path.txt"
register "$PLATFORM" "$CACHE/bad-pattern"
run_case "a pattern that does not compile" 2 "component-path.txt:1" "$(clean_draft)"
register "$PLATFORM" "$CACHE/$PLATFORM"

echo "[the platform's worked example]"
# The resolver answers a canonical root, which can spell $CACHE another way.
run_in "examples lists the pack's drafts" 0 "/$PLATFORM/examples/story.md" \
  python3 "$CHECKER" --examples
run_in "the pack's worked example passes" 0 "valid: write-specs" \
  python3 "$CHECKER" "$CACHE/$PLATFORM/examples/story.md"

echo "[plugin roots come from the resolver]"
clean_draft > "$TMP/registry.md"

run_in "checks a draft against the registered copies" 0 "valid: write-specs" \
  python3 "$CHECKER" "$TMP/registry.md"
if [[ -e "$REG/agentic-core" ]]; then
  echo "  FAIL: no core registry entry is needed"
  FAIL=$((FAIL + 1))
else
  run_in "no core registry entry is needed" 0 "valid: write-specs" \
    python3 "$CHECKER" "$TMP/registry.md"
fi
run_in "write-item reaches the registered tracker pack" 2 "this is a create" \
  python3 "$WRITER" "$TMP/registry.md"

register "$TRACKER" "$TMP/gone"
run_in "a stale pack entry is refused" 2 "refused: $TRACKER" \
  python3 "$CHECKER" "$TMP/registry.md"
run_in "write-item refuses a stale pack entry" 2 "refused: $TRACKER" \
  python3 "$WRITER" "$TMP/registry.md"
register "$TRACKER" "$CACHE/$TRACKER"

register "$PLATFORM" "$TMP/gone"
run_in "a stale platform entry is refused" 2 "refused: $PLATFORM" \
  python3 "$CHECKER" "$TMP/registry.md"
rm "$REG/$PLATFORM"
run_in "no platform entry is not resolved" 2 "not resolved: $PLATFORM" \
  python3 "$CHECKER" "$TMP/registry.md"
register "$PLATFORM" "$CACHE/$PLATFORM"

# Both spellings: a path literal, and a path built from a "plugins" segment.
if grep -nE "plugins/|[\"']plugins[\"']" "$CHECKER" "$WRITER"; then
  echo "  FAIL: a script names a plugins/ path"
  FAIL=$((FAIL + 1))
else
  echo "  ok: neither script names a plugins/ path"
  PASS=$((PASS + 1))
fi

echo
echo "passed: $PASS  failed: $FAIL"
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
