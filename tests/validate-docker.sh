#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_ROOT}"

TMP_ROOT="$(mktemp -d /tmp/hsctl-docker-validate.XXXXXX)"
STATE_FILE="${TMP_ROOT}/state.env"
LEGACY_MARKER="${TMP_ROOT}/legacy-marker.env"
CONFIG_FILE="${TMP_ROOT}/install.env"
HS_ROOT="${TMP_ROOT}/instance"
TEST_CONTAINER="headscale-validate"
TEST_HOST="127.0.0.1"
PORT_CANDIDATES=(38080 39080 40080 41080 42080 43080)
PORT=""
AS_ROOT=0
INSTALL_DONE=0
INSTALL_ATTEMPTED=0
CURRENT_STAGE="initializing"
TIMEOUT_BIN=""
CMD_TIMEOUT_SECONDS=180

cleanup() {
  local exit_code=$?

  if [ "${exit_code}" -ne 0 ]; then
    dump_debug_info || true
  fi

  if [ "${INSTALL_ATTEMPTED}" -eq 1 ]; then
    echo
    echo "Cleaning up test instance..."
    if [ "${AS_ROOT}" -eq 1 ]; then
      HEADSCALE_STATE_FILE="${STATE_FILE}" HEADSCALE_LEGACY_MARKER="${LEGACY_MARKER}" \
        bash "${PROJECT_ROOT}/bin/hsctl" uninstall -y >/dev/null 2>&1 || true
    elif command -v sudo >/dev/null 2>&1; then
      sudo -E env HEADSCALE_STATE_FILE="${STATE_FILE}" HEADSCALE_LEGACY_MARKER="${LEGACY_MARKER}" \
        bash "${PROJECT_ROOT}/bin/hsctl" uninstall -y >/dev/null 2>&1 || true
    fi
  fi

  rm -rf "${TMP_ROOT}"
  exit "${exit_code}"
}
trap cleanup EXIT

pass() {
  printf 'PASS: %s\n' "$1"
}

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

run_cmd() {
  echo "+ $*"
  "$@"
}

find_timeout_bin() {
  if command -v timeout >/dev/null 2>&1; then
    TIMEOUT_BIN="timeout"
  elif command -v gtimeout >/dev/null 2>&1; then
    TIMEOUT_BIN="gtimeout"
  else
    fail "missing timeout command"
  fi
}

run_timed() {
  local seconds="$1"
  shift

  echo "+ timeout ${seconds}s $*"
  "${TIMEOUT_BIN}" --foreground "${seconds}" "$@"
}

run_hsctl() {
  if [ "${AS_ROOT}" -eq 1 ]; then
    HEADSCALE_STATE_FILE="${STATE_FILE}" HEADSCALE_LEGACY_MARKER="${LEGACY_MARKER}" \
      bash "${PROJECT_ROOT}/bin/hsctl" "$@"
  else
    sudo -E env HEADSCALE_STATE_FILE="${STATE_FILE}" HEADSCALE_LEGACY_MARKER="${LEGACY_MARKER}" \
      bash "${PROJECT_ROOT}/bin/hsctl" "$@"
  fi
}

run_hsctl_timed() {
  local seconds="$1"
  shift

  if [ "${AS_ROOT}" -eq 1 ]; then
    run_timed "${seconds}" env HEADSCALE_STATE_FILE="${STATE_FILE}" HEADSCALE_LEGACY_MARKER="${LEGACY_MARKER}" \
      bash "${PROJECT_ROOT}/bin/hsctl" "$@"
  else
    run_timed "${seconds}" sudo -E env HEADSCALE_STATE_FILE="${STATE_FILE}" HEADSCALE_LEGACY_MARKER="${LEGACY_MARKER}" \
      bash "${PROJECT_ROOT}/bin/hsctl" "$@"
  fi
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "missing command: $1"
}

dump_debug_info() {
  echo
  echo "==== Debug Info ===="
  echo "Current stage: ${CURRENT_STAGE}"
  echo "Temporary root: ${TMP_ROOT}"
  echo "Instance root: ${HS_ROOT}"
  echo "State file: ${STATE_FILE}"
  echo "Legacy marker: ${LEGACY_MARKER}"

  if [ -f "${CONFIG_FILE}" ]; then
    echo
    echo "-- install.env --"
    sed -n '1,200p' "${CONFIG_FILE}" || true
  fi

  if [ -f "${STATE_FILE}" ]; then
    echo
    echo "-- state.env --"
    sed -n '1,200p' "${STATE_FILE}" || true
  fi

  if [ -f "${HS_ROOT}/compose.yaml" ]; then
    echo
    echo "-- compose ps -a --"
    docker compose -f "${HS_ROOT}/compose.yaml" ps -a || true

    echo
    echo "-- compose logs --"
    docker compose -f "${HS_ROOT}/compose.yaml" logs --tail=200 "${TEST_CONTAINER}" || true

    echo
    echo "-- headscale version --"
    docker compose -f "${HS_ROOT}/compose.yaml" exec -T "${TEST_CONTAINER}" headscale version || true

    echo
    echo "-- headscale users list --"
    docker compose -f "${HS_ROOT}/compose.yaml" exec -T "${TEST_CONTAINER}" headscale users list || true
  fi

  echo "===================="
}

