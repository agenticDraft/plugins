#!/usr/bin/env bash
# Run: bash scripts/check-plugin-versions.test.sh
set -uo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/check-plugin-versions.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/plugin-versions.XXXXXX")" || { echo "cannot create a temp dir" >&2; exit 2; }
[ -n "$WORK" ] && [ -d "$WORK" ] || { echo "cannot create a temp dir" >&2; exit 2; }
trap 'rm -rf "$WORK"' EXIT

pass=0; failed=0
expect() { # <label> <expected exit> <expected text> <actual exit> <actual output>
  if [ "$4" -eq "$2" ] && grep -qF -- "$3" <<<"$5"; then pass=$((pass + 1)); echo "  ok: $1"
  else failed=$((failed + 1)); echo "  FAIL: $1 (exit $4, wanted $2 with '$3')"; echo "$5" | sed 's/^/    /'; fi
}

g() { git -C "$WORK" -c user.email=t@t -c user.name=t "$@"; }
write_plugin() { # <name> <version>
  mkdir -p "$WORK/plugins/$1/.claude-plugin"
  printf '{"name":"%s","version":"%s"}\n' "$1" "$2" > "$WORK/plugins/$1/.claude-plugin/plugin.json"
}
write_catalog() { # <name> <version> ...
  mkdir -p "$WORK/.claude-plugin"
  jq -n '$ARGS.positional as $a | {plugins: [range(0; ($a|length); 2) | {name: $a[.], source: ("./plugins/" + $a[.]), version: $a[.+1]}]}' \
    --args "$@" > "$WORK/.claude-plugin/marketplace.json"
}
run() { out=$(bash "$SCRIPT" main "$WORK" 2>&1); rc=$?; }

g init -q -b main
write_plugin alpha 1.0.0; write_plugin beta 1.0.0
write_catalog alpha 1.0.0 beta 1.0.0
echo a > "$WORK/plugins/alpha/a.txt"
g add -A; g commit -q -m base
g switch -q -c work

run; expect "nothing changed" 0 "ok: plugins/alpha unchanged" "$rc" "$out"

echo b >> "$WORK/plugins/alpha/a.txt"; g commit -qam "change alpha"
run; expect "a change without a bump fails" 1 "bump: plugins/alpha changed since main but its version is still 1.0.0" "$rc" "$out"

write_plugin alpha 1.1.0; g commit -qam "bump alpha"
run; expect "a bump the catalog does not follow fails" 1 "drift: catalog says alpha is 1.0.0, ./plugins/alpha/.claude-plugin/plugin.json says 1.1.0" "$rc" "$out"

write_catalog alpha 1.1.0 beta 1.0.0; g commit -qam "catalog"
run; expect "a bump with a matching catalog passes" 0 "ok: plugins/alpha changed, version 1.0.0 -> 1.1.0" "$rc" "$out"

write_plugin gamma 0.1.0; write_catalog alpha 1.1.0 beta 1.0.0 gamma 0.1.0; g add -A; g commit -qm "gamma"
run; expect "a new plugin needs no bump" 0 "ok: plugins/gamma is new since main" "$rc" "$out"

echo "=== $pass passed, $failed failed ==="
[ "$failed" -eq 0 ]
