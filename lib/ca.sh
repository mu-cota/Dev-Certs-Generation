#!/usr/bin/env bash

set -euo pipefail

CA_DIR=""
CA_KEY=""
CA_CERT=""
CA_SERIAL=""

ca_init_paths() {
  local output_root="${1:?output_root required}"
  CA_DIR="${output_root}/ca"
  CA_KEY="${CA_DIR}/ca.key"
  CA_CERT="${CA_DIR}/ca.crt"
  CA_SERIAL="${CA_DIR}/ca.srl"
}

ca_exists() {
  [[ -f "$CA_KEY" && -f "$CA_CERT" ]]
}

ca_subject() {
  local country="${1:-SG}"
  local state="${2:-Singapore}"
  local locality="${3:-Singapore}"
  local org="${4:-Organization}"
  local ou="${5:-Security}"
  local cn="${6:-Dev CA}"
  printf "/C=%s/ST=%s/L=%s/O=%s/OU=%s/CN=%s" \
    "$country" "$state" "$locality" "$org" "$ou" "$cn"
}

ca_generate() {
  local curve="${1:?curve required}"
  local days="${2:?days required}"
  local subject="${3:?subject required}"

  check_openssl_curve "$curve"
  secure_mkdir "$CA_DIR"

  log_info "Generating ECDSA CA private key ($curve)"
  openssl ecparam -name "$curve" -genkey -noout -out "$CA_KEY"
  chmod 600 "$CA_KEY"

  log_info "Generating self-signed CA certificate (${days}d)"
  openssl req -x509 -new -sha384 -key "$CA_KEY" \
    -days "$days" -out "$CA_CERT" -subj "$subject" \
    -addext "basicConstraints=critical,CA:TRUE,pathlen:0" \
    -addext "keyUsage=critical,keyCertSign,cRLSign" \
    -addext "subjectKeyIdentifier=hash"
  chmod 644 "$CA_CERT"

  log_ok "CA created at $CA_DIR"
}

ca_remove_existing() {
  if [[ -d "$CA_DIR" ]]; then
    log_warn "Removing existing CA directory: $CA_DIR"
    rm -rf "$CA_DIR"
  fi
}

ca_ensure() {
  local fresh="${1:-false}"
  local curve="${2:?curve required}"
  local days="${3:?days required}"
  local subject="${4:?subject required}"

  if [[ "$fresh" == "true" ]]; then
    ca_remove_existing
  fi

  if ca_exists; then
    log_ok "Reusing existing CA: $CA_CERT"
  else
    ca_generate "$curve" "$days" "$subject"
  fi
}

ca_info() {
  [[ -f "$CA_CERT" ]] || die "CA certificate not found: $CA_CERT"
  openssl x509 -in "$CA_CERT" -noout -subject -issuer -dates -fingerprint -sha256
}

