#!/usr/bin/env bash

set -euo pipefail

create_full_chain() {
  local cert="${1:?cert path required}"
  local ca_cert="${2:?ca cert path required}"
  local output="${3:?output path required}"
  cat "$cert" "$ca_cert" >"$output"
  chmod 644 "$output"
}

generate_password() {
  openssl rand -base64 32 | tr -d '\n'
}

convert_pkcs12() {
  local cert="${1:?cert path required}"
  local key="${2:?key path required}"
  local ca_cert="${3:?ca cert required}"
  local output_p12="${4:?output p12 required}"
  local password="${5:?password required}"
  local alias_name="${6:-tls}"

  openssl pkcs12 -export \
    -in "$cert" \
    -inkey "$key" \
    -certfile "$ca_cert" \
    -name "$alias_name" \
    -out "$output_p12" \
    -passout "pass:${password}"
  chmod 600 "$output_p12"
}

convert_jks() {
  local source_p12="${1:?source p12 required}"
  local output_jks="${2:?output jks required}"
  local password="${3:?password required}"

  if ! command -v keytool >/dev/null 2>&1; then
    log_warn "keytool not found, skipping JKS generation for ${output_jks}"
    return 0
  fi

  if ! keytool -help >/dev/null 2>&1; then
    log_warn "keytool is present but Java runtime is unavailable; skipping JKS generation for ${output_jks}"
    return 0
  fi

  if ! keytool -importkeystore \
    -srckeystore "$source_p12" \
    -srcstoretype PKCS12 \
    -srcstorepass "$password" \
    -destkeystore "$output_jks" \
    -deststoretype JKS \
    -deststorepass "$password" \
    -noprompt >/dev/null 2>&1; then
    log_warn "JKS conversion failed, skipping: ${output_jks}"
    return 0
  fi

  chmod 600 "$output_jks"
}

emit_requested_formats() {
  local cert_dir="${1:?cert dir required}"
  local cert="${2:?cert required}"
  local key="${3:?key required}"
  local ca_cert="${4:?ca cert required}"
  local formats_csv="${5:-pem}"
  local alias_name="${6:-tls}"
  local password
  local p12_path="${cert_dir}/tls.p12"
  local p12_created=false

  create_full_chain "$cert" "$ca_cert" "${cert_dir}/full-chain.crt"

  if contains_csv_value "$formats_csv" "pkcs12" || contains_csv_value "$formats_csv" "jks"; then
    password="$(generate_password)"
    convert_pkcs12 "$cert" "$key" "$ca_cert" "$p12_path" "$password" "$alias_name"
    printf "%s\n" "$password" >"${cert_dir}/tls.p12.pass"
    chmod 600 "${cert_dir}/tls.p12.pass"
    p12_created=true
    log_ok "Generated PKCS#12: ${p12_path}"
  fi

  if contains_csv_value "$formats_csv" "jks"; then
    if [[ "$p12_created" != "true" ]]; then
      password="$(generate_password)"
      convert_pkcs12 "$cert" "$key" "$ca_cert" "$p12_path" "$password" "$alias_name"
      printf "%s\n" "$password" >"${cert_dir}/tls.p12.pass"
      chmod 600 "${cert_dir}/tls.p12.pass"
    fi
    convert_jks "$p12_path" "${cert_dir}/tls.jks" "$password"
    if [[ -f "${cert_dir}/tls.jks" ]]; then
      log_ok "Generated JKS: ${cert_dir}/tls.jks"
    fi
  fi
}

