#!/usr/bin/env bash
# Run: bash scripts/run-tests.test.sh
set -uo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/run-tests.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/run-tests.XXXXXX")" || { echo "cannot create a temp dir" >&2; exit 2; }
[ -n "$WORK" ] && [ -d "$WORK" ] || { echo "cannot create a temp dir" >&2; exit 2; }
trap 'rm -rf "$WORK"' EXIT

pass=0; failed=0
expect() { # <label> <expected exit> <expected text> <actual exit> <actual output>
  if [ "$4" -eq "$2" ] && grep -qF -- "$3" <<<"$5"; then pass=$((pass + 1)); echo "  ok: $1"
  else failed=$((failed + 1)); echo "  FAIL: $1 (exit $4, wanted $2 with '$3')"; echo "$5" | tail -5 | sed 's/^/    /'; fi
}
run() { # <dir> -> sets OUT and RC
  OUT="$(bash "$SCRIPT" "$1" 2>&1)"; RC=$?
}

# 1. A passing suite and two suites that skip: skips are tallied, the exit stays 0.
D="$WORK/mixed"; mkdir -p "$D"
printf '#!/usr/bin/env bash\necho "  ok: something"\n' > "$D/plain.test.sh"
# shellcheck disable=SC2016
printf '#!/usr/bin/env bash\necho "  skipped: first reason"\necho "  skipped: second reason"\necho "  ok: allowed: skipped: not a skip"\n' > "$D/skips.test.sh"
cat > "$D/skips.test.mjs" <<'EOF'
import { test } from "node:test";
test("runs", () => {});
test("skipped one", { skip: "no reason" }, () => {});
test("skipped two", { skip: "no reason" }, () => {});
EOF
run "$D"
expect "skips are tallied across .test.sh and .test.mjs" 0 "files=3 fail=0 skipped=4" "$RC" "$OUT"

# 2. No skip anywhere: the tally is printed and is zero.
D="$WORK/clean"; mkdir -p "$D"
printf '#!/usr/bin/env bash\necho "  ok: something"\n' > "$D/plain.test.sh"
run "$D"
expect "no skips prints skipped=0" 0 "files=1 fail=0 skipped=0" "$RC" "$OUT"

# 3. A failing suite still fails the run and is still reported.
D="$WORK/failing"; mkdir -p "$D"
printf '#!/usr/bin/env bash\necho "  skipped: one"\nexit 1\n' > "$D/bad.test.sh"
run "$D"
expect "a failing suite exits 1" 1 "files=1 fail=1 skipped=1" "$RC" "$OUT"
expect "a failing suite is annotated" 1 "::error file=$D/bad.test.sh::suite failed (exit 1)" "$RC" "$OUT"

# 4. No suites found is still a failure.
D="$WORK/empty"; mkdir -p "$D"
run "$D"
expect "no suites exits 1" 1 "files=0 fail=0 skipped=0" "$RC" "$OUT"

# 5. The suite's own output still reaches the caller.
D="$WORK/mixed"
run "$D"
expect "suite output is passed through" 0 "skipped: first reason" "$RC" "$OUT"

echo "$pass passed, $failed failed"
[ "$failed" -eq 0 ]
