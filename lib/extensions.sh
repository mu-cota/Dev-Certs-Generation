#!/usr/bin/env bash

set -euo pipefail

build_server_ext() {
  local ext_path="${1:?ext_path required}"
  local san_dns_csv="${2:-}"
  local san_ip_csv="${3:-}"
  local -a dns_list=()
  local -a ip_list=()
  local i=1

  csv_to_array "$san_dns_csv" dns_list
  csv_to_array "$san_ip_csv" ip_list

  {
    echo "authorityKeyIdentifier=keyid,issuer"
    echo "basicConstraints=critical,CA:FALSE"
    echo "keyUsage=critical,digitalSignature,keyEncipherment"
    echo "extendedKeyUsage=serverAuth"
    if [[ ${#dns_list[@]} -gt 0 || ${#ip_list[@]} -gt 0 ]]; then
      echo "subjectAltName=@alt_names"
      echo
      echo "[alt_names]"
      for entry in "${dns_list[@]}"; do
        echo "DNS.${i}=${entry}"
        ((i++))
      done
      i=1
      for entry in "${ip_list[@]}"; do
        echo "IP.${i}=${entry}"
        ((i++))
      done
    fi
  } >"$ext_path"
}

build_client_ext() {
  local ext_path="${1:?ext_path required}"
  local san_dns_csv="${2:-}"
  local san_ip_csv="${3:-}"
  local -a dns_list=()
  local -a ip_list=()
  local i=1

  csv_to_array "$san_dns_csv" dns_list
  csv_to_array "$san_ip_csv" ip_list

  {
    echo "authorityKeyIdentifier=keyid,issuer"
    echo "basicConstraints=critical,CA:FALSE"
    echo "keyUsage=critical,digitalSignature"
    echo "extendedKeyUsage=clientAuth"
    if [[ ${#dns_list[@]} -gt 0 || ${#ip_list[@]} -gt 0 ]]; then
      echo "subjectAltName=@alt_names"
      echo
      echo "[alt_names]"
      for entry in "${dns_list[@]}"; do
        echo "DNS.${i}=${entry}"
        ((i++))
      done
      i=1
      for entry in "${ip_list[@]}"; do
        echo "IP.${i}=${entry}"
        ((i++))
      done
    fi
  } >"$ext_path"
}

