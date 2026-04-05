#!/usr/bin/env bash

set -euo pipefail

build_server_ext() {
  local ext_path="${1:?ext_path required}"
  local san_dns_csv="${2:-}"
  local san_ip_csv="${3:-}"
  local i
  local has_sans=0

  {
    echo "authorityKeyIdentifier=keyid,issuer"
    echo "basicConstraints=critical,CA:FALSE"
    echo "keyUsage=critical,digitalSignature,keyEncipherment"
    echo "extendedKeyUsage=serverAuth"
    if [[ -n "$san_dns_csv" || -n "$san_ip_csv" ]]; then
      echo "subjectAltName=@alt_names"
      echo
      echo "[alt_names]"
      i=1
      while IFS= read -r entry; do
        [[ -z "$entry" ]] && continue
        has_sans=1
        echo "DNS.${i}=${entry}"
        ((i++))
      done < <(csv_to_lines "$san_dns_csv")
      i=1
      while IFS= read -r entry; do
        [[ -z "$entry" ]] && continue
        has_sans=1
        echo "IP.${i}=${entry}"
        ((i++))
      done < <(csv_to_lines "$san_ip_csv")
    fi
  } >"$ext_path"

  if [[ "$has_sans" -eq 0 ]]; then
    sed -i.bak '/subjectAltName=@alt_names/,$d' "$ext_path" && rm -f "${ext_path}.bak"
  fi
}

build_client_ext() {
  local ext_path="${1:?ext_path required}"
  local san_dns_csv="${2:-}"
  local san_ip_csv="${3:-}"
  local i
  local has_sans=0

  {
    echo "authorityKeyIdentifier=keyid,issuer"
    echo "basicConstraints=critical,CA:FALSE"
    echo "keyUsage=critical,digitalSignature"
    echo "extendedKeyUsage=clientAuth"
    if [[ -n "$san_dns_csv" || -n "$san_ip_csv" ]]; then
      echo "subjectAltName=@alt_names"
      echo
      echo "[alt_names]"
      i=1
      while IFS= read -r entry; do
        [[ -z "$entry" ]] && continue
        has_sans=1
        echo "DNS.${i}=${entry}"
        ((i++))
      done < <(csv_to_lines "$san_dns_csv")
      i=1
      while IFS= read -r entry; do
        [[ -z "$entry" ]] && continue
        has_sans=1
        echo "IP.${i}=${entry}"
        ((i++))
      done < <(csv_to_lines "$san_ip_csv")
    fi
  } >"$ext_path"

  if [[ "$has_sans" -eq 0 ]]; then
    sed -i.bak '/subjectAltName=@alt_names/,$d' "$ext_path" && rm -f "${ext_path}.bak"
  fi
}

