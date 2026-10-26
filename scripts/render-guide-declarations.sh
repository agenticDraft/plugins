#!/usr/bin/env bash
# Run: bash scripts/render-guide-declarations.sh [--root <repo>] [--write <guide>]
#
# render-guide-declarations.sh [--root <repo>] [--write <guide>]
#
# Renders the block of plugins/getting-started.md that says what a project prepares in advance,
# from what every shipped pack declares in its pack.yaml: `env`, `hosts`, `requires`,
# `credential_checks`, `session_tools` and `ignore_paths`, plus the core's own paths in
# agentic-core/shared/run-paths.txt. The guide never restates those values by hand; the block
# is refreshed from here and checked by check-getting-started.sh.
#
#   --root   the repository whose plugins/agentic-*/pack.yaml are read (default: this one)
#   --write  replace the block between the guide's two markers in place instead of printing it
#
# Every manifest is checked by the core's validator before it is read; an invalid one refuses
# the whole render. Deterministic, no model involved. Without --write it writes nothing.
#
# Exit codes: 0 — rendered (or written); 1 — a manifest is invalid, or no pack found;
#             2 — usage error, or --write on a guide without both markers.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
VALIDATE="$REPO/plugins/agentic-core/shared/lib/validate-pack-manifest.sh"
BEGIN='<!-- guide-declarations:begin'
END='<!-- guide-declarations:end -->'

usage() {
  echo "usage: render-guide-declarations.sh [--root <repo>] [--write <guide>]" >&2
  exit 2
}

ROOT="$REPO"
GUIDE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)  [[ $# -ge 2 ]] || usage; ROOT="$2"; shift 2 ;;
    --write) [[ $# -ge 2 ]] || usage; GUIDE="$2"; shift 2 ;;
    *) usage ;;
  esac
done

if [[ -n "$GUIDE" ]]; then
  [[ -f "$GUIDE" ]] && grep -q "^$BEGIN" "$GUIDE" && grep -qF "$END" "$GUIDE" \
    || { echo "refused: $GUIDE does not hold both guide-declarations markers" >&2; exit 2; }
fi

# Escapes the angle brackets of a declaration's text so a Markdown renderer shows them.
esc() { printf '%s' "$1" | sed -e 's/</\\</g' -e 's/>/\\>/g'; }

# The double-quoted entries of a one-line bracket list, one per line.
quoted_entries() { grep -oE '"[^"]*"' <<< "$1" | sed 's/^"//; s/"$//'; }

# Records of one manifest, tab-separated, one per declaration.
records() {
  awk '
    function flush() {
      if (kind == "env" && name != "") print "env\037" name "\037" src "\037" login
      else if (kind == "requires" && tool != "") print "req\037" tool "\037" inst "\037" rem
      else if (kind == "credential_checks" && chk != "") print "chk\037" chk "\037" rem
      else if (kind == "session_tools" && tool != "") print "sess\037" tool "\037" rem
      name = src = login = tool = inst = rem = chk = ""
    }
    function val(s) { sub(/^[^:]*: */, "", s); return s }
    function str(s) { s = val(s); sub(/^"/, "", s); sub(/"$/, "", s); return s }
    /^[A-Za-z_]+:/ {
      flush(); kind = $0; sub(/:.*/, "", kind)
      if (kind == "hosts" || kind == "ignore_paths") {
        l = val($0); sub(/^\[/, "", l); sub(/\]$/, "", l); print kind "\037" l
      } else if (kind == "kind") print "kind\037" val($0)
      else if (kind == "role") print "role\037" val($0)
      next
    }
    /^  - name: /  { flush(); name = val($0); next }
    /^  - tool: /  { flush(); tool = val($0); next }
    /^  - check: / { flush(); chk = val($0); next }
    /^    source: /            { src = str($0); next }
    /^    login_alternative: / { login = str($0); next }
    /^    install: /           { inst = val($0); sub(/^\[/, "", inst); sub(/\]$/, "", inst); gsub(/, /, " ", inst); next }
    /^    remedy: /            { rem = str($0); next }
    END { flush() }
  ' "$1"
}

PACKS=()
for manifest in "$ROOT"/plugins/agentic-*/pack.yaml; do
  [[ -f "$manifest" ]] || continue
  verdict=$(bash "$VALIDATE" "$manifest" 2>&1) \
    || { echo "refused: $manifest — ${verdict%%$'\n'*}" >&2; exit 1; }
  PACKS+=("$manifest")
done
[[ ${#PACKS[@]} -gt 0 ]] || { echo "refused: no plugins/agentic-*/pack.yaml under $ROOT" >&2; exit 1; }

# role<TAB>name<TAB>manifest, sorted by role order then name.
LIST=""
for manifest in "${PACKS[@]}"; do
  name=$(basename "$(dirname "$manifest")")
  rec=$(records "$manifest")
  kind=$(awk -F'\037' '$1 == "kind" { print $2 }' <<< "$rec")
  role=$(awk -F'\037' '$1 == "role" { print $2 }' <<< "$rec")
  [[ "$kind" == "platform" ]] && role="platform"
  case "$role" in
    platform) rank=1 ;; tracker) rank=2 ;; scm) rank=3 ;; design) rank=4 ;; browser) rank=5 ;; *) rank=9 ;;
  esac
  LIST+="$rank"$'\t'"$role"$'\t'"$name"$'\t'"$manifest"$'\n'
done
LIST=$(printf '%s' "$LIST" | sort -t$'\t' -k1,1n -k3,3)

