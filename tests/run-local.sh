#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

valac \
  --pkg glib-2.0 \
  --directory "${TMP_DIR}" \
  -o "${TMP_DIR}/test-contact-autocomplete-policy" \
  "${ROOT_DIR}/src/client/composer/contact-autocomplete-policy.vala" \
  "${ROOT_DIR}/tests/test-contact-autocomplete-policy.vala"

"${TMP_DIR}/test-contact-autocomplete-policy"
glib-compile-schemas --strict --dry-run "${ROOT_DIR}/desktop"
git -C "${ROOT_DIR}" diff --check
