#!/usr/bin/env bash

set -euo pipefail

declare -gA CONFIG=()

parse_config() {
  local file="${1:?config path required}"
  local line key value

  [[ -f "$file" ]] || die "Config file not found: $file"
  CONFIG=()

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
      CONFIG["$key"]="$value"
    fi
  done <"$file"
}

get_config() {
  local key="${1:?key required}"
  local default_value="${2:-}"
  if [[ -n "${CONFIG[$key]+x}" ]]; then
    printf "%s" "${CONFIG[$key]}"
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
  local key name
  local -A names=()
  for key in "${!CONFIG[@]}"; do
    if [[ "$key" =~ ^cert\.([^.]+)\.[^.]+$ ]]; then
      name="${BASH_REMATCH[1]}"
      names["$name"]=1
    fi
  done
  printf "%s\n" "${!names[@]}" | awk 'NF' | sort
}

