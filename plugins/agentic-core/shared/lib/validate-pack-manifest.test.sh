#!/usr/bin/env bash
# Tests for validate-pack-manifest.sh. Run with:
#   bash plugins/agentic-core/shared/lib/validate-pack-manifest.test.sh
#
# No framework — exits 0 on success, 1 if any case failed. assert_exit below
# compares expected vs. actual exit code per case, against fixture inputs.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATOR="$SCRIPT_DIR/validate-pack-manifest.sh"
EVALUATOR="$SCRIPT_DIR/evaluate-stage-conditions.sh"
FIXDIR="$SCRIPT_DIR/../fixtures/pack-manifest"
FACT_CONTRACT="$SCRIPT_DIR/../fact-record.md"

PASS=0
FAIL=0

assert_exit() {
  local desc="$1" expected="$2" actual="$3" output="$4"
  if [[ "$expected" == "$actual" ]]; then
    PASS=$((PASS + 1)); echo "  ok: $desc"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: $desc"
    echo "    expected exit=$expected, got exit=$actual"
    [[ -n "$output" ]] && echo "    output: $output"
  fi
}

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    PASS=$((PASS + 1)); echo "  ok: $desc"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: $desc"
    echo "    expected output to contain: $needle"
    echo "    got: $haystack"
  fi
}

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    PASS=$((PASS + 1)); echo "  ok: $desc"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: $desc"
    echo "    expected: $expected"
    echo "    actual:   $actual"
  fi
}

echo "=== validate-pack-manifest.sh tests ==="

# --- accepted shapes --------------------------------------------------------

echo "[accept] a platform manifest whose stages are all always-on"
OUT=$(bash "$VALIDATOR" "$FIXDIR/platform-valid/pack.yaml" 2>&1); ST=$?
assert_exit "platform-valid accepted (exit 0)" 0 $ST "$OUT"
assert_contains "reports kind" "platform" "$OUT"

echo "[accept] a platform manifest with a conditional stage"
OUT=$(bash "$VALIDATOR" "$FIXDIR/platform-valid-conditions/pack.yaml" 2>&1); ST=$?
assert_exit "platform-valid-conditions accepted (exit 0)" 0 $ST "$OUT"

echo "[accept] a platform manifest declaring all fifteen stages"
OUT=$(bash "$VALIDATOR" "$FIXDIR/platform-valid-full-route/pack.yaml" 2>&1); ST=$?
assert_exit "platform-valid-full-route accepted (exit 0)" 0 $ST "$OUT"

echo "[accept] a platform manifest declaring onboarding_state_path and audit_findings_path (D80)"
OUT=$(bash "$VALIDATOR" "$FIXDIR/platform-valid-onboarding/pack.yaml" 2>&1); ST=$?
assert_exit "platform-valid-onboarding accepted (exit 0)" 0 $ST "$OUT"
assert_contains "still reaches the trailing unexpected-content check" "valid: platform" "$OUT"

echo "[accept] validator 16 — evidence_manifest naming an artifact this pack registers (D86)"
OUT=$(bash "$VALIDATOR" "$FIXDIR/platform-valid-evidence-manifest/pack.yaml" 2>&1); ST=$?
assert_exit "platform-valid-evidence-manifest accepted (exit 0)" 0 $ST "$OUT"
assert_contains "still passes the trailing unexpected-content check" "valid: platform" "$OUT"

