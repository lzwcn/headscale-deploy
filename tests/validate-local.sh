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

  PROJECT_ROOT="${PROJECT_ROOT}" env_file="${env_file}" marker="${marker}" bash <<'EOF'
set -euo pipefail
# shellcheck source=../lib/common.sh
. "${PROJECT_ROOT}/lib/common.sh"
SERVER_URL=""
HEADSCALE_TAG=""
load_env_file "${env_file}"
[ "${SERVER_URL}" = "\$(touch ${marker})" ] || exit 1
[ "${HEADSCALE_TAG}" = "0.28.0" ] || exit 1
[ ! -e "${marker}" ] || exit 1
EOF
}

test_state_roundtrip_guard() {
  local state_root="${TMP_ROOT}/state-root"
  local marker="${TMP_ROOT}/state-triggered"

  mkdir -p "${state_root}"
  rm -f "${marker}"

  PROJECT_ROOT="${PROJECT_ROOT}" state_root="${state_root}" marker="${marker}" bash <<'EOF'
set -euo pipefail
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
EOF
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
DOCKER_MODE=host
HS_DOCKER_NETWORK=
DERP_MODE=disabled
DERP_REGION_ID=999
DERP_REGION_CODE=headscale
DERP_REGION_NAME="Headscale Embedded DERP"
DERP_STUN_LISTEN_ADDR=:3478
DERP_IPV4=
DERP_IPV6=
DERP_INCLUDE_DEFAULTS=true
DERP_AUTO_ADD_EMBEDDED_REGION=true
DNS_GLOBAL_NAMESERVERS=1.1.1.1,1.0.0.1,2606:4700:4700::1111,2606:4700:4700::1001
EOF

  bash bin/hsctl render --auto --config "${config_file}"

  [ -f "${instance_root}/config/config.yaml" ] || exit 1
  [ -f "${instance_root}/compose.yaml" ] || exit 1
  grep -q '^server_url: https://example.com$' "${instance_root}/config/config.yaml"
  grep -q 'image: ghcr.io/juanfont/headscale:0.28.0' "${instance_root}/compose.yaml"
}

test_derp_host_render() {
  local instance_root="${TMP_ROOT}/derp-host-instance"
  local config_file="${TMP_ROOT}/derp-host.env"

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
DOCKER_MODE=host
HS_DOCKER_NETWORK=
DERP_MODE=private
DERP_REGION_ID=999
DERP_REGION_CODE=hkg
DERP_REGION_NAME="Hong Kong DERP"
DERP_STUN_LISTEN_ADDR=:3478
DERP_IPV4=203.0.113.10
DERP_IPV6=2001:db8::10
DERP_INCLUDE_DEFAULTS=true
DERP_AUTO_ADD_EMBEDDED_REGION=true
DNS_GLOBAL_NAMESERVERS=223.5.5.5,223.6.6.6,2400:3200::1,1.1.1.1
EOF

  bash bin/hsctl render --auto --config "${config_file}"

  [ -f "${instance_root}/compose.yaml" ] || exit 1
  grep -q 'network_mode: host' "${instance_root}/compose.yaml"
  if grep -q '^    ports:' "${instance_root}/compose.yaml"; then
    exit 1
  fi

  grep -q 'stun_listen_addr: ":3478"' "${instance_root}/config/config.yaml"
  grep -q 'region_code: "hkg"' "${instance_root}/config/config.yaml"
  grep -q '^    ipv4: 203.0.113.10$' "${instance_root}/config/config.yaml"
  grep -q '^    ipv6: 2001:db8::10$' "${instance_root}/config/config.yaml"
  grep -q '223.5.5.5' "${instance_root}/config/config.yaml"
  grep -q '2400:3200::1' "${instance_root}/config/config.yaml"
}

test_ipv6_listen_render() {
  local instance_root="${TMP_ROOT}/ipv6-listen-instance"
  local config_file="${TMP_ROOT}/ipv6-listen.env"

  cat >"${config_file}" <<EOF
HS_ROOT=${instance_root}
HEADSCALE_IMAGE=ghcr.io/juanfont/headscale
HEADSCALE_TAG=0.28.0
HS_CONTAINER=headscale
SERVER_URL="https://example.com"
PORT=8080
LISTEN_ADDR=::
FIRST_USERNAME=admin
BASE_DOMAIN=headscale.internal
DOCKER_MODE=host
HS_DOCKER_NETWORK=
DERP_MODE=disabled
DERP_REGION_ID=999
DERP_REGION_CODE=headscale
DERP_REGION_NAME="Headscale Embedded DERP"
DERP_STUN_LISTEN_ADDR=:3478
DERP_IPV4=
DERP_IPV6=
DERP_INCLUDE_DEFAULTS=true
DERP_AUTO_ADD_EMBEDDED_REGION=true
DNS_GLOBAL_NAMESERVERS=1.1.1.1,1.0.0.1,2606:4700:4700::1111,2606:4700:4700::1001
EOF

  bash bin/hsctl render --auto --config "${config_file}"

  grep -q '^listen_addr: \[::\]:8080$' "${instance_root}/config/config.yaml"
}