OUT="$BEGIN — rendered by scripts/render-guide-declarations.sh from the packs' pack.yaml files; refresh it with --write, never edit it by hand -->"$'\n'
IGNORES=""

while IFS=$'\t' read -r _ role name manifest; do
  [[ -n "$name" ]] || continue
  rec=$(records "$manifest")
  OUT+=$'\n'"#### $name ($role)"$'\n'

  envs=$(awk -F'\037' '$1 == "env"' <<< "$rec")
  if [[ -n "$envs" ]]; then
    OUT+=$'\n'"Variables, kept in \`.claude/settings.local.json\` under \`env\`:"$'\n\n'
    while IFS=$'\037' read -r _ n s l; do
      s=$(esc "$s")
      if [[ -n "$l" ]]; then
        OUT+="- \`$n\` — ${s%.}. A login replaces it: \`$l\`"$'\n'
      else
        OUT+="- \`$n\` — $s"$'\n'
      fi
    done <<< "$envs"
  fi

  hosts=$(awk -F'\037' '$1 == "hosts" { print $2 }' <<< "$rec")
  if [[ -n "$hosts" ]]; then
    list=""
    while IFS= read -r h; do [[ -n "$h" ]] && list+="${list:+, }\`$h\`"; done < <(quoted_entries "$hosts")
    OUT+=$'\n'"Hosts, added to the committed \`.claude/settings.json\` under \`sandbox.network.allowedDomains\`: $list"$'\n'
  fi

  reqs=$(awk -F'\037' '$1 == "req"' <<< "$rec")
  if [[ -n "$reqs" ]]; then
    OUT+=$'\n'"Tools on your machine:"$'\n\n'
    while IFS=$'\037' read -r _ t i r; do
      r=$(esc "$r")
      if [[ -n "$i" ]]; then
        OUT+="- \`$t\` — \`setup\` can install it with \`$i\`. If you do it yourself: $r"$'\n'
      else
        OUT+="- \`$t\` — $r"$'\n'
      fi
    done <<< "$reqs"
  fi

  chks=$(awk -F'\037' '$1 == "chk"' <<< "$rec")
  if [[ -n "$chks" ]]; then
    OUT+=$'\n'"Checked before every run:"$'\n\n'
    while IFS=$'\037' read -r _ c r; do
      OUT+="- \`$c\` — $(esc "$r")"$'\n'
    done <<< "$chks"
  fi

  sess=$(awk -F'\037' '$1 == "sess"' <<< "$rec")
  if [[ -n "$sess" ]]; then
    OUT+=$'\n'"Session tools, which the plugin that serves them must provide before a run:"$'\n\n'
    grouped=$(awk -F'\037' '
      { if (!($3 in seen)) { seen[$3] = 1; order[++n] = $3 }
        tools[$3] = tools[$3] (tools[$3] == "" ? "" : ", ") "`" $2 "`" }
      END { for (i = 1; i <= n; i++) print tools[order[i]] "\037" order[i] }' <<< "$sess")
    while IFS=$'\037' read -r t r; do
      OUT+="- $t — $(esc "$r")"$'\n'
    done <<< "$grouped"
  fi

  if [[ -z "$envs$hosts$reqs$chks$sess" ]]; then
    OUT+=$'\n'"Declares nothing for you to prepare."$'\n'
  fi

  ign=$(awk -F'\037' '$1 == "ignore_paths" { print $2 }' <<< "$rec")
  while IFS= read -r p; do [[ -n "$p" ]] && IGNORES+="$p"$'\n'; done < <(quoted_entries "$ign")
done <<< "$LIST"

CORE_IGNORE="" COMMIT=""
RUN_PATHS="$ROOT/plugins/agentic-core/shared/run-paths.txt"
if [[ -f "$RUN_PATHS" ]]; then
  while read -r kind path; do
    case "$kind" in
      ignore) CORE_IGNORE+="$path"$'\n' ;;
      commit) COMMIT+="$path"$'\n' ;;
    esac
  done < "$RUN_PATHS"
fi

join_paths() { awk 'NF && !seen[$0]++ { printf "%s`%s`", (n++ ? ", " : ""), $0 }' ; }
OUT+=$'\n'"#### Files in your repository"$'\n'
OUT+=$'\n'"Kept out of git; \`setup\` adds each to \`.gitignore\`, never removing a line: $(printf '%s%s' "$CORE_IGNORE" "$IGNORES" | join_paths)"$'\n'
OUT+=$'\n'"Committed on purpose; \`setup\` names the ones it wrote for you to commit before the first run: $(printf '%s' "$COMMIT" | join_paths)"$'\n'
OUT+=$'\n'"$END"

if [[ -z "$GUIDE" ]]; then
  printf '%s\n' "$OUT"
  exit 0
fi

BLOCK_FILE=$(mktemp "${TMPDIR:-/tmp}/guide-block.XXXXXX") || exit 1
trap 'rm -f "$BLOCK_FILE" "$BLOCK_FILE.new"' EXIT
printf '%s\n' "$OUT" > "$BLOCK_FILE"
awk -v begin="$BEGIN" -v end="$END" -v blockfile="$BLOCK_FILE" '
  index($0, begin) == 1 && !done { while ((getline l < blockfile) > 0) print l; skipping = 1; next }
  skipping && index($0, end) == 1 { skipping = 0; done = 1; next }
  !skipping { print }
' "$GUIDE" > "$BLOCK_FILE.new" && cat "$BLOCK_FILE.new" > "$GUIDE"
echo "written: $GUIDE"
