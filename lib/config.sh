#!/usr/bin/env bash

set -euo pipefail

CONFIG_STORE=""

parse_config() {
  local file="${1:?config path required}"
  local line key value

  [[ -f "$file" ]] || die "Config file not found: $file"
  CONFIG_STORE="$(mktemp "${TMPDIR:-/tmp}/certgen-config.XXXXXX")"

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ "$line" =~ ^[[:space:]]*$ ]] && continue
    [[ "$line" =~ ^[[:space:]]*# ]] && continue

    if [[ "$line" =~ ^[[:space:]]*([A-Za-z0-9._-]+)[[:space:]]*:[[:space:]]*(.*)$ ]]; then
      key="${BASH_REMATCH[1]}"
      value="${BASH_REMATCH[2]}"
      value="$(trim "$value")"
      value="${value%%[[:space:]]#*}"
      value="$(trim "$value")"
      if [[ "$value" =~ ^\"(.*)\"$ ]]; then
        value="${BASH_REMATCH[1]}"
      fi
      printf "%s\t%s\n" "$key" "$value" >>"$CONFIG_STORE"
    fi
  done <"$file"
}

get_config() {
  local key="${1:?key required}"
  local default_value="${2:-}"
  local value
  [[ -n "$CONFIG_STORE" && -f "$CONFIG_STORE" ]] || {
    printf "%s" "$default_value"
    return
  }
  value="$(
    awk -F '\t' -v k="$key" '$1==k{v=$2} END{print v}' "$CONFIG_STORE"
  )"
  if [[ -n "$value" ]]; then
    printf "%s" "$value"
  else
    printf "%s" "$default_value"
  fi
}

get_cert_prop() {
  local cert_name="${1:?cert name required}"
  local prop="${2:?property required}"
  local default_value="${3:-}"
  local key="cert.${cert_name}.${prop}"
  get_config "$key" "$default_value"
}

list_cert_names() {
  [[ -n "$CONFIG_STORE" && -f "$CONFIG_STORE" ]] || return 0
  awk -F '\t' '{print $1}' "$CONFIG_STORE" \
    | awk -F '.' '/^cert\.[^.]+\.[^.]+$/ {print $2}' \
    | awk 'NF' \
    | sort -u
}