test_derp_stun_ipv6_render() {
  local instance_root="${TMP_ROOT}/derp-stun-ipv6"
  local config_file="${TMP_ROOT}/derp-stun-ipv6.env"

  cat >"${config_file}" <<EOF
HS_ROOT=${instance_root}
HEADSCALE_IMAGE=ghcr.io/juanfont/headscale
HEADSCALE_TAG=0.28.0
HS_CONTAINER=headscale
SERVER_URL="https://example.com"
PORT=8080
LISTEN_ADDR=2001:db8::20
FIRST_USERNAME=admin
BASE_DOMAIN=headscale.internal
DOCKER_MODE=host
HS_DOCKER_NETWORK=
DERP_MODE=private
DERP_REGION_ID=999
DERP_REGION_CODE=hkg
DERP_REGION_NAME="Hong Kong DERP"
DERP_STUN_LISTEN_ADDR=[::]:3478
DERP_IPV4=203.0.113.10
DERP_IPV6=2001:db8::10
DERP_INCLUDE_DEFAULTS=true
DERP_AUTO_ADD_EMBEDDED_REGION=true
DNS_GLOBAL_NAMESERVERS=1.1.1.1,1.0.0.1,2606:4700:4700::1111,2606:4700:4700::1001
EOF

  bash bin/hsctl render --auto --config "${config_file}"

  grep -q '^listen_addr: \[2001:db8::20\]:8080$' "${instance_root}/config/config.yaml"
  grep -q 'stun_listen_addr: "\[::\]:3478"' "${instance_root}/config/config.yaml"
}

test_legacy_install_passthrough() {
  local instance_root="${TMP_ROOT}/legacy-install"
  local config_file="${TMP_ROOT}/legacy-install.env"

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
DOCKER_MODE=host
HS_DOCKER_NETWORK=
DERP_MODE=disabled
DERP_REGION_ID=999
DERP_REGION_CODE=headscale
DERP_REGION_NAME="Headscale Embedded DERP"
DERP_STUN_LISTEN_ADDR=:3478
DERP_IPV4=
DERP_IPV6=
DERP_INCLUDE_DEFAULTS=true
DERP_AUTO_ADD_EMBEDDED_REGION=true
DNS_GLOBAL_NAMESERVERS=1.1.1.1,1.0.0.1,2606:4700:4700::1111,2606:4700:4700::1001
EOF

  (
    set -euo pipefail
    TEMPLATE_DIR="${PROJECT_ROOT}/templates"
    RUNTIME_DIR="${TMP_ROOT}/legacy-runtime"
    STATE_FILE_DEFAULT="${RUNTIME_DIR}/state.env"
    LEGACY_MARKER_DEFAULT="${RUNTIME_DIR}/legacy-marker.env"

    # shellcheck source=../lib/common.sh
    . "${PROJECT_ROOT}/lib/common.sh"
    # shellcheck source=../lib/state.sh
    . "${PROJECT_ROOT}/lib/state.sh"
    # shellcheck source=../lib/validate.sh
    . "${PROJECT_ROOT}/lib/validate.sh"
    # shellcheck source=../lib/render.sh
    . "${PROJECT_ROOT}/lib/render.sh"
    # shellcheck source=../lib/install.sh
    . "${PROJECT_ROOT}/lib/install.sh"
    # shellcheck source=../lib/legacy.sh
    . "${PROJECT_ROOT}/lib/legacy.sh"

    run_install_command() {
      run_render_command "$@"
    }

    legacy_main --config "${config_file}" --auto --listenaddr :: --prefix "${instance_root}" >/dev/null
  )

  grep -q '^listen_addr: \[::\]:8080$' "${instance_root}/config/config.yaml"
  grep -q 'network_mode: host' "${instance_root}/compose.yaml"
}

test_install_env_example_semantics() {
  grep -q '^DOCKER_MODE=host$' templates/install.env.example
  grep -q '^HS_DOCKER_NETWORK=$' templates/install.env.example
}

