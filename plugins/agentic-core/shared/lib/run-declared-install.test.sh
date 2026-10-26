#!/usr/bin/env bash
# Tests for run-declared-install.sh. Run with:
#   bash plugins/agentic-core/shared/lib/run-declared-install.test.sh
#
# No framework — exits 0 on success, 1 if any case failed.
#
# Every install in here is a stub the test writes into a fixture pack: it
# edits files of a fixture project and counts its own runs. No case runs a
# real install or reaches a network.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/run-declared-install.sh"
[[ -n "${TMPDIR:-}" ]] || { echo "TMPDIR is empty; refusing to create test directories" >&2; exit 1; }
WORK="$(mktemp -d "$TMPDIR/run-declared-install-test.XXXXXX")" || exit 1
trap 'rm -rf "$WORK"' EXIT

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

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    PASS=$((PASS + 1)); echo "  ok: $desc"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: $desc"
    echo "    expected: $expected"
    echo "    got:      $actual"
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

# The fixture pack: a probe that answers whether the project holds the
# tool's binary, and stub installs that write what a real one would — the
# binary in an ignored directory, a changed dependency list, a new lock
# file — and append one line per run to a counter outside the project.
PACK="$WORK/pack"
COUNTER="$WORK/runs.txt"
mkdir -p "$PACK/scripts"
cat > "$PACK/scripts/probe.sh" <<'EOF'
[[ -x vendor/bin/example-cli ]]
EOF
cat > "$PACK/scripts/stub-install.sh" <<EOF
echo "run in \$(pwd)" >> "$COUNTER"
echo "stub install: fetching example-cli" >&2
mkdir -p vendor/bin
printf '#!/usr/bin/env bash\nexit 0\n' > vendor/bin/example-cli
chmod +x vendor/bin/example-cli
echo "example-cli 1.0.0" >> deps.txt
echo "example-cli 1.0.0 sha-stub" > deps.lock
EOF
cat > "$PACK/scripts/stub-install-fails.sh" <<EOF
echo "run in \$(pwd)" >> "$COUNTER"
echo "stub install: registry refused" >&2
exit 7
EOF
cat > "$PACK/scripts/stub-install-no-binary.sh" <<EOF
echo "run in \$(pwd)" >> "$COUNTER"
echo "example-cli 1.0.0" >> deps.txt
EOF
cat > "$PACK/pack.yaml" <<'EOF'
kind: platform
requires:
  - tool: example-cli
    probe: [bash, <pack>/scripts/probe.sh]
    install: [bash, <pack>/scripts/stub-install.sh]
    remedy: "run the example installer, then commit deps.txt and deps.lock"
  - tool: failing-cli
    probe: [bash, <pack>/scripts/probe.sh]
    install: [bash, <pack>/scripts/stub-install-fails.sh]
    remedy: "install failing-cli by hand"
  - tool: half-cli
    probe: [bash, <pack>/scripts/probe.sh]
    install: [bash, <pack>/scripts/stub-install-no-binary.sh]
    remedy: "install half-cli by hand"
  - tool: manual-cli
    probe: [bash, <pack>/scripts/probe.sh]
    remedy: "install manual-cli by hand"
  - tool: quoted-cli
    probe: [bash, <pack>/scripts/probe.sh]
    install: [touch, $(touch WORK_CANARY)]
    remedy: "install quoted-cli by hand"
EOF

# A fresh fixture project: one commit holding deps.txt and other.txt, an
# ignore rule for vendor/, and two pre-existing changes the install must not
# be blamed for — an edited tracked file and an untracked note.
new_project() {
  local dir="$WORK/project-$1"
  rm -rf "$dir"; mkdir -p "$dir/sub"
  (
    cd "$dir" || exit 1
    git init -q
    printf 'vendor/\n' > .gitignore
    echo "base 1.0.0" > deps.txt
    echo "other" > other.txt
    echo "keep" > sub/keep.txt
    git add -A
    git -c user.name=t -c user.email=t@example.invalid commit -q -m base
    echo "edited before" >> other.txt
    echo "a note" > notes.txt
  )
  : > "$COUNTER"
  echo "$dir"
}

