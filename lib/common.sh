#!/usr/bin/env bash

set -euo pipefail

if [[ -t 1 ]]; then
  COLOR_INFO="\033[1;34m"
  COLOR_WARN="\033[1;33m"
  COLOR_ERROR="\033[1;31m"
  COLOR_OK="\033[1;32m"
  COLOR_RESET="\033[0m"
else
  COLOR_INFO=""
  COLOR_WARN=""
  COLOR_ERROR=""
  COLOR_OK=""
  COLOR_RESET=""
fi

timestamp() {
  date "+%Y-%m-%d %H:%M:%S"
}

log_info() {
  echo -e "${COLOR_INFO}[$(timestamp)] [INFO]${COLOR_RESET} $*"
}

log_warn() {
  echo -e "${COLOR_WARN}[$(timestamp)] [WARN]${COLOR_RESET} $*" >&2
}

log_error() {
  echo -e "${COLOR_ERROR}[$(timestamp)] [ERROR]${COLOR_RESET} $*" >&2
}

log_ok() {
  echo -e "${COLOR_OK}[$(timestamp)] [OK]${COLOR_RESET} $*"
}

die() {
  log_error "$*"
  exit 1
}

trim() {
  local value="${1:-}"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf "%s" "$value"
}

require_command() {
  local cmd="${1:?command required}"
  command -v "$cmd" >/dev/null 2>&1 || die "Required command not found: $cmd"
}

check_openssl_curve() {
  local curve="${1:?curve required}"
  if ! openssl ecparam -list_curves 2>/dev/null | awk '{print $1}' | grep -qx "$curve"; then
    die "OpenSSL does not support curve '$curve' on this machine."
  fi
}

secure_mkdir() {
  local dir="${1:?directory required}"
  mkdir -p "$dir"
  chmod 700 "$dir"
}

secure_write_file() {
  local path="${1:?path required}"
  local mode="${2:-600}"
  : > "$path"
  chmod "$mode" "$path"
}

csv_to_lines() {
  local csv="${1:-}"
  local item
  local old_ifs="$IFS"
  IFS=','
  for item in $csv; do
    item="$(trim "$item")"
    [[ -n "$item" ]] && printf "%s\n" "$item"
  done
  IFS="$old_ifs"
}

contains_csv_value() {
  local csv="${1:-}"
  local needle="${2:-}"
  local entry
  while IFS= read -r entry; do
    if [[ "$entry" == "$needle" ]]; then
      return 0
    fi
  done < <(csv_to_lines "$csv")
  return 1
}

ensure_openssl() {
  require_command openssl
}

is_positive_integer() {
  local value="${1:-}"
  [[ "$value" =~ ^[1-9][0-9]*$ ]]
}

validate_cert_name() {
  local cert_name="${1:-}"
  [[ "$cert_name" =~ ^[A-Za-z0-9._-]+$ ]] || \
    die "Invalid certificate name '$cert_name'. Use only letters, numbers, dot, dash, underscore."
}

validate_csv_dns() {
  local csv="${1:-}"
  local entry
  [[ -z "$csv" ]] && return 0
  while IFS= read -r entry; do
    [[ "$entry" =~ ^[A-Za-z0-9.-]+$ ]] || die "Invalid DNS SAN entry: '$entry'"
  done < <(csv_to_lines "$csv")
}

validate_csv_ip() {
  local csv="${1:-}"
  local entry
  [[ -z "$csv" ]] && return 0
  while IFS= read -r entry; do
    [[ "$entry" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || die "Invalid IP SAN entry: '$entry'"
  done < <(csv_to_lines "$csv")
}

validate_formats_csv() {
  local csv="${1:-pem}"
  local entry
  local count=0
  while IFS= read -r entry; do
    ((count+=1))
    case "$entry" in
      pem|pkcs12|jks) ;;
      *) die "Invalid format '$entry'. Allowed: pem, pkcs12, jks" ;;
    esac
  done < <(csv_to_lines "$csv")
  [[ "$count" -gt 0 ]] || die "At least one format is required (pem, pkcs12, jks)."
}