test_derp_ipv6_network_warning() {
  local instance_root="${TMP_ROOT}/derp-network-warning"
  local config_file="${TMP_ROOT}/derp-network-warning.env"
  local output_file="${TMP_ROOT}/derp-network-warning.out"

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
DOCKER_MODE=network
HS_DOCKER_NETWORK=headscale
DERP_MODE=private
DERP_REGION_ID=999
DERP_REGION_CODE=headscale
DERP_REGION_NAME="Headscale Embedded DERP"
DERP_STUN_LISTEN_ADDR=:3478
DERP_IPV4=203.0.113.10
DERP_IPV6=2001:db8::10
DERP_INCLUDE_DEFAULTS=true
DERP_AUTO_ADD_EMBEDDED_REGION=true
DNS_GLOBAL_NAMESERVERS=1.1.1.1,1.0.0.1,2606:4700:4700::1111,2606:4700:4700::1001
EOF

  bash bin/hsctl render --auto --config "${config_file}" >"${output_file}" 2>&1
  grep -q 'Embedded DERP with IPv6 may fail behind Docker bridge networking. Prefer DOCKER_MODE=host.' "${output_file}"
}

test_interactive_derp_requires_server_url_early() {
  local output_file="${TMP_ROOT}/interactive-derp-serverurl.out"
  local input_file="${TMP_ROOT}/interactive-derp-serverurl.in"

  cat >"${input_file}" <<'EOF'

host






private
EOF

  if bash bin/hsctl install <"${input_file}" >"${output_file}" 2>&1; then
    exit 1
  fi

  grep -q 'Interactive install' "${output_file}"
  grep -q 'Embedded DERP requires an explicit HTTPS SERVER_URL. Please enter https://<your-headscale-domain> during interactive install.' "${output_file}"
}

test_derp_requires_https_server_url() {
  local instance_root="${TMP_ROOT}/derp-http-instance"
  local config_file="${TMP_ROOT}/derp-http.env"
  local output_file="${TMP_ROOT}/derp-http.out"

  cat >"${config_file}" <<EOF
HS_ROOT=${instance_root}
HEADSCALE_IMAGE=ghcr.io/juanfont/headscale
HEADSCALE_TAG=0.28.0
HS_CONTAINER=headscale
SERVER_URL=
PORT=8080
LISTEN_ADDR=0.0.0.0
FIRST_USERNAME=admin
BASE_DOMAIN=headscale.internal
DOCKER_MODE=host
HS_DOCKER_NETWORK=
DERP_MODE=private
DERP_REGION_ID=999
DERP_REGION_CODE=headscale
DERP_REGION_NAME="Headscale Embedded DERP"
DERP_STUN_LISTEN_ADDR=:3478
DERP_IPV4=203.0.113.10
DERP_IPV6=2001:db8::10
DERP_INCLUDE_DEFAULTS=true
DERP_AUTO_ADD_EMBEDDED_REGION=true
DNS_GLOBAL_NAMESERVERS=1.1.1.1,1.0.0.1,2606:4700:4700::1111,2606:4700:4700::1001
EOF

  if bash bin/hsctl render --auto --config "${config_file}" >"${output_file}" 2>&1; then
    exit 1
  fi

  grep -q 'Embedded DERP requires an explicit HTTPS SERVER_URL.' "${output_file}"
}

main() {
  printf 'Running local validations in %s\n' "${PROJECT_ROOT}"

  run_expect_success "bash syntax" test_bash_syntax
  run_expect_success "env injection guard" test_env_injection_guard
  run_expect_success "state round-trip guard" test_state_roundtrip_guard
  run_expect_success "dangerous prefix rejected" test_dangerous_prefix_rejected
  run_expect_success "safe render" test_safe_render
  run_expect_success "derp host render" test_derp_host_render
  run_expect_success "ipv6 listen render" test_ipv6_listen_render
  run_expect_success "derp stun ipv6 render" test_derp_stun_ipv6_render
  run_expect_success "legacy install passthrough" test_legacy_install_passthrough
  run_expect_success "install env example semantics" test_install_env_example_semantics
  run_expect_success "interactive derp requires server_url early" test_interactive_derp_requires_server_url_early
  run_expect_success "derp ipv6 network warning" test_derp_ipv6_network_warning
  run_expect_success "derp requires https server_url" test_derp_requires_https_server_url

  printf '\nAll local validations passed.\n'
  printf 'Optional next step: run a real install test on a Docker-enabled Linux host.\n'
}

main "$@"