runs() { grep -c . "$COUNTER" 2>/dev/null || true; }

echo "=== run-declared-install.sh tests ==="

echo "[usage]"
P="$(new_project usage)"
OUT=$(cd "$P" && bash "$SCRIPT" 2>&1); assert_exit "no argument -> usage error" 2 $? "$OUT"
OUT=$(cd "$P" && bash "$SCRIPT" "$WORK/nope.yaml" example-cli 2>&1); assert_exit "missing manifest -> usage error" 2 $? "$OUT"
OUT=$(cd "$P" && bash "$SCRIPT" "$PACK/pack.yaml" no-such-tool 2>&1); RC=$?
assert_exit "a tool the pack does not declare -> usage error" 2 "$RC" "$OUT"
assert_contains "names the tool" "no-such-tool" "$OUT"
mkdir -p "$WORK/not-a-repo"
OUT=$(cd "$WORK/not-a-repo" && bash "$SCRIPT" "$PACK/pack.yaml" example-cli 2>&1); RC=$?
assert_exit "outside a git work tree -> usage error" 2 "$RC" "$OUT"
assert_eq "the install never ran on a usage error" "0" "$(runs)"

echo "[no-install] an entry with no install argv"
P="$(new_project manual)"
OUT=$(cd "$P" && bash "$SCRIPT" "$PACK/pack.yaml" manual-cli 2>/dev/null); RC=$?
assert_exit "exit 3" 3 "$RC" "$OUT"
assert_contains "says there is nothing to run" "no-install: manual-cli" "$OUT"
assert_contains "carries the remedy" "remedy: install manual-cli by hand" "$OUT"

echo "[installed] the stub runs once, the probe passes, exactly its files are named"
P="$(new_project ok)"
HEAD_BEFORE="$(git -C "$P" rev-parse HEAD)"
OUT=$(cd "$P/sub" && bash "$SCRIPT" "$PACK/pack.yaml" example-cli 2>"$WORK/stderr.txt"); RC=$?
assert_exit "exit 0" 0 "$RC" "$OUT"
assert_eq "stdout is the result, then one changed line per file, sorted" \
  "installed: example-cli
changed: deps.lock
changed: deps.txt" "$OUT"
assert_eq "the stub ran exactly once" "1" "$(runs)"
assert_eq "the stub ran in the project root, from a subdirectory" "run in $(cd "$P" && pwd -P)" "$(head -1 "$COUNTER")"
assert_contains "the install's own output goes to stderr" "stub install: fetching example-cli" "$(cat "$WORK/stderr.txt")"
assert_eq "nothing committed" "$HEAD_BEFORE" "$(git -C "$P" rev-parse HEAD)"
git -C "$P" diff --cached --quiet; assert_exit "nothing staged" 0 $? ""
OUT=$(cd "$P" && bash "$SCRIPT" "$PACK/pack.yaml" example-cli 2>&1); RC=$?
assert_exit "a second call finds it present -> exit 0" 0 "$RC" "$OUT"
assert_contains "and runs nothing" "present: example-cli" "$OUT"
assert_eq "the stub still ran only once" "1" "$(runs)"

echo "[installed] a file already changed before is named only if the install changed it again"
P="$(new_project again)"
echo "edited before" >> "$P/deps.txt"
OUT=$(cd "$P" && bash "$SCRIPT" "$PACK/pack.yaml" example-cli 2>/dev/null); RC=$?
assert_exit "exit 0" 0 "$RC" "$OUT"
assert_contains "deps.txt, edited before and again by the install" "changed: deps.txt" "$OUT"
case "$OUT" in
  *"other.txt"*|*"notes.txt"*) FAIL=$((FAIL + 1)); echo "  FAIL: a change made before the install was named: $OUT" ;;
  *) PASS=$((PASS + 1)); echo "  ok: changes made before the install are not named" ;;
