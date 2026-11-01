#!/usr/bin/env bash
set -euo pipefail

name="${1:?usage: $0 <VARIABLE_NAME> [versions-file]}"
file="${2:-${VERSIONS_FILE:-versions.env}}"

value="${!name:-}"

if [ -z "$value" ] && [ -f "$file" ]; then
  value="$(awk -v key="$name" '
    $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
      sub(/^[[:space:]]*[^=]*=[[:space:]]*/, "")
      sub(/\r$/, "")
      sub(/[[:space:]]*$/, "")
      print
      exit
    }
  ' "$file")"
fi

# Trim surrounding whitespace from either source.
value="$(printf '%s' "$value" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

if [ -z "$value" ]; then
  echo "error: ${name} is not set via environment and not found in ${file}" >&2
  exit 1
fi

printf '%s\n' "$value"