echo "[reject] validator 16 — evidence_manifest naming an artifact this pack does not register"
OUT=$(bash "$VALIDATOR" "$FIXDIR/platform-invalid/evidence-manifest-unregistered/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the unregistered id" "not-a-real-artifact" "$OUT"
assert_contains "reason names the failure precisely" "does not register" "$OUT"
[[ "$OUT" != *"unexpected content"* ]]
assert_exit "reason does not misdiagnose as unexpected content" 0 $? ""
[[ "$OUT" != *"expected "* ]]
assert_exit "reason does not misdiagnose as a parse error" 0 $? ""

echo "[validator 22] branch_name (D544, D129) — built from an existing fixture in a temp dir"
BN_WORK=$(mktemp -d "${TMPDIR:-/tmp}/pack-manifest-branch-name.XXXXXX") || { echo "cannot create a temp dir" >&2; exit 2; }
[[ -n "$BN_WORK" && -d "$BN_WORK" ]] || { echo "cannot create a temp dir" >&2; exit 2; }
trap 'rm -rf "$BN_WORK"' EXIT

# with_branch_name <fixture> <case> <lines…> — the fixture copied, with lines appended
with_branch_name() {
  local fixture="$1" case_dir="$BN_WORK/$2"; shift 2
  cp -R "$FIXDIR/$fixture" "$case_dir"
  printf '%s\n' "$@" >> "$case_dir/pack.yaml"
  echo "$case_dir/pack.yaml"
}

M=$(with_branch_name platform-valid-evidence-manifest after-em "branch_name:" '  pattern: "^[a-z0-9/-]+$"')
OUT=$(bash "$VALIDATOR" "$M" 2>&1); ST=$?
assert_exit "pattern after evidence_manifest accepted" 0 $ST "$OUT"
M=$(with_branch_name platform-valid pattern-only "branch_name:" '  pattern: "^[a-z-]+$"')
OUT=$(bash "$VALIDATOR" "$M" 2>&1); ST=$?
assert_exit "pattern only, no other optional key, accepted" 0 $ST "$OUT"

echo "[validator 22] max_length is the project's, not the pack's (D129)"
for lines in "  max_length: 23" $'  max_length: 23\n  pattern: "^[a-z-]+$"'; do
  M=$(with_branch_name platform-valid "len-$RANDOM" "branch_name:" "$lines")
  OUT=$(bash "$VALIDATOR" "$M" 2>&1); ST=$?
  assert_exit "max_length in the manifest rejected ($(printf '%s' "$lines" | wc -l | tr -d ' ') more line(s))" 1 $ST "$OUT"
  assert_contains "says where max_length lives" "project config" "$OUT"
done

M=$(with_branch_name platform-valid empty "branch_name:")
OUT=$(bash "$VALIDATOR" "$M" 2>&1); ST=$?
assert_exit "no sub-key rejected" 1 $ST "$OUT"
assert_contains "names the key" "branch_name" "$OUT"
M=$(with_branch_name platform-valid empty-pattern "branch_name:" '  pattern: ""')
OUT=$(bash "$VALIDATOR" "$M" 2>&1); ST=$?
assert_exit "empty pattern rejected" 1 $ST "$OUT"
assert_contains "names pattern" "pattern" "$OUT"
M=$(with_branch_name platform-valid broken-pattern "branch_name:" '  pattern: "[a-"')
OUT=$(bash "$VALIDATOR" "$M" 2>&1); ST=$?
assert_exit "pattern that does not compile rejected" 1 $ST "$OUT"
assert_contains "says it does not compile" "compile" "$OUT"
M=$(with_branch_name platform-valid unquoted "branch_name:" "  pattern: ^[a-z]+$")
OUT=$(bash "$VALIDATOR" "$M" 2>&1); ST=$?
assert_exit "unquoted pattern rejected" 1 $ST "$OUT"
M=$(with_branch_name platform-valid unknown-sub "branch_name:" '  pattern: "^[a-z-]+$"' "  min_length: 3")
OUT=$(bash "$VALIDATOR" "$M" 2>&1); ST=$?
assert_exit "unknown sub-key rejected" 1 $ST "$OUT"

echo "[validator 23] reference_docs (D117)"
M=$(with_branch_name platform-valid rd-after-branch "branch_name:" '  pattern: "^[a-z-]+$"' 'reference_docs: "https://docs.example.org/en-US/"')
OUT=$(bash "$VALIDATOR" "$M" 2>&1); ST=$?
assert_exit "reference_docs after branch_name accepted" 0 $ST "$OUT"
M=$(with_branch_name platform-valid rd-alone 'reference_docs: "https://docs.example.org/"')
OUT=$(bash "$VALIDATOR" "$M" 2>&1); ST=$?
assert_exit "reference_docs as the only optional key accepted" 0 $ST "$OUT"
for bad in '"http://docs.example.org/"' 'https://docs.example.org/' '""' '"https://a b"'; do
  M=$(with_branch_name platform-valid "rd-bad-$RANDOM" "reference_docs: $bad")
  OUT=$(bash "$VALIDATOR" "$M" 2>&1); ST=$?
  assert_exit "reference_docs $bad rejected" 1 $ST "$OUT"
  assert_contains "reference_docs $bad → names the key" "reference_docs" "$OUT"
done
M=$(with_branch_name platform-valid rd-before-branch 'reference_docs: "https://docs.example.org/"' "branch_name:" '  pattern: "^[a-z-]+$"')
OUT=$(bash "$VALIDATOR" "$M" 2>&1); ST=$?
assert_exit "a key after reference_docs rejected (it is last)" 1 $ST "$OUT"
M=$(with_branch_name platform-valid-evidence-manifest wrong-order "branch_name:" '  pattern: "^[a-z-]+$"' "evidence_manifest: change-summary")
OUT=$(bash "$VALIDATOR" "$M" 2>&1); ST=$?
assert_exit "a key after branch_name rejected (fixed order)" 1 $ST "$OUT"

echo "[accept] a well-formed provider manifest"
OUT=$(bash "$VALIDATOR" "$FIXDIR/provider-valid/pack.yaml" 2>&1); ST=$?
assert_exit "provider-valid accepted (exit 0)" 0 $ST "$OUT"
assert_contains "reports kind" "provider" "$OUT"

echo "[accept] a provider that implements nothing yet — 'operations: {}', every operation unsupported"
PROV_TMP="$(mktemp -d "${TMPDIR:-/tmp}/validate-pack-manifest-provider.XXXXXX")"
cp -R "$FIXDIR/provider-valid/." "$PROV_TMP/"
cat > "$PROV_TMP/pack.yaml" <<'EOF'
kind: provider
role: design
operations: {}
unsupported: [fetch_reference]
EOF
OUT=$(bash "$VALIDATOR" "$PROV_TMP/pack.yaml" 2>&1); ST=$?
assert_exit "empty operations map accepted (exit 0)" 0 $ST "$OUT"
assert_contains "reports kind" "valid: provider" "$OUT"

echo "[accept] text_conventions carrying only the new acceptance_criteria_headings key"
cat > "$PROV_TMP/pack.yaml" <<'EOF'
kind: provider
role: tracker
operations:
  fetch_item: fetch
  post_note: note
  attach_file: attach
  list_types: list
unsupported: [create_item, update_item]
text_conventions:
  acceptance_criteria_headings: [Acceptance Criteria, AC]
EOF
OUT=$(bash "$VALIDATOR" "$PROV_TMP/pack.yaml" 2>&1); ST=$?
assert_exit "accepted (exit 0)" 0 $ST "$OUT"

echo "[accept] text_conventions carrying before_state_keywords"
cat > "$PROV_TMP/pack.yaml" <<'EOF'
kind: provider
role: tracker
operations:
  fetch_item: fetch
  post_note: note
  attach_file: attach
  list_types: list
unsupported: [create_item, update_item]
text_conventions:
  design_keywords: [design]
  before_state_keywords: [unchanged, same as before]
EOF
OUT=$(bash "$VALIDATOR" "$PROV_TMP/pack.yaml" 2>&1); ST=$?
assert_exit "accepted (exit 0)" 0 $ST "$OUT"

echo "[reject] text_conventions declared for a non-tracker role"
cat > "$PROV_TMP/pack.yaml" <<'EOF'
kind: provider
role: scm
operations:
  create_branch: fetch
  publish_change: note
  check_status: attach
unsupported: []
text_conventions:
  design_keywords: [design]
EOF
OUT=$(bash "$VALIDATOR" "$PROV_TMP/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the role" "belongs to the tracker role, not 'scm'" "$OUT"

echo "[accept] scripts naming an implemented operation whose path resolves (D95)"
mkdir -p "$PROV_TMP/skills/fetch/scripts"
echo '#!/usr/bin/env bash' > "$PROV_TMP/skills/fetch/scripts/fetch.sh"
cat > "$PROV_TMP/pack.yaml" <<'EOF'
kind: provider
role: tracker
operations:
  fetch_item: fetch
  post_note: note
  attach_file: attach
  list_types: list
unsupported: [create_item, update_item]
scripts:
  fetch_item: "skills/fetch/scripts/fetch.sh"
EOF
OUT=$(bash "$VALIDATOR" "$PROV_TMP/pack.yaml" 2>&1); ST=$?
assert_exit "accepted (exit 0)" 0 $ST "$OUT"

echo "[accept] an scm pack's scripts.check_status (the change-state caller's script form)"
for s in branch publish status; do
  mkdir -p "$PROV_TMP/skills/$s"
  cp "$PROV_TMP/skills/fetch/SKILL.md" "$PROV_TMP/skills/$s/SKILL.md"
done
mkdir -p "$PROV_TMP/skills/status/scripts"
echo '#!/usr/bin/env bash' > "$PROV_TMP/skills/status/scripts/status.sh"
cat > "$PROV_TMP/pack.yaml" <<'EOF'
kind: provider
role: scm
operations:
  create_branch: branch
  publish_change: publish
  check_status: status
unsupported: []
scripts:
  check_status: "skills/status/scripts/status.sh"
EOF
OUT=$(bash "$VALIDATOR" "$PROV_TMP/pack.yaml" 2>&1); ST=$?
assert_exit "accepted (exit 0)" 0 $ST "$OUT"

echo "[reject] scripts names an operation this pack does not implement"
cat > "$PROV_TMP/pack.yaml" <<'EOF'
kind: provider
role: tracker
operations:
  fetch_item: fetch
  post_note: note
  attach_file: attach
unsupported: [list_types, create_item, update_item]
scripts:
  list_types: "skills/fetch/scripts/fetch.sh"
EOF
OUT=$(bash "$VALIDATOR" "$PROV_TMP/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the operation" "scripts.list_types names an operation this pack does not implement" "$OUT"

echo "[reject] scripts names a script that does not exist"
cat > "$PROV_TMP/pack.yaml" <<'EOF'
kind: provider
role: tracker
operations:
  fetch_item: fetch
  post_note: note
  attach_file: attach
  list_types: list
unsupported: [create_item, update_item]
scripts:
  fetch_item: "skills/fetch/scripts/does-not-exist.sh"
EOF
OUT=$(bash "$VALIDATOR" "$PROV_TMP/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the missing script" "does not exist" "$OUT"

echo "[reject] scripts present but empty"
cat > "$PROV_TMP/pack.yaml" <<'EOF'
kind: provider
role: tracker
operations:
  fetch_item: fetch
  post_note: note
  attach_file: attach
  list_types: list
unsupported: [create_item, update_item]
scripts:
EOF
OUT=$(bash "$VALIDATOR" "$PROV_TMP/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason says omit the key" "omit the key instead" "$OUT"

# --- the authoring write operations -----------------------------------------
# create_item and update_item joined the tracker role after the other four, so
# these three cases pin the states a tracker pack can be in while the packs
# catch up: implementing them, declining them, and saying nothing about them.
# The third is the one that matters — a pack silently missing an operation is
# how a caller discovers the gap at run time instead of at validation.

echo "[accept] a tracker implementing the authoring write operations"
mkdir -p "$PROV_TMP/skills/create" "$PROV_TMP/skills/update"
: > "$PROV_TMP/skills/create/SKILL.md"
: > "$PROV_TMP/skills/update/SKILL.md"
cat > "$PROV_TMP/pack.yaml" <<'EOF'
kind: provider
role: tracker
operations:
  fetch_item: fetch
  post_note: note
  attach_file: attach
  list_types: list
  create_item: create
  update_item: update
unsupported: []
EOF
OUT=$(bash "$VALIDATOR" "$PROV_TMP/pack.yaml" 2>&1); ST=$?
assert_exit "accepted (exit 0)" 0 $ST "$OUT"

echo "[reject] a tracker naming create_item but shipping no such skill"
cat > "$PROV_TMP/pack.yaml" <<'EOF'
kind: provider
role: tracker
operations:
  fetch_item: fetch
  post_note: note
  attach_file: attach
  list_types: list
  create_item: nonexistent
  update_item: update
unsupported: []
EOF
OUT=$(bash "$VALIDATOR" "$PROV_TMP/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the missing skill" "operations.create_item names a nonexistent skill" "$OUT"

echo "[reject] a tracker silent about the authoring write operations"
cat > "$PROV_TMP/pack.yaml" <<'EOF'
kind: provider
role: tracker
operations:
  fetch_item: fetch
  post_note: note
  attach_file: attach
  list_types: list
unsupported: []
EOF
OUT=$(bash "$VALIDATOR" "$PROV_TMP/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the operation left out" "create_item" "$OUT"

echo "[accept] validator 18 — requires declaring a tool, an argv probe and a remedy (D97)"
cat > "$PROV_TMP/pack.yaml" <<'EOF'
kind: provider
role: browser
operations: {}
unsupported: [render, capture, measure, interact]
requires:
  - tool: example-tool
    probe: [example-tool, --version]
    remedy: "install example-tool, then download its runtime"
EOF
OUT=$(bash "$VALIDATOR" "$PROV_TMP/pack.yaml" 2>&1); ST=$?
assert_exit "accepted (exit 0)" 0 $ST "$OUT"
assert_contains "still reports the kind" "valid: provider" "$OUT"

echo "[accept] validator 18 — two entries, and a pack declaring none"
cat > "$PROV_TMP/pack.yaml" <<'EOF'
kind: provider
role: browser
operations: {}
unsupported: [render, capture, measure, interact]
requires:
  - tool: example-tool
    probe: [example-tool, --version]
    remedy: "install example-tool"
  - tool: example-runtime
    probe: [example-tool, list-runtimes]
    remedy: "download the runtime through example-tool"
EOF
OUT=$(bash "$VALIDATOR" "$PROV_TMP/pack.yaml" 2>&1); ST=$?
assert_exit "two entries accepted (exit 0)" 0 $ST "$OUT"
cat > "$PROV_TMP/pack.yaml" <<'EOF'
kind: provider
role: design
operations: {}
unsupported: [fetch_reference]
EOF
OUT=$(bash "$VALIDATOR" "$PROV_TMP/pack.yaml" 2>&1); ST=$?
assert_exit "absent requires still accepted — absent means ungated (exit 0)" 0 $ST "$OUT"

echo "[reject] validator 18 — probe given as a string rather than argv"
cat > "$PROV_TMP/pack.yaml" <<'EOF'
kind: provider
role: design
operations: {}
unsupported: [fetch_reference]
requires:
  - tool: example-tool
    probe: "example-tool --version"
    remedy: "install example-tool"
EOF
OUT=$(bash "$VALIDATOR" "$PROV_TMP/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the tool and the expected shape" "requires.example-tool: expected 'probe: [<argv>" "$OUT"

echo "[reject] validator 18 — an empty probe list"
cat > "$PROV_TMP/pack.yaml" <<'EOF'
kind: provider
role: design
operations: {}
unsupported: [fetch_reference]
requires:
  - tool: example-tool
    probe: []
    remedy: "install example-tool"
EOF
OUT=$(bash "$VALIDATOR" "$PROV_TMP/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason says a probe that runs nothing answers nothing" "cannot answer whether the tool is present" "$OUT"

echo "[reject] validator 18 — a missing remedy"
cat > "$PROV_TMP/pack.yaml" <<'EOF'
kind: provider
role: design
operations: {}
unsupported: [fetch_reference]
requires:
  - tool: example-tool
    probe: [example-tool, --version]
EOF
OUT=$(bash "$VALIDATOR" "$PROV_TMP/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names remedy" "remedy" "$OUT"

echo "[reject] validator 18 — an empty remedy"
cat > "$PROV_TMP/pack.yaml" <<'EOF'
kind: provider
role: design
operations: {}
unsupported: [fetch_reference]
requires:
  - tool: example-tool
    probe: [example-tool, --version]
    remedy: ""
EOF
OUT=$(bash "$VALIDATOR" "$PROV_TMP/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason says a missing tool with no remedy is a dead end" "dead end" "$OUT"

echo "[accept] validator 18 — a probe naming a script the pack ships (<pack>/ prefix)"
mkdir -p "$PROV_TMP/scripts"
printf '#!/usr/bin/env bash\nexit 0\n' > "$PROV_TMP/scripts/probe-tool.sh"
cat > "$PROV_TMP/pack.yaml" <<'EOF'
kind: provider
role: design
operations: {}
unsupported: [fetch_reference]
requires:
  - tool: example-tool
    probe: [bash, <pack>/scripts/probe-tool.sh, module]
    remedy: "install example-tool"
EOF
OUT=$(bash "$VALIDATOR" "$PROV_TMP/pack.yaml" 2>&1); ST=$?
assert_exit "accepted (exit 0)" 0 $ST "$OUT"

echo "[reject] validator 18 — a <pack>/ probe naming a file the pack does not ship"
cat > "$PROV_TMP/pack.yaml" <<'EOF'
kind: provider
role: design
operations: {}
unsupported: [fetch_reference]
requires:
  - tool: example-tool
    probe: [bash, <pack>/scripts/does-not-exist.sh]
    remedy: "install example-tool"
EOF
OUT=$(bash "$VALIDATOR" "$PROV_TMP/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the missing file" "does not ship" "$OUT"

echo "[reject] validator 18 — a <pack>/ probe escaping the pack root"
cat > "$PROV_TMP/pack.yaml" <<'EOF'
kind: provider
role: design
operations: {}
unsupported: [fetch_reference]
requires:
  - tool: example-tool
    probe: [bash, <pack>/../escape.sh]
    remedy: "install example-tool"
EOF
OUT=$(bash "$VALIDATOR" "$PROV_TMP/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the path segment" "'..'" "$OUT"

echo "[reject] validator 18 — requires present but empty"
cat > "$PROV_TMP/pack.yaml" <<'EOF'
kind: provider
role: design
operations: {}
unsupported: [fetch_reference]
requires:
EOF
OUT=$(bash "$VALIDATOR" "$PROV_TMP/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason says omit the key" "omit the key instead" "$OUT"

echo "[accept] validator 18 — requires on a platform pack (D137)"
PLAT_TMP="$(mktemp -d "${TMPDIR:-/tmp}/validate-pack-manifest-platform.XXXXXX")"
cp -R "$FIXDIR/platform-valid/." "$PLAT_TMP/"
printf 'requires:\n  - tool: example-tool\n    probe: [example-tool, --version]\n    remedy: "install example-tool"\n' \
  >> "$PLAT_TMP/pack.yaml"
OUT=$(bash "$VALIDATOR" "$PLAT_TMP/pack.yaml" 2>&1); ST=$?
assert_exit "accepted (exit 0)" 0 $ST "$OUT"
assert_contains "still reports the kind" "valid: platform" "$OUT"

echo "[reject] validator 18 — a malformed requires on a platform pack is held to the same shape"
cp "$FIXDIR/platform-valid/pack.yaml" "$PLAT_TMP/pack.yaml"
printf 'requires:\n  - tool: example-tool\n    probe: "example-tool --version"\n    remedy: "install example-tool"\n' \
  >> "$PLAT_TMP/pack.yaml"
OUT=$(bash "$VALIDATOR" "$PLAT_TMP/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the tool and the expected shape" "requires.example-tool: expected 'probe: [<argv>" "$OUT"
rm -rf "$PLAT_TMP"

echo "[accept] validator 24 — session_tools declaring a tool and a remedy"
cat > "$PROV_TMP/pack.yaml" <<'EOF'
kind: provider
role: design
operations: {}
unsupported: [fetch_reference]
session_tools:
  - tool: mcp__example-server__read_item
    remedy: "enable the example plugin, then restart the session"
EOF
OUT=$(bash "$VALIDATOR" "$PROV_TMP/pack.yaml" 2>&1); ST=$?
assert_exit "accepted (exit 0)" 0 $ST "$OUT"
assert_contains "still reports the kind" "valid: provider" "$OUT"

echo "[accept] validator 24 — two entries after a requires block"
cat > "$PROV_TMP/pack.yaml" <<'EOF'
kind: provider
role: design
operations: {}
unsupported: [fetch_reference]
requires:
  - tool: example-tool
    probe: [example-tool, --version]
    remedy: "install example-tool"
session_tools:
  - tool: mcp__example-server__read_item
    remedy: "enable the example plugin"
  - tool: mcp__example-server__read_image
    remedy: "enable the example plugin"
EOF
OUT=$(bash "$VALIDATOR" "$PROV_TMP/pack.yaml" 2>&1); ST=$?
assert_exit "accepted (exit 0)" 0 $ST "$OUT"

echo "[reject] validator 24 — an empty tool name"
cat > "$PROV_TMP/pack.yaml" <<'EOF'
kind: provider
role: design
operations: {}
unsupported: [fetch_reference]
session_tools:
  - tool:
    remedy: "enable the example plugin"
EOF
OUT=$(bash "$VALIDATOR" "$PROV_TMP/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the empty tool" "session_tools: an entry declares an empty 'tool'" "$OUT"

echo "[reject] validator 24 — a tool name that is a pattern, not a registered name"
cat > "$PROV_TMP/pack.yaml" <<'EOF'
kind: provider
role: design
operations: {}
unsupported: [fetch_reference]
session_tools:
  - tool: mcp__example-server__*
    remedy: "enable the example plugin"
EOF
OUT=$(bash "$VALIDATOR" "$PROV_TMP/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the tool and the allowed characters" "session_tools.mcp__example-server__*: 'tool' must be an exact tool name" "$OUT"

echo "[reject] validator 24 — a missing remedy"
cat > "$PROV_TMP/pack.yaml" <<'EOF'
kind: provider
role: design
operations: {}
unsupported: [fetch_reference]
session_tools:
  - tool: mcp__example-server__read_item
EOF
OUT=$(bash "$VALIDATOR" "$PROV_TMP/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the tool and remedy" "session_tools.mcp__example-server__read_item: expected 'remedy:" "$OUT"

echo "[reject] validator 24 — an empty remedy"
cat > "$PROV_TMP/pack.yaml" <<'EOF'
kind: provider
role: design
operations: {}
unsupported: [fetch_reference]
session_tools:
  - tool: mcp__example-server__read_item
    remedy: "  "
EOF
OUT=$(bash "$VALIDATOR" "$PROV_TMP/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason says the remedy is empty" "'remedy' is empty" "$OUT"

echo "[reject] validator 24 — the same tool declared twice"
cat > "$PROV_TMP/pack.yaml" <<'EOF'
kind: provider
role: design
operations: {}
unsupported: [fetch_reference]
session_tools:
  - tool: mcp__example-server__read_item
    remedy: "enable the example plugin"
  - tool: mcp__example-server__read_item
    remedy: "enable the example plugin"
EOF
OUT=$(bash "$VALIDATOR" "$PROV_TMP/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the duplicate" "session_tools: 'mcp__example-server__read_item' is declared twice" "$OUT"

echo "[reject] validator 24 — session_tools present but empty"
cat > "$PROV_TMP/pack.yaml" <<'EOF'
kind: provider
role: design
operations: {}
unsupported: [fetch_reference]
session_tools:
EOF
OUT=$(bash "$VALIDATOR" "$PROV_TMP/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason says omit the key" "'session_tools:' is present but declares no entries" "$OUT"

echo "[reject] validator 24 — session_tools on a platform pack"
PLAT_TMP="$(mktemp -d "${TMPDIR:-/tmp}/validate-pack-manifest-platform.XXXXXX")"
cp -R "$FIXDIR/platform-valid/." "$PLAT_TMP/"
printf 'session_tools:\n  - tool: mcp__example-server__read_item\n    remedy: "enable the example plugin"\n' \
  >> "$PLAT_TMP/pack.yaml"
OUT=$(bash "$VALIDATOR" "$PLAT_TMP/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the kind it belongs to" "session_tools belongs to a provider pack, not a platform pack" "$OUT"
rm -rf "$PLAT_TMP"

# --- env, hosts, ignore_paths (validator 26, D137) ---------------------------

# Writes a provider manifest whose tail (after `unsupported:`) is the
# argument, so each case below states only the block under test.
provider_with() {
  {
    printf 'kind: provider\nrole: design\noperations: {}\nunsupported: [fetch_reference]\n'
    printf '%s\n' "$1"
  } > "$PROV_TMP/pack.yaml"
}

echo "[accept] validator 26 — every declaration, in the fixed order, between requires and session_tools"
provider_with 'requires:
  - tool: example-tool
    probe: [example-tool, --version]
    remedy: "install example-tool"
env:
  - name: EXAMPLE_SITE
    source: "the host name of your example site"
  - name: EXAMPLE_API_TOKEN
    source: "example account settings, API tokens"
hosts: ["api.example.test", "*.example.test"]
ignore_paths: [".ai/example/", "example-drafts/", ".ai/example.log"]
session_tools:
  - tool: mcp__example-server__read_item
    remedy: "enable the example plugin"'
OUT=$(bash "$VALIDATOR" "$PROV_TMP/pack.yaml" 2>&1); ST=$?
assert_exit "accepted (exit 0)" 0 $ST "$OUT"
assert_contains "still reports the kind" "valid: provider" "$OUT"

echo "[accept] validator 26 — each declaration alone"
provider_with 'env:
  - name: EXAMPLE_API_TOKEN
    source: "example account settings"'
OUT=$(bash "$VALIDATOR" "$PROV_TMP/pack.yaml" 2>&1); ST=$?
assert_exit "env alone accepted (exit 0)" 0 $ST "$OUT"
provider_with 'hosts: ["api.example.test"]'
OUT=$(bash "$VALIDATOR" "$PROV_TMP/pack.yaml" 2>&1); ST=$?
assert_exit "hosts alone accepted (exit 0)" 0 $ST "$OUT"
provider_with 'ignore_paths: [".ai/example/"]'
OUT=$(bash "$VALIDATOR" "$PROV_TMP/pack.yaml" 2>&1); ST=$?
assert_exit "ignore_paths alone accepted (exit 0)" 0 $ST "$OUT"

echo "[reject] validator 26 — a value where a variable name belongs (committed fixture)"
OUT=$(bash "$VALIDATOR" "$FIXDIR/provider-invalid/env-value-as-name/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason says a name is expected" "env: 'name' must be a variable name" "$OUT"
[[ "$OUT" != *"sk-live"* ]]
assert_exit "the rejection does not echo the value back" 0 $? "$OUT"

echo "[reject] validator 26 — an assignment where a variable name belongs"
provider_with 'env:
  - name: EXAMPLE_API_TOKEN=abc123
    source: "example account settings"'
OUT=$(bash "$VALIDATOR" "$PROV_TMP/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason says a name is expected" "env: 'name' must be a variable name" "$OUT"
[[ "$OUT" != *"abc123"* ]]
assert_exit "the rejection does not echo the value back" 0 $? "$OUT"

echo "[reject] validator 26 — a quoted or lower-case name"
provider_with 'env:
  - name: "EXAMPLE_API_TOKEN"
    source: "example account settings"'
OUT=$(bash "$VALIDATOR" "$PROV_TMP/pack.yaml" 2>&1); ST=$?
assert_exit "a quoted name rejected (exit 1)" 1 $ST "$OUT"
provider_with 'env:
  - name: example_api_token
    source: "example account settings"'
OUT=$(bash "$VALIDATOR" "$PROV_TMP/pack.yaml" 2>&1); ST=$?
assert_exit "a lower-case name rejected (exit 1)" 1 $ST "$OUT"

echo "[reject] validator 26 — an entry carrying a value field"
provider_with 'env:
  - name: EXAMPLE_API_TOKEN
    source: "example account settings"
    value: "abc123"'
OUT=$(bash "$VALIDATOR" "$PROV_TMP/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason says an entry has a name and a source only" "env.EXAMPLE_API_TOKEN: an entry declares 'name' and 'source' only" "$OUT"
[[ "$OUT" != *"abc123"* ]]
assert_exit "the rejection does not echo the value back" 0 $? "$OUT"

echo "[reject] validator 26 — a value field placed before the source"
provider_with 'env:
  - name: EXAMPLE_API_TOKEN
    value: "abc123"
    source: "example account settings"'
OUT=$(bash "$VALIDATOR" "$PROV_TMP/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
[[ "$OUT" != *"abc123"* ]]
assert_exit "the rejection does not echo the value back" 0 $? "$OUT"

echo "[reject] validator 26 — a missing or empty source"
provider_with 'env:
  - name: EXAMPLE_API_TOKEN'
OUT=$(bash "$VALIDATOR" "$PROV_TMP/pack.yaml" 2>&1); ST=$?
assert_exit "a missing source rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the variable and source" "env.EXAMPLE_API_TOKEN: expected 'source:" "$OUT"
provider_with 'env:
  - name: EXAMPLE_API_TOKEN
    source: " "'
OUT=$(bash "$VALIDATOR" "$PROV_TMP/pack.yaml" 2>&1); ST=$?
assert_exit "an empty source rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason says the source is empty" "env.EXAMPLE_API_TOKEN: 'source' is empty" "$OUT"

echo "[reject] validator 26 — the same variable declared twice, and env present but empty"
provider_with 'env:
  - name: EXAMPLE_API_TOKEN
    source: "example account settings"
  - name: EXAMPLE_API_TOKEN
    source: "example account settings"'
OUT=$(bash "$VALIDATOR" "$PROV_TMP/pack.yaml" 2>&1); ST=$?
assert_exit "a duplicate rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the duplicate" "env: 'EXAMPLE_API_TOKEN' is declared twice" "$OUT"
provider_with 'env:'
OUT=$(bash "$VALIDATOR" "$PROV_TMP/pack.yaml" 2>&1); ST=$?
assert_exit "an empty env rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason says omit the key" "'env:' is present but declares no entries" "$OUT"

echo "[reject] validator 26 — a host with a scheme, a port, a path, upper case, a bare word or no quotes"
for bad in '"https://api.example.test"' '"api.example.test:443"' '"api.example.test/rest"' \
           '"API.example.test"' '"localhost"' 'api.example.test' '"*example.test"' '"a.*.example.test"'; do
  provider_with "hosts: [$bad]"
  OUT=$(bash "$VALIDATOR" "$PROV_TMP/pack.yaml" 2>&1); ST=$?
  assert_exit "hosts: [$bad] rejected (exit 1)" 1 $ST "$OUT"
done
assert_contains "reason names the expected form" "hosts: each entry must be a double-quoted host name or '*.<domain>'" "$OUT"

echo "[reject] validator 26 — hosts empty, or a host declared twice"
provider_with 'hosts: []'
OUT=$(bash "$VALIDATOR" "$PROV_TMP/pack.yaml" 2>&1); ST=$?
assert_exit "an empty list rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason says omit the key" "'hosts:' is present but declares no entries" "$OUT"
provider_with 'hosts: ["api.example.test", "api.example.test"]'
OUT=$(bash "$VALIDATOR" "$PROV_TMP/pack.yaml" 2>&1); ST=$?
assert_exit "a duplicate rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the duplicate" "hosts: 'api.example.test' is declared twice" "$OUT"

echo "[reject] validator 26 — an ignore path that is absolute, escapes, globs or is unquoted"
for bad in '"/tmp/example/"' '"../example/"' '"a/../../b/"' '"*.log"' '"example/**/"' '"example[1]/"' \
           '".ai/example/"x' '.ai/example/' '""'; do
  provider_with "ignore_paths: [$bad]"
  OUT=$(bash "$VALIDATOR" "$PROV_TMP/pack.yaml" 2>&1); ST=$?
  assert_exit "ignore_paths: [$bad] rejected (exit 1)" 1 $ST "$OUT"
done

echo "[reject] validator 26 — ignore_paths empty, or a path declared twice"
provider_with 'ignore_paths: []'
OUT=$(bash "$VALIDATOR" "$PROV_TMP/pack.yaml" 2>&1); ST=$?
assert_exit "an empty list rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason says omit the key" "'ignore_paths:' is present but declares no entries" "$OUT"
provider_with 'ignore_paths: [".ai/example/", ".ai/example/"]'
OUT=$(bash "$VALIDATOR" "$PROV_TMP/pack.yaml" 2>&1); ST=$?
assert_exit "a duplicate rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the duplicate" "ignore_paths: '.ai/example/' is declared twice" "$OUT"

echo "[reject] validator 26 — a declaration out of its fixed place"
provider_with 'hosts: ["api.example.test"]
env:
  - name: EXAMPLE_API_TOKEN
    source: "example account settings"'
OUT=$(bash "$VALIDATOR" "$PROV_TMP/pack.yaml" 2>&1); ST=$?
assert_exit "env after hosts rejected (exit 1)" 1 $ST "$OUT"
provider_with 'session_tools:
  - tool: mcp__example-server__read_item
    remedy: "enable the example plugin"
ignore_paths: [".ai/example/"]'
OUT=$(bash "$VALIDATOR" "$PROV_TMP/pack.yaml" 2>&1); ST=$?
assert_exit "ignore_paths after session_tools rejected (exit 1)" 1 $ST "$OUT"

echo "[accept] validator 26 — a platform pack declaring all three, before reference_docs"
PLAT_TMP="$(mktemp -d "${TMPDIR:-/tmp}/validate-pack-manifest-platform.XXXXXX")"
cp -R "$FIXDIR/platform-valid/." "$PLAT_TMP/"
printf '%s\n' 'requires:' '  - tool: example-cli' '    probe: [example-cli, --version]' \
  '    remedy: "install example-cli"' 'env:' '  - name: EXAMPLE_ADMIN_KEY' \
  '    source: "the example admin console"' 'hosts: ["*.example.test"]' \
  'ignore_paths: ["example-drafts/"]' 'reference_docs: "https://example.test/docs"' >> "$PLAT_TMP/pack.yaml"
OUT=$(bash "$VALIDATOR" "$PLAT_TMP/pack.yaml" 2>&1); ST=$?
assert_exit "accepted (exit 0)" 0 $ST "$OUT"
assert_contains "still reports the kind" "valid: platform" "$OUT"

echo "[reject] validator 26 — a platform pack's declaration after reference_docs"
cp "$FIXDIR/platform-valid/pack.yaml" "$PLAT_TMP/pack.yaml"
printf '%s\n' 'reference_docs: "https://example.test/docs"' 'ignore_paths: ["example-drafts/"]' >> "$PLAT_TMP/pack.yaml"
OUT=$(bash "$VALIDATOR" "$PLAT_TMP/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
rm -rf "$PLAT_TMP"

rm -rf "$PROV_TMP"

# --- committed rejection fixtures -------------------------------------------

echo "[reject] always_autonomous binds an unknown stage"
OUT=$(bash "$VALIDATOR" "$FIXDIR/platform-invalid/unknown-stage-always-autonomous/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the unknown stage" "publish-gate" "$OUT"

echo "[reject] an artifact producer that is not a declared stage"
OUT=$(bash "$VALIDATOR" "$FIXDIR/platform-invalid/unknown-stage-artifact-producer/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the unknown stage" "prototype" "$OUT"

echo "[reject] a stage naming a nonexistent skill"
OUT=$(bash "$VALIDATOR" "$FIXDIR/platform-invalid/dangling-skill/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the missing skill" "nonexistent" "$OUT"

echo "[reject] a stage skill that does not declare isolated execution"
OUT=$(bash "$VALIDATOR" "$FIXDIR/platform-invalid/stage-not-isolated/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the missing declaration" "context: fork" "$OUT"

echo "[reject] an unfilled template placeholder under the pack root"
OUT=$(bash "$VALIDATOR" "$FIXDIR/platform-invalid/unfilled-placeholder/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the placeholder" "placeholder" "$OUT"

# An installed pack carries core/ as a real directory (git stores it as a
# symlink to agentic-core/shared; install unrolls it). That vendored copy, its
# tests, its fixtures and node_modules legitimately contain the marker.
echo "[accept] a marker inside a vendored core/, *.test.sh, fixtures/ and node_modules"
VEND_TMP="$(mktemp -d "${TMPDIR:-/tmp}/validate-pack-manifest-vendored.XXXXXX")"
cp -R "$FIXDIR/platform-valid/." "$VEND_TMP/"
mkdir -p "$VEND_TMP/core/lib" "$VEND_TMP/core/fixtures/x" "$VEND_TMP/node_modules/dep" "$VEND_TMP/fixtures"
echo 'x={{y}}' > "$VEND_TMP/core/lib/generate-pack.sh"
echo 'x={{y}}' > "$VEND_TMP/core/lib/generate-pack.test.sh"
echo 'x={{y}}' > "$VEND_TMP/core/fixtures/x/pack.yaml"
echo 'x={{y}}' > "$VEND_TMP/node_modules/dep/index.js"
echo 'x={{y}}' > "$VEND_TMP/fixtures/case.yaml"
echo 'x={{y}}' > "$VEND_TMP/pack.test.sh"
OUT=$(bash "$VALIDATOR" "$VEND_TMP/pack.yaml" 2>&1); ST=$?
assert_exit "accepted (exit 0)" 0 $ST "$OUT"

echo "[reject] a marker in generated skill content still fails"
echo 'Run {{command}} now' >> "$VEND_TMP/skills/intake/SKILL.md"
OUT=$(bash "$VALIDATOR" "$VEND_TMP/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "names the skill file" "skills/intake/SKILL.md" "$OUT"
rm -rf "$VEND_TMP"

echo "[reject] validator 1 — a stage id outside the fifteen"
OUT=$(bash "$VALIDATOR" "$FIXDIR/platform-invalid/stage-id-not-in-vocabulary/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the id" "deploy" "$OUT"
assert_contains "reason names the vocabulary" "fifteen" "$OUT"

echo "[reject] validator 12 — a when: key that is not a fact-record field"
OUT=$(bash "$VALIDATOR" "$FIXDIR/platform-invalid/when-unknown-field/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the field" "design_requested" "$OUT"

echo "[reject] validator 13 — no readiness_criteria at all"
OUT=$(bash "$VALIDATOR" "$FIXDIR/platform-invalid/no-readiness-criteria/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason explains the consequence" "fail every item" "$OUT"

echo "[reject] validator 13 — a criterion requiring a field the record lacks"
OUT=$(bash "$VALIDATOR" "$FIXDIR/platform-invalid/readiness-criteria-unknown-field/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the field" "has_mockup" "$OUT"

echo "[reject] validator 14 — a digraph node that is not a declared stage"
OUT=$(bash "$VALIDATOR" "$FIXDIR/platform-invalid/digraph-node-not-a-stage/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the node" "lint" "$OUT"

echo "[reject] validator 14 — a declared stage with no node"
OUT=$(bash "$VALIDATOR" "$FIXDIR/platform-invalid/digraph-missing-node/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the stage" "implement" "$OUT"

echo "[reject] validator 14 — an edge label that disagrees with the when:"
OUT=$(bash "$VALIDATOR" "$FIXDIR/platform-invalid/digraph-label-mismatch/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason prints the actual label" "is 'design_source=true'" "$OUT"
assert_contains "reason prints the expected rendering" "design_source=true OR design_mentioned=true" "$OUT"

echo "[reject] validator 15 — onboarding_state_path is absolute"
OUT=$(bash "$VALIDATOR" "$FIXDIR/platform-invalid/onboarding-path-absolute/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason says absolute" "not absolute" "$OUT"

echo "[reject] validator 15 — audit_findings_path contains a '..' segment"
OUT=$(bash "$VALIDATOR" "$FIXDIR/platform-invalid/onboarding-path-traversal/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the segment" "'..' path segment" "$OUT"

echo "[reject] validator 15 — audit_digest_path is absolute (G500)"
OUT=$(bash "$VALIDATOR" "$FIXDIR/platform-invalid/digest-path-absolute/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the key" "audit_digest_path" "$OUT"
assert_contains "reason says absolute" "not absolute" "$OUT"

echo "[reject] validator 15 — onboarding_state_path present but empty"
OUT=$(bash "$VALIDATOR" "$FIXDIR/platform-invalid/onboarding-path-empty/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason says omit the key" "omit the key instead" "$OUT"

echo "[accept] validator 25 — authoring_examples_path, a directory relative to the pack root (D132)"
OUT=$(bash "$VALIDATOR" "$FIXDIR/platform-valid-authoring-examples/pack.yaml" 2>&1); ST=$?
assert_exit "platform-valid-authoring-examples accepted (exit 0)" 0 $ST "$OUT"
assert_contains "still reaches the trailing unexpected-content check" "valid: platform" "$OUT"
M=$(with_branch_name platform-valid ae-alone 'authoring_examples_path: "authoring-examples/"')
OUT=$(bash "$VALIDATOR" "$M" 2>&1); ST=$?
assert_exit "as the only optional key, trailing slash, accepted" 0 $ST "$OUT"
M=$(with_branch_name platform-valid ae-before-em 'authoring_examples_path: "examples/authoring"' "evidence_manifest: change-summary")
OUT=$(bash "$VALIDATOR" "$M" 2>&1); ST=$?
assert_exit "before evidence_manifest accepted" 0 $ST "$OUT"
M=$(with_branch_name platform-valid-evidence-manifest ae-after-em 'authoring_examples_path: "authoring-examples"')
OUT=$(bash "$VALIDATOR" "$M" 2>&1); ST=$?
assert_exit "after evidence_manifest rejected (fixed order)" 1 $ST "$OUT"
M=$(with_branch_name platform-valid ae-missing-dir 'authoring_examples_path: "no-such-directory"')
OUT=$(bash "$VALIDATOR" "$M" 2>&1); ST=$?
assert_exit "a directory the fixture does not ship still accepted (shape only)" 0 $ST "$OUT"

echo "[reject] validator 25 — authoring_examples_path is absolute"
OUT=$(bash "$VALIDATOR" "$FIXDIR/platform-invalid/authoring-examples-path-absolute/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the key" "authoring_examples_path" "$OUT"
assert_contains "reason says absolute" "not absolute" "$OUT"

echo "[reject] validator 25 — authoring_examples_path contains a '..' segment"
OUT=$(bash "$VALIDATOR" "$FIXDIR/platform-invalid/authoring-examples-path-traversal/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the key" "authoring_examples_path" "$OUT"
assert_contains "reason names the segment" "'..' path segment" "$OUT"

echo "[reject] validator 25 — authoring_examples_path is not a string"
OUT=$(bash "$VALIDATOR" "$FIXDIR/platform-invalid/authoring-examples-path-not-string/pack.yaml" 2>&1); ST=$?
assert_exit "a list rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the key" "authoring_examples_path" "$OUT"
assert_contains "reason names the expected shape" "double-quoted" "$OUT"
for bad in '42' 'true' 'authoring-examples' '{dir: authoring-examples}' '' '""'; do
  M=$(with_branch_name platform-valid "ae-bad-$RANDOM" "authoring_examples_path: $bad")
  OUT=$(bash "$VALIDATOR" "$M" 2>&1); ST=$?
  assert_exit "authoring_examples_path: $bad rejected" 1 $ST "$OUT"
  assert_contains "authoring_examples_path: $bad → names the key" "authoring_examples_path" "$OUT"
done
M=$(with_branch_name platform-valid ae-block "authoring_examples_path:" "  dir: authoring-examples")
OUT=$(bash "$VALIDATOR" "$M" 2>&1); ST=$?
assert_exit "a block mapping rejected" 1 $ST "$OUT"
assert_contains "a block mapping → names the key" "authoring_examples_path" "$OUT"

echo "[reject] validator 25 — authoring_examples_path on a provider pack"
OUT=$(bash "$VALIDATOR" "$FIXDIR/provider-invalid/authoring-examples-path/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the kind it belongs to" "authoring_examples_path belongs to a platform pack, not a provider pack" "$OUT"
[[ "$OUT" != *"unexpected content"* ]]
assert_exit "reason does not misdiagnose as unexpected content" 0 $? ""
M=$(with_branch_name provider-valid ae-provider-early)
# placed ahead of operations: — a provider pack carries it nowhere
awk '{print} /^role: tracker$/{print "authoring_examples_path: \"authoring-examples\""}' "$M" > "$M.tmp" && mv "$M.tmp" "$M"
OUT=$(bash "$VALIDATOR" "$M" 2>&1); ST=$?
assert_exit "anywhere in a provider manifest rejected" 1 $ST "$OUT"
assert_contains "anywhere → names the kind it belongs to" "belongs to a platform pack" "$OUT"

echo "[reject] provider manifest omits an operation without declaring it unsupported"
OUT=$(bash "$VALIDATOR" "$FIXDIR/provider-invalid/missing-operation/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the missing operation" "list_types" "$OUT"

echo "[reject] provider manifest implements an operation unknown to its role"
OUT=$(bash "$VALIDATOR" "$FIXDIR/provider-invalid/unknown-operation/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the unknown operation" "bogus_op" "$OUT"

echo "[reject] provider manifest names a nonexistent skill"
OUT=$(bash "$VALIDATOR" "$FIXDIR/provider-invalid/dangling-skill/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the missing skill" "note" "$OUT"

# --- inline shape errors ----------------------------------------------------
# One-block edits to an otherwise valid manifest. A fixture directory each
# would multiply the tree to prove one regex apiece.

TMP="$(mktemp -d "${TMPDIR:-/tmp}/validate-pack-manifest.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
cp -R "$FIXDIR/platform-valid-conditions/." "$TMP/"

# stage_list <lines…> — rewrite the manifest with a replacement stage list,
# keeping the trailing keys the valid fixture already carries.
stage_list() {
  {
    printf 'kind: platform\nstages:\n'
    printf '%s\n' "$@"
    sed -n '/^always_autonomous:/,$p' "$FIXDIR/platform-valid-conditions/pack.yaml"
  } > "$TMP/pack.yaml"
}

echo "[reject] the pre-list manifest shape (stages as a mapping)"
stage_list '  intake: intake' '  deliver: deliver'
OUT=$(bash "$VALIDATOR" "$TMP/pack.yaml" 2>&1); ST=$?
assert_exit "old map shape rejected (exit 1)" 1 $ST "$OUT"

echo "[reject] the same stage declared twice"
stage_list '  - id: intake' '    skill: intake' '  - id: intake' '    skill: intake' \
           '  - id: deliver' '    skill: deliver'
OUT=$(bash "$VALIDATOR" "$TMP/pack.yaml" 2>&1); ST=$?
assert_exit "duplicate stage rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason says twice" "twice" "$OUT"

echo "[reject] a list that does not begin with intake"
stage_list '  - id: implement' '    skill: implement' '  - id: deliver' '    skill: deliver'
OUT=$(bash "$VALIDATOR" "$TMP/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names intake" "begin with 'intake'" "$OUT"

echo "[reject] a list that does not end with deliver"
stage_list '  - id: intake' '    skill: intake' '  - id: implement' '    skill: implement'
OUT=$(bash "$VALIDATOR" "$TMP/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names deliver" "end with 'deliver'" "$OUT"

echo "[reject] a mandatory stage carrying a condition"
stage_list '  - id: intake' '    skill: intake' '    when:' '      - { design_source: true }' \
           '  - id: deliver' '    skill: deliver'
OUT=$(bash "$VALIDATOR" "$TMP/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names intake" "intake" "$OUT"

echo "[reject] when: present with no blocks"
stage_list '  - id: intake' '    skill: intake' '  - id: extract' '    skill: extract' '    when:' \
           '  - id: deliver' '    skill: deliver'
OUT=$(bash "$VALIDATOR" "$TMP/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"

echo "[reject] a list field compared against a boolean"
stage_list '  - id: intake' '    skill: intake' '  - id: extract' '    skill: extract' '    when:' \
           '      - { components: true }' '  - id: deliver' '    skill: deliver'
OUT=$(bash "$VALIDATOR" "$TMP/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the right values" "present" "$OUT"

echo "[reject] a boolean field compared against present"
stage_list '  - id: intake' '    skill: intake' '  - id: extract' '    skill: extract' '    when:' \
           '      - { design_source: present }' '  - id: deliver' '    skill: deliver'
OUT=$(bash "$VALIDATOR" "$TMP/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the right values" "true" "$OUT"

echo "[reject] a non-positive fix_attempts"
stage_list '  - id: intake' '    skill: intake' '  - id: implement' '    skill: implement' \
           '    fix_attempts: 0' '  - id: deliver' '    skill: deliver'
OUT=$(bash "$VALIDATOR" "$TMP/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"

echo "[reject] a trailing top-level key"
{
  cat "$FIXDIR/platform-valid-conditions/pack.yaml"
  printf 'unexpected: true\n'
} > "$TMP/pack.yaml"
OUT=$(bash "$VALIDATOR" "$TMP/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the trailing content" "unexpected" "$OUT"

echo "[reject] a platform pack shipping no route.dot"
cp -R "$FIXDIR/platform-valid/." "$TMP/"
rm -f "$TMP/route.dot"
OUT=$(bash "$VALIDATOR" "$TMP/pack.yaml" 2>&1); ST=$?
assert_exit "missing route.dot rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the file" "route.dot" "$OUT"

echo "[reject] an always-on stage drawn dashed"
cp -R "$FIXDIR/platform-valid/." "$TMP/"
sed 's/"implement" \[shape=box\]/"implement" [shape=box, style=dashed]/' \
  "$FIXDIR/platform-valid/route.dot" > "$TMP/route.dot"
OUT=$(bash "$VALIDATOR" "$TMP/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason says it carries no condition" "carries no 'when:'" "$OUT"

echo "[reject] a stray duplicate edge into the same stage"
cp -R "$FIXDIR/platform-valid/." "$TMP/"
{
  cat "$FIXDIR/platform-valid/route.dot" | grep -v '^}$'
  printf '    "intake" -> "deliver";\n}\n'
} > "$TMP/route.dot"
OUT=$(bash "$VALIDATOR" "$TMP/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the doubly-targeted stage" "more than one edge points into 'deliver'" "$OUT"

echo "[accept] route.dot whose final line (a conditional edge's label) has no trailing newline"
cp -R "$FIXDIR/platform-valid-conditions/." "$TMP/"
# Reorders the edges so the labeled edge into the conditional stage 'extract'
# is the last line of the file, with the trailing newline stripped — an
# editor that does not add one, or a hand-authored file, produces exactly
# this shape.
REORDERED='digraph route {
    "intake"    [shape=box];
    "extract"   [shape=box, style=dashed];
    "implement" [shape=box];
    "deliver"   [shape=box];

    "extract"   -> "implement";
    "implement" -> "deliver";
    "intake"    -> "extract"   [label="design_source=true OR design_mentioned=true"];'
printf '%s' "$REORDERED" > "$TMP/route.dot"
OUT=$(bash "$VALIDATOR" "$TMP/pack.yaml" 2>&1); ST=$?
assert_exit "still valid (exit 0)" 0 $ST "$OUT"
assert_contains "no line dropped from EOF" "valid: platform" "$OUT"

# --- drift guards -----------------------------------------------------------
# The validator hardcodes the fact-record field list the way it hardcodes each
# role's operations. These two cases are what stop that copy silently drifting
# from the contract it is supposed to enforce.

echo "[drift] the validator's field list equals fact-record.md's Format block"
CONTRACT_FIELDS="$(
  sed -n '/^## Format$/,/^## Field rules$/p' "$FACT_CONTRACT" \
    | grep -oE '^[a-z_]+:' | tr -d ':' | tr '\n' ' '
)"
VALIDATOR_FIELDS="$(
  sed -n '/^FACT_FIELDS=(/,/)$/p' "$VALIDATOR" \
    | tr '\n' ' ' | sed 's/FACT_FIELDS=(//; s/)//' | tr -s ' '
)"
assert_eq "field lists agree" "$(echo $CONTRACT_FIELDS)" "$(echo $VALIDATOR_FIELDS)"

echo "[drift] the validator and the evaluator share one field/kind table"
V_TABLE="$(sed -n '/^FACT_KINDS=(/,/)$/p' "$VALIDATOR" | tr -s ' \n' ' ')"
E_TABLE="$(sed -n '/^FACT_KINDS=(/,/)$/p' "$EVALUATOR" | tr -s ' \n' ' ')"
assert_eq "kind tables agree" "$V_TABLE" "$E_TABLE"

# --- usage ------------------------------------------------------------------

echo "[usage] no argument"
OUT=$(bash "$VALIDATOR" 2>&1); ST=$?
assert_exit "no arg -> usage error (exit 2)" 2 $ST "$OUT"

echo "[usage] file not found"
OUT=$(bash "$VALIDATOR" "$FIXDIR/does-not-exist/pack.yaml" 2>&1); ST=$?
assert_exit "missing file -> usage error (exit 2)" 2 $ST "$OUT"

# --- config_derivation (validator 27, D138) ---------------------------------

echo "[validator 27] config_derivation — a platform pack's derivation script (D138)"
derivation_case() {
  local case_dir="$BN_WORK/$1"; shift
  cp -R "$FIXDIR/platform-valid" "$case_dir"
  mkdir -p "$case_dir/scripts"
  printf '#!/usr/bin/env bash\n' > "$case_dir/scripts/derive.sh"
  printf '%s\n' "$@" >> "$case_dir/pack.yaml"
  echo "$case_dir/pack.yaml"
}
M=$(derivation_case cd-ordered 'ignore_paths: ["out/"]' 'config_derivation: "scripts/derive.sh"' 'reference_docs: "https://docs.example.org/"')
OUT=$(bash "$VALIDATOR" "$M" 2>&1); ST=$?
assert_exit "after ignore_paths, before reference_docs, accepted" 0 $ST "$OUT"
M=$(derivation_case cd-alone 'config_derivation: "scripts/derive.sh"')
OUT=$(bash "$VALIDATOR" "$M" 2>&1); ST=$?
assert_exit "as the only optional key accepted" 0 $ST "$OUT"
M=$(derivation_case cd-missing 'config_derivation: "scripts/absent.sh"')
OUT=$(bash "$VALIDATOR" "$M" 2>&1); ST=$?
assert_exit "a script that does not exist rejected" 1 $ST "$OUT"
assert_contains "says the script is missing" "config_derivation names a script that does not exist" "$OUT"
for bad in '"../derive.sh"' '"/abs/derive.sh"' 'scripts/derive.sh' '""'; do
  M=$(derivation_case "cd-bad-$RANDOM" "config_derivation: $bad")
  OUT=$(bash "$VALIDATOR" "$M" 2>&1); ST=$?
  assert_exit "config_derivation $bad rejected" 1 $ST "$OUT"
  assert_contains "config_derivation $bad → names the key" "config_derivation" "$OUT"
done
M=$(derivation_case cd-after-rd 'reference_docs: "https://docs.example.org/"' 'config_derivation: "scripts/derive.sh"')
OUT=$(bash "$VALIDATOR" "$M" 2>&1); ST=$?
assert_exit "after reference_docs rejected (reference_docs is last)" 1 $ST "$OUT"
M=$(derivation_case cd-before-ip 'config_derivation: "scripts/derive.sh"' 'ignore_paths: ["out/"]')
OUT=$(bash "$VALIDATOR" "$M" 2>&1); ST=$?
assert_exit "before ignore_paths rejected (fixed order)" 1 $ST "$OUT"
PROV_CD="$BN_WORK/cd-provider"; mkdir -p "$PROV_CD"
printf 'kind: provider\nrole: design\noperations: {}\nunsupported: [fetch_reference]\nconfig_derivation: "derive.sh"\n' > "$PROV_CD/pack.yaml"
: > "$PROV_CD/derive.sh"
OUT=$(bash "$VALIDATOR" "$PROV_CD/pack.yaml" 2>&1); ST=$?
assert_exit "on a provider pack rejected" 1 $ST "$OUT"
assert_contains "reason names the kind it belongs to" "config_derivation belongs to a platform pack, not a provider pack" "$OUT"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
