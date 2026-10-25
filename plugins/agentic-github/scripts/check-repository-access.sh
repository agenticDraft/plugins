#!/usr/bin/env bash
# Run: bash plugins/agentic-github/scripts/check-repository-access.sh
#
# The scm pack's credential check (`credential_checks:` in pack.yaml). Run in
# the project's checkout. Exits 0 when the credential `gh` uses — a login, or
# GH_TOKEN where no one can log in — reaches the repository `origin` names and
# the account may push to it. Reads only; opens nothing, writes nothing, and
# prints nothing, so no account or token detail can reach a report.
#
# A token whose resource owner is another account cannot see the repository,
# so the read fails. What this cannot answer is whether a fine-grained token
# carries "Pull requests: write": GitHub has no endpoint that reports a
# token's permissions, and `permissions.push` is the account's role on the
# repository, not the token's grant.
#
# Exit codes: 0 — reached, may push; 1 — anything else.

set -uo pipefail

origin="$(git remote get-url origin 2>/dev/null)" || exit 1

case "$origin" in
  git@github.com:*) path="${origin#git@github.com:}" ;;
  ssh://git@github.com/*) path="${origin#ssh://git@github.com/}" ;;
  https://github.com/*) path="${origin#https://github.com/}" ;;
  *) exit 1 ;;
esac
path="${path%/}"
path="${path%.git}"
[[ "$path" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || exit 1

gh auth status >/dev/null 2>&1 || exit 1

push="$(gh api "repos/$path" --jq '.permissions.push' 2>/dev/null)" || exit 1
[[ "$push" == "true" ]] || exit 1
exit 0
