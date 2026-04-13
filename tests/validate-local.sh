#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_ROOT}"

TMP_ROOT="$(mktemp -d /tmp/hsctl-validate.XXXXXX)"
trap 'rm -rf "${TMP_ROOT}"' EXIT

pass() {
  printf 'PASS: %s\n' "$1"
}

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

run_expect_success() {
  local name="$1"
  shift

  if "$@"; then
    pass "${name}"
  else
    fail "${name}"
  fi
}

test_bash_syntax() {
  bash -n bin/hsctl headscale-install.sh lib/*.sh tests/*.sh
}

test_env_injection_guard() {
  local env_file="${TMP_ROOT}/rce.env"
  local marker="${TMP_ROOT}/rce-triggered"

  rm -f "${marker}"
  cat >"${env_file}" <<EOF
SERVER_URL="\$(touch ${marker})"
HEADSCALE_TAG="0.28.0"
EOF

  (
    set -euo pipefail
    # shellcheck source=../lib/common.sh
    . "${PROJECT_ROOT}/lib/common.sh"
    SERVER_URL=""
    HEADSCALE_TAG=""
    load_env_file "${env_file}"
    [ "${SERVER_URL}" = "\$(touch ${marker})" ] || exit 1
    [ "${HEADSCALE_TAG}" = "0.28.0" ] || exit 1
    [ ! -e "${marker}" ] || exit 1
  )
}

test_state_roundtrip_guard() {
  local state_root="${TMP_ROOT}/state-root"
  local marker="${TMP_ROOT}/state-triggered"

  mkdir -p "${state_root}"
  rm -f "${marker}"

  (
    set -euo pipefail
    PROJECT_ROOT="${PROJECT_ROOT}"
    RUNTIME_DIR="${state_root}"
    STATE_FILE_DEFAULT="${RUNTIME_DIR}/state.env"
    LEGACY_MARKER_DEFAULT="${RUNTIME_DIR}/legacy.env"

    # shellcheck source=../lib/common.sh
    . "${PROJECT_ROOT}/lib/common.sh"
    # shellcheck source=../lib/state.sh
    . "${PROJECT_ROOT}/lib/state.sh"

    bootstrap_runtime_defaults
    HS_ROOT="${state_root}/instance dir"
    printf -v SERVER_URL '%s' "\$(touch ${marker})"

    write_state_file

    SERVER_URL=""
    HS_ROOT=""
    load_env_file "${STATE_FILE}"

    [ "${HS_ROOT}" = "${state_root}/instance dir" ] || exit 1
    [ "${SERVER_URL}" = "\$(touch ${marker})" ] || exit 1
    [ ! -e "${marker}" ] || exit 1
  )
}

test_dangerous_prefix_rejected() {
  local output_file="${TMP_ROOT}/unsafe-prefix.out"

  if bash bin/hsctl render --auto --prefix / --serverurl https://example.com --docker-network none \
    >"${output_file}" 2>&1; then
    return 1
  fi

  grep -q 'Refusing unsafe HS_ROOT: /' "${output_file}"
}

test_safe_render() {
  local instance_root="${TMP_ROOT}/render-instance"
  local config_file="${TMP_ROOT}/install.env"

  cat >"${config_file}" <<EOF
HS_ROOT=${instance_root}
HEADSCALE_IMAGE=ghcr.io/juanfont/headscale
HEADSCALE_TAG=0.28.0
HS_CONTAINER=headscale
SERVER_URL="https://example.com"
PORT=8080
LISTEN_ADDR=0.0.0.0
FIRST_USERNAME=admin
BASE_DOMAIN=headscale.internal
DOCKER_MODE=portmap
HS_DOCKER_NETWORK=
DERP_MODE=disabled
DERP_REGION_ID=999
DERP_REGION_CODE=headscale
DERP_REGION_NAME="Headscale Embedded DERP"
DERP_STUN_LISTEN_ADDR=0.0.0.0:3478
DERP_IPV4=
DERP_IPV6=
DERP_INCLUDE_DEFAULTS=true
DERP_AUTO_ADD_EMBEDDED_REGION=true
EOF

  bash bin/hsctl render --auto --config "${config_file}"

  [ -f "${instance_root}/config/config.yaml" ] || exit 1
  [ -f "${instance_root}/compose.yaml" ] || exit 1
  grep -q '^server_url: https://example.com$' "${instance_root}/config/config.yaml"
  grep -q 'image: ghcr.io/juanfont/headscale:0.28.0' "${instance_root}/compose.yaml"
}

main() {
  printf 'Running local validations in %s\n' "${PROJECT_ROOT}"

  run_expect_success "bash syntax" test_bash_syntax
  run_expect_success "env injection guard" test_env_injection_guard
  run_expect_success "state round-trip guard" test_state_roundtrip_guard
  run_expect_success "dangerous prefix rejected" test_dangerous_prefix_rejected
  run_expect_success "safe render" test_safe_render

  printf '\nAll local validations passed.\n'
  printf 'Optional next step: run a real install test on a Docker-enabled Linux host.\n'
}

main "$@"