esac

echo "[failed] the install exits non-zero"
P="$(new_project fails)"
OUT=$(cd "$P" && bash "$SCRIPT" "$PACK/pack.yaml" failing-cli 2>"$WORK/stderr.txt"); RC=$?
assert_exit "exit 1" 1 "$RC" "$OUT"
assert_eq "failed, the exit code, the remedy" \
  "failed: failing-cli — the install exited 7
remedy: install failing-cli by hand" "$OUT"
assert_contains "the refusal itself is on stderr" "registry refused" "$(cat "$WORK/stderr.txt")"
assert_eq "no second attempt" "1" "$(runs)"

echo "[failed] the install exits 0 but the probe still fails"
P="$(new_project half)"
OUT=$(cd "$P" && bash "$SCRIPT" "$PACK/pack.yaml" half-cli 2>/dev/null); RC=$?
assert_exit "exit 1" 1 "$RC" "$OUT"
assert_contains "says the probe still fails" "failed: half-cli — the probe still fails after the install" "$OUT"
assert_contains "still names what it changed" "changed: deps.txt" "$OUT"
assert_contains "and the remedy" "remedy: install half-cli by hand" "$OUT"
assert_eq "no second attempt" "1" "$(runs)"

echo "[argv] the install is argv, never a shell string"
P="$(new_project quoted)"
OUT=$(cd "$P" && bash "$SCRIPT" "$PACK/pack.yaml" quoted-cli 2>/dev/null); RC=$?
if [[ -e "$P/WORK_CANARY" ]]; then
  FAIL=$((FAIL + 1)); echo "  FAIL: a command substitution in the argv was executed"
else
  PASS=$((PASS + 1)); echo "  ok: a command substitution in the argv is a literal argument"
fi

echo "[readers] nothing but this script runs install, and only setup calls it"
PLUGINS="$(cd "$SCRIPT_DIR/../../.." && pwd)"
code_files() {
  find "$PLUGINS" -type d -name node_modules -prune -o -type f \
    \( -name '*.sh' -o -name '*.mjs' -o -name '*.cjs' -o -name '*.js' -o -name '*.py' \) \
    ! -name '*.test.*' -print
}
# A code file that names the key at all: this script, the validator (shape),
# and check-requires.sh (which skips the line).
NAMING="$(code_files | xargs grep -l 'install:' 2>/dev/null | sed "s|^$PLUGINS/||" | LC_ALL=C sort | tr '\n' ' ')"
assert_eq "only three code files name the install key" \
  "agentic-core/shared/lib/check-requires.sh agentic-core/shared/lib/run-declared-install.sh agentic-core/shared/lib/validate-pack-manifest.sh " \
  "$NAMING"
assert_eq "check-requires.sh never captures the install argv" "" \
  "$(grep 'install:' "$SCRIPT_DIR/check-requires.sh" | grep -v '^[[:space:]]*#' | grep -e '(\.\*)' -e 'BASH_REMATCH')"
# A file outside this script and its test that calls it: only the core setup skill.
CALLERS="$( { code_files; find "$PLUGINS" -type d -name node_modules -prune -o -name SKILL.md -print; } \
  | xargs grep -l 'run-declared-install' 2>/dev/null \
  | while IFS= read -r f; do grep -v '^[[:space:]]*#' "$f" | grep -q 'run-declared-install' && echo "${f#"$PLUGINS"/}"; done \
  | grep -v 'shared/lib/run-declared-install' | LC_ALL=C sort | tr '\n' ' ')"
assert_eq "only the core setup skill calls it" "agentic-core/skills/setup/SKILL.md " "$CALLERS"

echo
if [[ "$FAIL" -eq 0 ]]; then
  echo "=== $PASS passed, 0 failed ==="
  exit 0
fi
echo "=== $PASS passed, $FAIL failed ==="
exit 1
