#!/usr/bin/env bash
# check-pr-body.sh <template> <body> [--source <composed body>]
#
# Checks that a pull request body fills the repository's template:
#   - every Markdown heading of the template is in the body, in the
#     template's order;
#   - each one has content before the next heading or a `---` line, or a line
#     `Empty: <reason>`. Blank lines, HTML comment lines and `Empty:` with no
#     reason are not content;
#   - no placeholder of the template — `<name>` or `{name}` — is left in the
#     body;
#   - with --source, the caller's composed body appears in it verbatim, so
#     filling the template never drops what the caller wrote.
# Deterministic, no model involved. Reads and never writes.
#
# Output (stdout):
#   filled: <n> headings, <m> placeholders replaced
#   unfilled: <what>                         one line per problem
#
# Exit codes: 0 — filled; 1 — unfilled; 2 — usage error (a file is missing).

set -uo pipefail

usage() { echo "usage: check-pr-body.sh <template> <body> [--source <composed body>]" >&2; exit 2; }

[[ $# -ge 2 ]] || usage
TEMPLATE="$1"; BODY="$2"; shift 2
SOURCE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --source) [[ $# -ge 2 ]] || usage; SOURCE="$2"; shift 2 ;;
    *) usage ;;
  esac
done
[[ -f "$TEMPLATE" && -f "$BODY" ]] || usage
[[ -z "$SOURCE" || -f "$SOURCE" ]] || usage

is_heading() { [[ "$1" =~ ^#{1,6}\ [^[:space:]] ]]; }

PROBLEMS=()

# The template's headings, in order.
T_HEADINGS=()
while IFS= read -r line || [[ -n "$line" ]]; do
  is_heading "$line" && T_HEADINGS+=("$line")
done < "$TEMPLATE"

# The body, as an array of lines.
B_LINES=()
while IFS= read -r line || [[ -n "$line" ]]; do
  B_LINES+=("$line")
done < "$BODY"
NB=${#B_LINES[@]}

# has_content <index of a heading line in the body>
has_content() {
  local i=$(( $1 + 1 )) l
  while (( i < NB )); do
    l="${B_LINES[$i]}"
    is_heading "$l" && return 1
    [[ "$l" == "---" ]] && return 1
    if [[ -n "${l//[[:space:]]/}" && ! "$l" =~ ^[[:space:]]*\<!--.*--\>[[:space:]]*$ \
          && ! "$l" =~ ^Empty:[[:space:]]*$ ]]; then
      return 0
    fi
    i=$(( i + 1 ))
  done
  return 1
}

# Each template heading, searched from just after the previous one found.
CUR=-1
for h in "${T_HEADINGS[@]+"${T_HEADINGS[@]}"}"; do
  found=-1 earlier=0
  for (( i = CUR + 1; i < NB; i++ )); do
    [[ "${B_LINES[$i]}" == "$h" ]] && { found=$i; break; }
  done
  if (( found < 0 )); then
    for (( i = 0; i <= CUR && i < NB; i++ )); do
      [[ "${B_LINES[$i]}" == "$h" ]] && { earlier=1; break; }
    done
    if (( earlier )); then
      PROBLEMS+=("heading '$h' is out of the template's order")
    else
      PROBLEMS+=("heading '$h' is missing")
    fi
    continue
  fi
  CUR=$found
  has_content "$found" || PROBLEMS+=("heading '$h' has no content and no 'Empty: <reason>'")
done

# The template's placeholders, in order of first appearance, each once.
PLACEHOLDERS=()
while IFS= read -r p; do
  [[ -n "$p" ]] && PLACEHOLDERS+=("$p")
done < <(grep -oE '<[A-Za-z][A-Za-z0-9_ -]*>|\{[A-Za-z][A-Za-z0-9_-]*\}' "$TEMPLATE" | awk '!seen[$0]++')
for p in "${PLACEHOLDERS[@]+"${PLACEHOLDERS[@]}"}"; do
  grep -qF -- "$p" "$BODY" && PROBLEMS+=("placeholder '$p' is still in the body")
done

if [[ -n "$SOURCE" ]]; then
  SRC="$(cat "$SOURCE")"
  [[ "$(cat "$BODY")" == *"$SRC"* ]] || PROBLEMS+=("the composed body is not carried verbatim")
fi

if (( ${#PROBLEMS[@]} > 0 )); then
  printf 'unfilled: %s\n' "${PROBLEMS[@]}"
  exit 1
fi
echo "filled: ${#T_HEADINGS[@]} headings, ${#PLACEHOLDERS[@]} placeholders replaced"
exit 0
