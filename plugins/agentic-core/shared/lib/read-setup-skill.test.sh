#!/usr/bin/env bash
# Tests for read-setup-skill.sh. Run with:
#   bash plugins/agentic-core/shared/lib/read-setup-skill.test.sh
#
# No framework — exits 0 on success, 1 if any case failed.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/read-setup-skill.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/read-setup-skill.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
check() {
  local desc="$1" want_rc="$2" want_out="$3" rc="$4" out="$5"
  if [[ "$rc" == "$want_rc" && "$out" == "$want_out" ]]; then
    PASS=$((PASS + 1)); echo "  ok: $desc"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: $desc"
    echo "    expected exit=$want_rc out='$want_out', got exit=$rc out='$out'"
  fi
}

echo "=== read-setup-skill.sh tests ==="

printf 'kind: platform\nconfig_derivation: "scripts/derive.sh"\nsetup_skill: "example-setup"\nreference_docs: "https://docs.example.org/"\n' > "$WORK/declares.yaml"
OUT=$(bash "$SCRIPT" "$WORK/declares.yaml" 2>&1); RC=$?
check "a declared setup skill is printed" 0 "setup_skill: example-setup" "$RC" "$OUT"

printf 'kind: platform\nreference_docs: "https://docs.example.org/"\n' > "$WORK/none.yaml"
OUT=$(bash "$SCRIPT" "$WORK/none.yaml" 2>&1); RC=$?
check "no setup skill -> none, exit 3" 3 "none: the platform pack declares no setup skill" "$RC" "$OUT"

printf 'kind: provider\nrole: scm\nsetup_skill: "x"\n' > "$WORK/provider.yaml"
OUT=$(bash "$SCRIPT" "$WORK/provider.yaml" 2>&1); RC=$?
check "a provider manifest -> refused, exit 1" 1 "refused: $WORK/provider.yaml is not a platform pack" "$RC" "$OUT"

printf 'kind: platform\nsetup_skill: example-setup\n' > "$WORK/unquoted.yaml"
OUT=$(bash "$SCRIPT" "$WORK/unquoted.yaml" 2>&1); RC=$?
check "an unquoted value -> refused, exit 1" 1 "refused: setup_skill is malformed; run validate-pack-manifest.sh on $WORK/unquoted.yaml" "$RC" "$OUT"

OUT=$(bash "$SCRIPT" 2>&1); RC=$?
check "no argument -> usage, exit 2" 2 "usage: read-setup-skill.sh <platform pack.yaml>" "$RC" "$OUT"
OUT=$(bash "$SCRIPT" "$WORK/absent.yaml" 2>&1); RC=$?
check "a missing file -> usage, exit 2" 2 "refused: $WORK/absent.yaml does not exist" "$RC" "$OUT"

echo
echo "=== $PASS passed, $FAIL failed ==="
(( FAIL == 0 ))
