#!/usr/bin/env bash
# Run: bash plugins/agentic-eds/shared/scripts/write-site-links.sh [--config <path>] [--readme <path>]
#
# Writes the site's links into one marked block of the project README, from the
# project config: the content editor (`platform.content_source`, asked once by
# the platform setup, since nothing derives it), and the preview and live hosts
# of the default branch, derived from `platform.preview_host_suffix` and never
# stored. A re-run replaces the block in place and leaves everything outside it
# untouched; with no block yet, it goes after the README's title, or first. A
# README that does not exist is created holding the block alone. Nothing else
# about the site — who may edit it, its users — is read or written.
#
# Output (stdout): `updated: <readme>`, `unchanged: <readme>` or
# `created: <readme>`.
# Exit codes: 0 — written or unchanged; 1 — refused (no suffix in the config,
# or a content_source that is not an https URL), nothing written; 2 — usage.

set -uo pipefail

CONFIG=".ai/project-config.yaml"
README="README.md"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --config) [[ $# -ge 2 ]] || exit 2; CONFIG="$2"; shift 2 ;;
    --readme) [[ $# -ge 2 ]] || exit 2; README="$2"; shift 2 ;;
    *) echo "usage: write-site-links.sh [--config <path>] [--readme <path>]" >&2; exit 2 ;;
  esac
done

refuse() { echo "refused: $1" >&2; exit 1; }

platform_value() {
  [[ -f "$CONFIG" ]] || return 0
  awk -v k="  $1:" '
    $0 == "platform:" { inside = 1; next }
    /^[^ ]/ { inside = 0 }
    inside && index($0, k) == 1 { v = substr($0, length(k) + 1); gsub(/^[ \t"]+|[ \t"]+$/, "", v); print v; exit }
  ' "$CONFIG"
}

suffix="$(platform_value preview_host_suffix)"
[[ -n "$suffix" ]] || refuse "no platform.preview_host_suffix in $CONFIG; run setup"
source_url="$(platform_value content_source)"
if [[ -n "$source_url" ]]; then
  [[ "$source_url" =~ ^https://[^[:space:]\"\<\>]+$ ]] || refuse "platform.content_source is not an https URL"
  editor="$source_url"
else
  editor="not configured (platform.content_source)"
fi

branch="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)"
branch="${branch#origin/}"
[[ -n "$branch" ]] || branch="main"
branch="$(printf '%s' "$branch" | tr '[:upper:]/' '[:lower:]-')"

START='<!-- agentic-eds:site-links (written from .ai/project-config.yaml by the platform setup; edits inside are replaced) -->'
END='<!-- /agentic-eds:site-links -->'
BLOCK="$START
## Site links

- Content editor: $editor
- Preview: https://${branch}${suffix}.aem.page/
- Live: https://${branch}${suffix}.aem.live/
$END"

if [[ ! -f "$README" ]]; then
  printf '%s\n' "$BLOCK" > "$README"
  echo "created: $README"
  exit 0
fi

TMP="$(mktemp "${TMPDIR:-/tmp}/site-links.XXXXXX")"
trap 'rm -f "$TMP"' EXIT
BLOCK="$BLOCK" awk -v start="$START" -v end="$END" '
  BEGIN { block = ENVIRON["BLOCK"] }
  { lines[++n] = $0; if ($0 == start) s = n; if ($0 == end && s && !e) e = n }
  END {
    if (s && e) {
      for (i = 1; i < s; i++) print lines[i]
      print block
      for (i = e + 1; i <= n; i++) print lines[i]
    } else if (n > 0 && lines[1] ~ /^# /) {
      print lines[1]; print ""; print block
      i = 2; if (lines[2] != "") print ""
      for (; i <= n; i++) print lines[i]
    } else {
      print block; print ""
      for (i = 1; i <= n; i++) print lines[i]
    }
  }
' "$README" > "$TMP"

if cmp -s "$TMP" "$README"; then
  echo "unchanged: $README"
else
  cat "$TMP" > "$README"
  echo "updated: $README"
fi
exit 0
