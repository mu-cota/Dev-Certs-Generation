#!/usr/bin/env bash

set -euo pipefail

build_subject() {
  local country="${1:-SG}"
  local state="${2:-Singapore}"
  local locality="${3:-Singapore}"
  local org="${4:-Organization}"
  local ou="${5:-Engineering}"
  local cn="${6:?common name required}"
  printf "/C=%s/ST=%s/L=%s/O=%s/OU=%s/CN=%s" \
    "$country" "$state" "$locality" "$org" "$ou" "$cn"
}

generate_leaf_cert() {
  local cert_name="${1:?cert name required}"
  local profile="${2:?profile required}"
  local cn="${3:?common name required}"
  local san_dns="${4:-}"
  local san_ip="${5:-}"
  local formats="${6:-pem}"
  local country="${7:-SG}"
  local state="${8:-Singapore}"
  local locality="${9:-Singapore}"
  local organization="${10:-Organization}"
  local ou="${11:-Engineering}"
  local days="${12:-365}"
  local curve="${13:-secp384r1}"
  local output_root="${14:?output root required}"
  local package_web="${15:-true}"

  local cert_dir="${output_root}/${cert_name}"
  local key_file="${cert_dir}/tls.key"
  local csr_file="${cert_dir}/${cert_name}.csr"
  local crt_file="${cert_dir}/tls.crt"
  local ext_file="${cert_dir}/${cert_name}.ext"
  local subject

  validate_cert_name "$cert_name"
  is_positive_integer "$days" || die "validity days must be a positive integer, got '$days'"
  validate_csv_dns "$san_dns"
  validate_csv_ip "$san_ip"
  validate_formats_csv "$formats"

  [[ -f "$CA_KEY" && -f "$CA_CERT" ]] || die "CA is not available. Run CA generation first."
  check_openssl_curve "$curve"

  secure_mkdir "$cert_dir"
  subject="$(build_subject "$country" "$state" "$locality" "$organization" "$ou" "$cn")"

  log_info "Generating ${profile} key for ${cert_name} (${curve})"
  openssl ecparam -name "$curve" -genkey -noout -out "$key_file"
  chmod 600 "$key_file"

  log_info "Generating CSR for ${cert_name}"
  openssl req -new -sha384 -key "$key_file" -out "$csr_file" -subj "$subject"
  chmod 600 "$csr_file"

  if [[ "$profile" == "server" ]]; then
    build_server_ext "$ext_file" "$san_dns" "$san_ip"
  else
    build_client_ext "$ext_file" "$san_dns" "$san_ip"
  fi
  chmod 600 "$ext_file"

  log_info "Signing ${profile} certificate for ${cert_name}"
  openssl x509 -req \
    -in "$csr_file" \
    -CA "$CA_CERT" \
    -CAkey "$CA_KEY" \
    -CAserial "$CA_SERIAL" \
    -CAcreateserial \
    -out "$crt_file" \
    -days "$days" \
    -sha384 \
    -extfile "$ext_file"
  chmod 644 "$crt_file"

  cp "$CA_CERT" "${cert_dir}/ca.crt"
  chmod 644 "${cert_dir}/ca.crt"

  emit_requested_formats "$cert_dir" "$crt_file" "$key_file" "$CA_CERT" "$formats" "$cert_name"

  # Friendly server packaging for common TLS consumers (e.g. reverse proxies)
  if [[ "$profile" == "server" && "$package_web" == "true" ]]; then
    cp "${cert_dir}/full-chain.crt" "${cert_dir}/fullchain.pem"
    cp "$key_file" "${cert_dir}/privkey.pem"
    chmod 644 "${cert_dir}/fullchain.pem"
    chmod 600 "${cert_dir}/privkey.pem"
  fi

  validate_cert "$crt_file" "$CA_CERT"
  check_sans "$crt_file" "$san_dns" "$san_ip"
  write_cert_summary "$crt_file" "${cert_dir}/cert-info.txt"

  rm -f "$csr_file" "$ext_file"
  log_ok "Generated ${profile} certificate set at ${cert_dir}"
}

generate_server_cert() {
  generate_leaf_cert "$1" "server" "$2" "${3:-}" "${4:-}" "${5:-pem}" \
    "${6:-SG}" "${7:-Singapore}" "${8:-Singapore}" "${9:-Organization}" "${10:-Engineering}" \
    "${11:-365}" "${12:-secp384r1}" "${13:?output root required}" "${14:-true}"
}

generate_client_cert() {
  generate_leaf_cert "$1" "client" "$2" "${3:-}" "${4:-}" "${5:-pem}" \
    "${6:-SG}" "${7:-Singapore}" "${8:-Singapore}" "${9:-Organization}" "${10:-Engineering}" \
    "${11:-365}" "${12:-secp384r1}" "${13:?output root required}" "false"
}

