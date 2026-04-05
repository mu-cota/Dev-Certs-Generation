#!/usr/bin/env bash

set -euo pipefail

assert_cert_file() {
  local cert="${1:?cert path required}"
  [[ -f "$cert" ]] || die "Certificate file not found: $cert"
}

validate_cert() {
  local cert="${1:?cert required}"
  local ca_cert="${2:?ca cert required}"
  [[ -f "$ca_cert" ]] || die "CA certificate not found: $ca_cert"
  assert_cert_file "$cert"
  openssl verify -CAfile "$ca_cert" "$cert" >/dev/null
  log_ok "Certificate chain validated: $cert"
}

extract_sans() {
  local cert="${1:?cert required}"
  assert_cert_file "$cert"
  openssl x509 -in "$cert" -noout -ext subjectAltName 2>/dev/null \
    | awk 'NR>1 {print}' \
    | tr -d ' ' \
    | tr ',' '\n'
}

extract_field_single_line() {
  local cert="${1:?cert required}"
  local flag="${2:?openssl flag required}"
  openssl x509 -in "$cert" -noout "$flag" 2>/dev/null | sed -e 's/^[^=]*=//'
}

extract_signature_algorithm() {
  local cert="${1:?cert required}"
  openssl x509 -in "$cert" -noout -text 2>/dev/null \
    | awk '/Signature Algorithm:/ {print $3; exit}'
}

extract_public_key_algorithm() {
  local cert="${1:?cert required}"
  openssl x509 -in "$cert" -noout -text 2>/dev/null \
    | awk '/Public Key Algorithm:/ {sub(/^[ \t]+/, ""); print; exit}'
}

extract_public_key_size() {
  local cert="${1:?cert required}"
  openssl x509 -in "$cert" -noout -text 2>/dev/null \
    | awk '/Public-Key: \(/ {line=$0; gsub(/^.*Public-Key: \(/, "", line); gsub(/ bit\).*$/, "", line); print line; exit}'
}

extract_curve() {
  local cert="${1:?cert required}"
  openssl x509 -in "$cert" -noout -text 2>/dev/null \
    | awk '/ASN1 OID:/ {print $3; exit}'
}

extract_extension_block() {
  local cert="${1:?cert required}"
  local ext_name="${2:?extension name required}"
  openssl x509 -in "$cert" -noout -ext "$ext_name" 2>/dev/null | awk 'NR>1 {print}'
}

extract_ocsp_uri() {
  local cert="${1:?cert required}"
  openssl x509 -in "$cert" -noout -ocsp_uri 2>/dev/null || true
}

