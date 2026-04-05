#!/usr/bin/env bash

set -euo pipefail

validate_cert() {
  local cert="${1:?cert required}"
  local ca_cert="${2:?ca cert required}"
  openssl verify -CAfile "$ca_cert" "$cert" >/dev/null
  log_ok "Certificate chain validated: $cert"
}

extract_sans() {
  local cert="${1:?cert required}"
  openssl x509 -in "$cert" -noout -ext subjectAltName 2>/dev/null \
    | awk 'NR>1 {print}' \
    | tr -d ' ' \
    | tr ',' '\n'
}

check_sans() {
  local cert="${1:?cert required}"
  local expected_dns_csv="${2:-}"
  local expected_ip_csv="${3:-}"
  local sans
  local entry

  sans="$(extract_sans "$cert" || true)"

  while IFS= read -r entry; do
    [[ -z "$entry" ]] && continue
    if ! grep -q "^DNS:${entry}$" <<<"$sans"; then
      die "SAN validation failed for $cert: missing DNS:${entry}"
    fi
  done < <(csv_to_lines "$expected_dns_csv")

  while IFS= read -r entry; do
    [[ -z "$entry" ]] && continue
    if ! grep -q "^IPAddress:${entry}$" <<<"$sans"; then
      die "SAN validation failed for $cert: missing IP:${entry}"
    fi
  done < <(csv_to_lines "$expected_ip_csv")

  log_ok "SAN values validated for $cert"
}

print_cert_summary() {
  local cert="${1:?cert required}"
  openssl x509 -in "$cert" -noout \
    -subject \
    -issuer \
    -dates \
    -fingerprint -sha256 \
    -ext keyUsage \
    -ext extendedKeyUsage \
    -ext subjectAltName
}

write_cert_summary() {
  local cert="${1:?cert required}"
  local output_file="${2:?output file required}"
  {
    echo "Certificate Summary"
    echo "==================="
    print_cert_summary "$cert"
  } >"$output_file"
  chmod 644 "$output_file"
}

generate_report() {
  local output_root="${1:?output root required}"
  local report_file="${output_root}/generation-report.txt"
  local cert_file

  {
    echo "Generation Report"
    echo "================="
    echo "Generated at: $(date -u "+%Y-%m-%dT%H:%M:%SZ")"
    echo
    for cert_file in "$output_root"/*/tls.crt; do
      [[ -f "$cert_file" ]] || continue
      echo "--- ${cert_file} ---"
      openssl x509 -in "$cert_file" -noout -subject -issuer -dates -fingerprint -sha256
      echo
    done
  } >"$report_file"
  chmod 644 "$report_file"
  log_ok "Generation report written: $report_file"
}

