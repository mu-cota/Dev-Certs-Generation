#!/usr/bin/env bash

set -euo pipefail

FORCE=false
TARGETS=("output" "certificates" "data" "config")

if [[ "${1:-}" == "--force" ]]; then
  FORCE=true
elif [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  echo "Usage: ./cleanup.sh [--force]"
  exit 0
fi

if [[ "$FORCE" != "true" ]]; then
  echo "This will remove generated certificate artifacts:"
  printf '  - %s\n' "${TARGETS[@]}"
  read -r -p "Continue? [y/N]: " response
  case "${response:-}" in
    y|Y|yes|YES) ;;
    *) echo "Aborted."; exit 0 ;;
  esac
fi

for path in "${TARGETS[@]}"; do
  if [[ -e "$path" ]]; then
    rm -rf "$path"
    echo "[OK] Removed: $path"
  else
    echo "[INFO] Skipped (not found): $path"
  fi
done

echo "[OK] Cleanup complete."