extract_crl_uri() {
  local cert="${1:?cert required}"
  openssl x509 -in "$cert" -noout -text 2>/dev/null \
    | awk '
      /CRL Distribution Points/ {incrl=1; next}
      incrl && /URI:/ {sub(/^.*URI:/, ""); print; exit}
    '
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

print_cert_details_default() {
  local cert="${1:?cert required}"
  local sans

  assert_cert_file "$cert"
  sans="$(extract_sans "$cert" || true)"

  echo "Certificate Inspection"
  echo "======================"
  echo "Subject: $(extract_field_single_line "$cert" -subject)"
  echo "Issuer: $(extract_field_single_line "$cert" -issuer)"
  echo "Serial: $(extract_field_single_line "$cert" -serial)"
  echo "Not Before: $(extract_field_single_line "$cert" -startdate)"
  echo "Not After: $(extract_field_single_line "$cert" -enddate)"
  echo "SHA256 Fingerprint: $(extract_field_single_line "$cert" -fingerprint | sed -e 's/^sha256 Fingerprint=//')"
  echo "Signature Algorithm: $(extract_signature_algorithm "$cert")"
  echo "Public Key Algorithm: $(extract_public_key_algorithm "$cert")"
  if [[ -n "$(extract_public_key_size "$cert")" ]]; then
    echo "Public Key Size: $(extract_public_key_size "$cert") bits"
  fi
  if [[ -n "$(extract_curve "$cert")" ]]; then
    echo "Curve: $(extract_curve "$cert")"
  fi
  echo "SANs:"
  if [[ -n "$sans" ]]; then
    printf "%s\n" "$sans" | sed 's/^/  - /'
  else
    echo "  - (none)"
  fi
  echo "Key Usage:"
  extract_extension_block "$cert" keyUsage | sed 's/^/  /'
  echo "Extended Key Usage:"
  extract_extension_block "$cert" extendedKeyUsage | sed 's/^/  /'
  echo "Basic Constraints:"
  extract_extension_block "$cert" basicConstraints | sed 's/^/  /'
  echo "Subject Key Identifier:"
  extract_extension_block "$cert" subjectKeyIdentifier | sed 's/^/  /'
  echo "Authority Key Identifier:"
  extract_extension_block "$cert" authorityKeyIdentifier | sed 's/^/  /'
}

print_cert_query() {
  local cert="${1:?cert required}"
  local query="${2:?query required}"
  local query_key
  local ocsp_uri crl_uri

  assert_cert_file "$cert"
  query_key="$(printf "%s" "$query" | tr '[:upper:]' '[:lower:]' | tr '-' '_')"

  case "$query_key" in
    subject) extract_field_single_line "$cert" -subject ;;
    issuer) extract_field_single_line "$cert" -issuer ;;
    serial) extract_field_single_line "$cert" -serial ;;
    not_before|startdate) extract_field_single_line "$cert" -startdate ;;
    not_after|enddate|expiry) extract_field_single_line "$cert" -enddate ;;
    dates) openssl x509 -in "$cert" -noout -dates ;;
    fingerprint|fingerprint_sha256) extract_field_single_line "$cert" -fingerprint | sed -e 's/^sha256 Fingerprint=//' ;;
    san|sans) extract_sans "$cert" ;;
    key_usage) extract_extension_block "$cert" keyUsage ;;
    eku|extended_key_usage) extract_extension_block "$cert" extendedKeyUsage ;;
    basic_constraints) extract_extension_block "$cert" basicConstraints ;;
    ski|subject_key_identifier) extract_extension_block "$cert" subjectKeyIdentifier ;;
    aki|authority_key_identifier) extract_extension_block "$cert" authorityKeyIdentifier ;;
    signature_algorithm) extract_signature_algorithm "$cert" ;;
    public_key_algorithm) extract_public_key_algorithm "$cert" ;;
    public_key_size) extract_public_key_size "$cert" ;;
    curve) extract_curve "$cert" ;;
    ocsp_uri)
      ocsp_uri="$(extract_ocsp_uri "$cert")"
      [[ -n "$ocsp_uri" ]] && printf "%s\n" "$ocsp_uri" || printf "(none)\n"
      ;;
    crl_uri)
      crl_uri="$(extract_crl_uri "$cert")"
      [[ -n "$crl_uri" ]] && printf "%s\n" "$crl_uri" || printf "(none)\n"
      ;;
    *)
      die "Unsupported query '$query'. Supported: subject, issuer, serial, not_before, not_after, dates, fingerprint, san, key_usage, eku, basic_constraints, ski, aki, signature_algorithm, public_key_algorithm, public_key_size, curve, ocsp_uri, crl_uri"
      ;;
  esac
}

print_cert_text() {
  local cert="${1:?cert required}"
  assert_cert_file "$cert"
  openssl x509 -in "$cert" -text -noout
}

check_cert_expiry_window() {
  local cert="${1:?cert required}"
  local days="${2:?days required}"
  local seconds

  assert_cert_file "$cert"
  is_positive_integer "$days" || die "--check-expiry-days must be a positive integer"
  seconds="$((days * 86400))"

  if openssl x509 -in "$cert" -noout -checkend "$seconds" >/dev/null 2>&1; then
    log_ok "Certificate does not expire within ${days} day(s)."
  else
    die "Certificate expires within ${days} day(s)."
  fi
}

http_fetch_to_file() {
  local url="${1:?url required}"
  local out_file="${2:?output file required}"

  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --connect-timeout 5 --max-time 15 "$url" -o "$out_file"
    return 0
  fi
  if command -v wget >/dev/null 2>&1; then
    wget -q -T 15 -O "$out_file" "$url"
    return 0
  fi
  return 1
}