pick_port() {
  local candidate

  for candidate in "${PORT_CANDIDATES[@]}"; do
    if command -v ss >/dev/null 2>&1; then
      if ss -ltn "( sport = :${candidate} )" 2>/dev/null | grep -q ":${candidate}"; then
        continue
      fi
    fi
    PORT="${candidate}"
    return 0
  done

  fail "could not find a free test port"
}

write_config() {
  cat >"${CONFIG_FILE}" <<EOF
HS_ROOT=${HS_ROOT}
HEADSCALE_IMAGE=ghcr.io/juanfont/headscale
HEADSCALE_TAG=0.28.0
HS_CONTAINER=${TEST_CONTAINER}
SERVER_URL="http://${TEST_HOST}:${PORT}"
PORT=${PORT}
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
}

check_environment() {
  require_command docker
  find_timeout_bin
  run_cmd docker --version >/dev/null
  run_cmd docker compose version >/dev/null
  run_cmd docker info >/dev/null

  if [ "$(id -u)" -eq 0 ]; then
    AS_ROOT=1
  else
    require_command sudo
    run_cmd sudo -n true >/dev/null || fail "sudo requires a password; run this script with sudo"
  fi
}

verify_install_outputs() {
  [ -f "${HS_ROOT}/compose.yaml" ] || fail "missing compose.yaml"
  [ -f "${HS_ROOT}/config/config.yaml" ] || fail "missing config.yaml"
  [ -f "${HS_ROOT}/.hsctl-instance" ] || fail "missing instance marker"
  [ -f "${STATE_FILE}" ] || fail "missing state file"
  pass "install artifacts created"
}

verify_runtime() {
  local status_out users_out

  CURRENT_STAGE="status"
  status_out="$(run_hsctl_timed 60 status)"
  printf '%s\n' "${status_out}"
  printf '%s\n' "${status_out}" | grep -q 'container_exec: ok' || fail "container exec check failed"
  pass "status check"

  CURRENT_STAGE="user-list"
  users_out="$(run_hsctl_timed 60 user list)"
  printf '%s\n' "${users_out}"
  printf '%s\n' "${users_out}" | grep -qi 'admin' || fail "admin user not found"
  pass "user list check"

  CURRENT_STAGE="down"
  run_hsctl_timed 60 down
  pass "down command"

  CURRENT_STAGE="up"
  run_hsctl_timed 90 up
  pass "up command"
}

verify_uninstall() {
  CURRENT_STAGE="uninstall"
  run_hsctl_timed 90 uninstall -y
  INSTALL_DONE=0
  INSTALL_ATTEMPTED=0

  [ ! -d "${HS_ROOT}" ] || fail "HS_ROOT still exists after uninstall"
  [ ! -f "${STATE_FILE}" ] || fail "state file still exists after uninstall"
  [ ! -f "${LEGACY_MARKER}" ] || fail "legacy marker still exists after uninstall"
  pass "uninstall cleanup"
}

main() {
  echo "Running Docker validation in ${PROJECT_ROOT}"

  CURRENT_STAGE="environment-check"
  check_environment
  CURRENT_STAGE="pick-port"
  pick_port
  CURRENT_STAGE="write-config"
  write_config

  echo "Using temporary root: ${HS_ROOT}"
  echo "Using test port: ${PORT}"

  CURRENT_STAGE="install"
  INSTALL_ATTEMPTED=1
  run_hsctl_timed "${CMD_TIMEOUT_SECONDS}" install --auto --config "${CONFIG_FILE}"
  INSTALL_DONE=1
  pass "install command"

  CURRENT_STAGE="verify-install-artifacts"
  verify_install_outputs
  CURRENT_STAGE="verify-runtime"
  verify_runtime
  CURRENT_STAGE="verify-uninstall"
  verify_uninstall

  echo
  echo "Docker validation completed successfully."
}

main "$@"
