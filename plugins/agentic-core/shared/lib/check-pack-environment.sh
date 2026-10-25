#!/usr/bin/env bash
# Run: bash plugins/agentic-core/shared/lib/check-pack-environment.sh <label>=<pack.yaml> ...
#
# check-pack-environment.sh [--settings <path>] <label>=<pack.yaml> [...]
#
# Checks, for each given pack, what its manifest declares the project must
# provide (shared/pack-manifest.md): each `env` variable is set in this
# process's environment and does not hold a `FILL-IN:` placeholder, and each
# `hosts` entry is in the committed settings' `sandbox.network.allowedDomains`.
# Offline: reads the manifests, the settings file and the environment, and
# reaches nothing. Never prints a value — not a credential, not a placeholder.
# A set variable is reported as present, never as working. Names no pack.
# Deterministic, no model involved. Writes nothing.
#
#   <label>     how the pack is named in the report (a role, or a pack name)
#   --settings  the committed settings file (default .claude/settings.json)
#
# A variable that declares `login_alternative` may be left unset or empty,
# because the login stands in for it; that is reported as `login:` and is
# not a failure here — only a credential check proves the login. Holding a
# placeholder is a failure, because a placeholder breaks the login.
#
# A literal host is allowed when the list holds it, or holds a `*.<domain>`
# entry it ends in; a declared `*.<domain>` is allowed only by that same entry.
#
# Output (stdout), one line per declaration:
#   set: <label> <NAME> — presence only, not proof that it works
#   missing: <label> <NAME> — not set; <source>
#   unfilled: <label> <NAME> — holds a FILL-IN: placeholder; …
#   login: <label> <NAME> — not set; "<login>" may stand in, …
#   allowed: <label> <host>
#   blocked: <label> <host> — not in sandbox.network.allowedDomains of <file>
#   none: <label> declares no variable and no host
#
# Exit codes:
#   0 — nothing missing, unfilled or blocked
#   1 — at least one missing, unfilled or blocked line
#   2 — usage error, a manifest that does not exist, or a settings file that
#       is not a JSON object with a list `sandbox.network.allowedDomains`

set -uo pipefail

usage() {
  echo "usage: check-pack-environment.sh [--settings <path>] <label>=<pack.yaml> [...]" >&2
  exit 2
}

SETTINGS=".claude/settings.json"
PACKS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --settings) [[ $# -ge 2 ]] || usage; SETTINGS="$2"; shift 2 ;;
    *=*) PACKS+=("$1"); shift ;;
    *) usage ;;
  esac
done
(( ${#PACKS[@]} > 0 )) || usage

ALLOWED=()
if [[ -e "$SETTINGS" ]]; then
  SHAPE='type == "object" and ((.sandbox.network.allowedDomains // []) | type == "array")'
  jq -e "$SHAPE" "$SETTINGS" >/dev/null 2>&1 \
    || { echo "refused: $SETTINGS is not a JSON object with a list sandbox.network.allowedDomains" >&2; exit 2; }
  while IFS= read -r d; do ALLOWED+=("$d"); done < <(jq -r '(.sandbox.network.allowedDomains // [])[] | strings' "$SETTINGS")
fi

host_allowed() {
  local host="$1" d
  for d in ${ALLOWED[@]+"${ALLOWED[@]}"}; do
    [[ "$d" == "$host" ]] && return 0
    if [[ "$host" != \*.* && "$d" == \*.* && "$host" == *".${d#\*.}" ]]; then
      return 0
    fi
  done
  return 1
}

STATUS=0

# report_env <label> <name> <source> <login> — the value is read into a local
# and compared, never printed.
report_env() {
  local label="$1" name="$2" source="$3" login="$4" value
  value="${!name-}"
  if [[ "$value" == FILL-IN:* ]]; then
    if [[ -n "$login" ]]; then
      echo "unfilled: $label $name — holds a FILL-IN: placeholder, which breaks \"$login\"; fill it, or remove the key and use the login"
    else
      echo "unfilled: $label $name — holds a FILL-IN: placeholder; fill it in the credentials file"
    fi
    STATUS=1
  elif [[ -n "$value" ]]; then
    echo "set: $label $name — presence only, not proof that it works"
  elif [[ -n "$login" ]]; then
    echo "login: $label $name — not set; \"$login\" may stand in, proven only by a credential check"
  else
    echo "missing: $label $name — not set; $source"
    STATUS=1
  fi
}

for arg in "${PACKS[@]}"; do
  label="${arg%%=*}"
  manifest="${arg#*=}"
  [[ -f "$manifest" ]] || { echo "refused: $manifest does not exist" >&2; exit 2; }
  declared=0

  # env: entries are a name, a source and an optional login_alternative, in
  # that order, as validate-pack-manifest.sh checks.
  name="" source="" login="" inside=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == "env:" ]]; then inside=1; continue; fi
    (( inside )) || continue
    if [[ "$line" =~ ^\ \ -\ name:\ (.*)$ ]]; then
      [[ -n "$name" ]] && { report_env "$label" "$name" "$source" "$login"; declared=1; }
      name="${BASH_REMATCH[1]}" source="" login=""
    elif [[ "$line" =~ ^\ \ \ \ source:\ \"(.*)\"$ ]]; then
      source="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^\ \ \ \ login_alternative:\ \"(.*)\"$ ]]; then
      login="${BASH_REMATCH[1]}"
    else
      inside=0
    fi
  done < "$manifest"
  [[ -n "$name" ]] && { report_env "$label" "$name" "$source" "$login"; declared=1; }

  hosts=$(sed -n 's/^hosts: \[\(.*\)\]$/\1/p' "$manifest")
  while IFS= read -r host; do
    [[ -n "$host" ]] || continue
    declared=1
    if host_allowed "$host"; then
      echo "allowed: $label $host"
    else
      echo "blocked: $label $host — not in sandbox.network.allowedDomains of $SETTINGS"
      STATUS=1
    fi
  done < <(grep -oE '"[^"]*"' <<< "$hosts" | sed 's/^"//; s/"$//')

  (( declared )) || echo "none: $label declares no variable and no host"
done

exit "$STATUS"