check_revocation_ocsp() {
  local cert="${1:?cert required}"
  local ca_cert="${2:-}"
  local strict="${3:-false}"
  local ocsp_uri
  local response

  if [[ -z "$ca_cert" ]]; then
    [[ "$strict" == "true" ]] && die "OCSP check requested but --ca is missing."
    log_warn "OCSP check skipped: --ca is required."
    return 0
  fi

  ocsp_uri="$(extract_ocsp_uri "$cert")"
  if [[ -z "$ocsp_uri" ]]; then
    [[ "$strict" == "true" ]] && die "OCSP check requested but certificate has no OCSP URI."
    log_warn "OCSP URI not present in certificate; status unknown."
    return 0
  fi

  response="$(
    openssl ocsp \
      -issuer "$ca_cert" \
      -cert "$cert" \
      -url "$ocsp_uri" \
      -CAfile "$ca_cert" \
      -noverify \
      -no_nonce \
      -timeout 10 2>&1 || true
  )"

  if printf "%s" "$response" | grep -qi ": good"; then
    log_ok "OCSP status: good"
    return 0
  fi
  if printf "%s" "$response" | grep -qi ": revoked"; then
    die "OCSP status: revoked"
  fi
  if [[ "$strict" == "true" ]]; then
    die "OCSP status: unknown or unavailable"
  fi
  log_warn "OCSP status: unknown or unavailable"
}

check_revocation_crl() {
  local cert="${1:?cert required}"
  local ca_cert="${2:-}"
  local strict="${3:-false}"
  local crl_uri
  local tmp_dir
  local crl_raw
  local crl_pem
  local verify_output

  if [[ -z "$ca_cert" ]]; then
    [[ "$strict" == "true" ]] && die "CRL check requested but --ca is missing."
    log_warn "CRL check skipped: --ca is required."
    return 0
  fi

  crl_uri="$(extract_crl_uri "$cert")"
  if [[ -z "$crl_uri" ]]; then
    [[ "$strict" == "true" ]] && die "CRL check requested but certificate has no CRL URI."
    log_warn "CRL URI not present in certificate; status unknown."
    return 0
  fi

  tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/certgen-crl.XXXXXX")"
  crl_raw="${tmp_dir}/download.crl"
  crl_pem="${tmp_dir}/download.pem"

  if ! http_fetch_to_file "$crl_uri" "$crl_raw"; then
    rm -rf "$tmp_dir"
    [[ "$strict" == "true" ]] && die "Failed to fetch CRL URI: $crl_uri"
    log_warn "Failed to fetch CRL URI: $crl_uri"
    return 0
  fi

  if openssl crl -in "$crl_raw" -noout >/dev/null 2>&1; then
    cp "$crl_raw" "$crl_pem"
  elif openssl crl -inform DER -in "$crl_raw" -out "$crl_pem" >/dev/null 2>&1; then
    :
  else
    rm -rf "$tmp_dir"
    [[ "$strict" == "true" ]] && die "Unable to parse downloaded CRL data."
    log_warn "Unable to parse downloaded CRL data."
    return 0
  fi

  verify_output="$(openssl verify -CAfile "$ca_cert" -crl_check -CRLfile "$crl_pem" "$cert" 2>&1 || true)"
  rm -rf "$tmp_dir"

  if printf "%s" "$verify_output" | grep -qi "OK"; then
    log_ok "CRL status: good (not revoked)"
    return 0
  fi
  if printf "%s" "$verify_output" | grep -qi "certificate revoked"; then
    die "CRL status: revoked"
  fi

  [[ "$strict" == "true" ]] && die "CRL status: unknown or unavailable"
  log_warn "CRL status: unknown or unavailable"
}

check_revocation() {
  local cert="${1:?cert required}"
  local ca_cert="${2:-}"
  local method="${3:?method required}"
  local strict="${4:-false}"

  case "$method" in
    ocsp) check_revocation_ocsp "$cert" "$ca_cert" "$strict" ;;
    crl) check_revocation_crl "$cert" "$ca_cert" "$strict" ;;
    *) die "Unsupported revocation method '$method'. Use ocsp or crl." ;;
  esac
}

print_cert_summary() {
  local cert="${1:?cert required}"
  print_cert_details_default "$cert"
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

