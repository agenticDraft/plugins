#!/usr/bin/env bash
# find-pr-template.sh [repository-root]
#
# Prints the pull request template GitHub fills a new pull request's body
# from, if the repository has one: `.github/`, the root, then `docs/`, a file
# named pull_request_template.md in any letter case. A template directory
# (PULL_REQUEST_TEMPLATE/) holding several templates is not a default body:
# GitHub applies one of those only when the pull request URL names it. An
# empty file is no template. Reads and never writes.
#
# Output (stdout):
#   template: <path relative to the root>
#   none: <why>
#
# Exit codes: 0 — found; 3 — none; 2 — usage error (the root is not a directory).

set -uo pipefail

ROOT="${1:-.}"
[[ -d "$ROOT" ]] || { echo "usage: find-pr-template.sh [repository-root]" >&2; exit 2; }

for dir in .github . docs; do
  [[ -d "$ROOT/$dir" ]] || continue
  for f in "$ROOT/$dir"/*; do
    [[ -f "$f" && -s "$f" ]] || continue
    name="$(basename "$f")"
    lower="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')"
    if [[ "$lower" == "pull_request_template.md" ]]; then
      if [[ "$dir" == "." ]]; then echo "template: $name"; else echo "template: $dir/$name"; fi
      exit 0
    fi
  done
done

for dir in .github . docs; do
  for sub in "$ROOT/$dir"/*; do
    [[ -d "$sub" ]] || continue
    name="$(basename "$sub")"
    if [[ "$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')" == "pull_request_template" ]]; then
      rel="$name/"; [[ "$dir" == "." ]] || rel="$dir/$name/"
      echo "none: only a template directory ($rel), which applies by query parameter only"
      exit 3
    fi
  done
done

echo "none: no pull request template in this repository"
exit 3
