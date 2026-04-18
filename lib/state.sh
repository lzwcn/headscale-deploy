#!/usr/bin/env bash

bootstrap_runtime_defaults() {
  OFFICIAL_GIT="https://github.com/juanfont/headscale"
  OFFICIAL_REGISTRY="ghcr.io/juanfont/headscale"

  STATE_FILE="${HEADSCALE_STATE_FILE:-${STATE_FILE_DEFAULT}}"
  LEGACY_MARKER="${HEADSCALE_LEGACY_MARKER:-${LEGACY_MARKER_DEFAULT}}"

  HEADSCALE_IMAGE="${HEADSCALE_IMAGE:-${OFFICIAL_REGISTRY}}"
  HEADSCALE_TAG="${HEADSCALE_TAG:-0.28.0}"
  HS_CONTAINER="${HS_CONTAINER:-headscale}"

  HS_ROOT="${HS_ROOT:-${RUNTIME_DIR}/instance}"
  SERVER_URL="${SERVER_URL:-}"
  PORT="${PORT:-8080}"
  LISTEN_ADDR="${LISTEN_ADDR:-0.0.0.0}"
  FIRST_USERNAME="${FIRST_USERNAME:-admin}"
  BASE_DOMAIN="${BASE_DOMAIN:-headscale.internal}"
  DOCKER_MODE="${DOCKER_MODE:-host}"
  HS_DOCKER_NETWORK="${HS_DOCKER_NETWORK:-headscale}"
  DERP_MODE="${DERP_MODE:-disabled}"
  DERP_REGION_ID="${DERP_REGION_ID:-999}"
  DERP_REGION_CODE="${DERP_REGION_CODE:-headscale}"
  DERP_REGION_NAME="${DERP_REGION_NAME:-Headscale Embedded DERP}"
  DERP_STUN_LISTEN_ADDR="${DERP_STUN_LISTEN_ADDR:-:3478}"
  DERP_STUN_PORT="${DERP_STUN_PORT:-3478}"
  DERP_IPV4="${DERP_IPV4:-}"
  DERP_IPV6="${DERP_IPV6:-}"
  DERP_INCLUDE_DEFAULTS="${DERP_INCLUDE_DEFAULTS:-true}"
  DERP_AUTO_ADD_EMBEDDED_REGION="${DERP_AUTO_ADD_EMBEDDED_REGION:-true}"
  DNS_GLOBAL_NAMESERVERS="${DNS_GLOBAL_NAMESERVERS:-1.1.1.1,1.0.0.1,2606:4700:4700::1111,2606:4700:4700::1001}"

  AUTO=0
  ASSUME_YES=0
  NO_BACKUP=0
  IMAGE_TAG_EXPLICIT=0

  TARGET_USER=""
  TARGET_NODE_ID=""
  TARGET_NODE_KEY=""
  TARGET_USERNAME=""

  SANITIZED_USERNAME=""
  COMPUTED_SERVER_URL=""
  INITIAL_USER_ID=""
  IP_ADDR=""
  PUBLIC_IP_ADDR=""
  OS_FAMILY=""
  OS_VERSION=""

  apply_hs_paths
  normalize_network_mode
}

apply_hs_paths() {
  if [[ "${HS_ROOT}" != /* ]]; then
    HS_ROOT="${PROJECT_ROOT}/${HS_ROOT#./}"
  fi
  while [ "${HS_ROOT}" != "/" ] && [[ "${HS_ROOT}" == */ ]]; do
    HS_ROOT="${HS_ROOT%/}"
  done
  HS_CONF_DIR="${HS_ROOT}/config"
  HS_CONF="${HS_CONF_DIR}/config.yaml"
  HS_DATA_DIR="${HS_ROOT}/data"
  HS_COMPOSE="${HS_ROOT}/compose.yaml"
  HS_INSTANCE_MARKER="${HS_ROOT}/.hsctl-instance"
}

normalize_network_mode() {
  case "${DOCKER_MODE}" in
    portmap|none)
      DOCKER_MODE="portmap"
      HS_DOCKER_NETWORK=""
      ;;
    host)
      DOCKER_MODE="host"
      HS_DOCKER_NETWORK=""
      ;;
    *)
      DOCKER_MODE="network"
      HS_DOCKER_NETWORK="${HS_DOCKER_NETWORK:-headscale}"
      ;;
  esac
}

normalize_derp_mode() {
  case "${DERP_MODE}" in
    disabled|private|public) ;;
    *)
      exiterr "Invalid DERP_MODE: ${DERP_MODE}"
      ;;
  esac

  DERP_STUN_PORT="$(extract_socket_port "${DERP_STUN_LISTEN_ADDR}")" ||
    exiterr "Invalid DERP_STUN_LISTEN_ADDR: ${DERP_STUN_LISTEN_ADDR}"
}

load_persisted_state() {
  if [ -f "${STATE_FILE}" ]; then
    load_env_file "${STATE_FILE}"
  elif [ -f "${LEGACY_MARKER}" ]; then
    load_env_file "${LEGACY_MARKER}"
    if [ -n "${HS_DOCKER_NETWORK:-}" ]; then
      DOCKER_MODE="network"
    else
      DOCKER_MODE="portmap"
    fi
  fi

  apply_hs_paths
  normalize_network_mode
  normalize_derp_mode
}

write_state_file() {
  mkdir -p "${RUNTIME_DIR}"
  {
    printf 'HS_ROOT=%s\n' "$(env_quote_value "${HS_ROOT}")"
    printf 'HEADSCALE_IMAGE=%s\n' "$(env_quote_value "${HEADSCALE_IMAGE}")"
    printf 'HEADSCALE_TAG=%s\n' "$(env_quote_value "${HEADSCALE_TAG}")"
    printf 'HS_CONTAINER=%s\n' "$(env_quote_value "${HS_CONTAINER}")"
    printf 'SERVER_URL=%s\n' "$(env_quote_value "${SERVER_URL}")"
    printf 'PORT=%s\n' "$(env_quote_value "${PORT}")"
    printf 'LISTEN_ADDR=%s\n' "$(env_quote_value "${LISTEN_ADDR}")"
    printf 'FIRST_USERNAME=%s\n' "$(env_quote_value "${FIRST_USERNAME}")"
    printf 'BASE_DOMAIN=%s\n' "$(env_quote_value "${BASE_DOMAIN}")"
    printf 'DOCKER_MODE=%s\n' "$(env_quote_value "${DOCKER_MODE}")"
    printf 'HS_DOCKER_NETWORK=%s\n' "$(env_quote_value "${HS_DOCKER_NETWORK}")"
    printf 'DERP_MODE=%s\n' "$(env_quote_value "${DERP_MODE}")"
    printf 'DERP_REGION_ID=%s\n' "$(env_quote_value "${DERP_REGION_ID}")"
    printf 'DERP_REGION_CODE=%s\n' "$(env_quote_value "${DERP_REGION_CODE}")"
    printf 'DERP_REGION_NAME=%s\n' "$(env_quote_value "${DERP_REGION_NAME}")"
    printf 'DERP_STUN_LISTEN_ADDR=%s\n' "$(env_quote_value "${DERP_STUN_LISTEN_ADDR}")"
    printf 'DERP_STUN_PORT=%s\n' "$(env_quote_value "${DERP_STUN_PORT}")"
    printf 'DERP_IPV4=%s\n' "$(env_quote_value "${DERP_IPV4}")"
    printf 'DERP_IPV6=%s\n' "$(env_quote_value "${DERP_IPV6}")"
    printf 'DERP_INCLUDE_DEFAULTS=%s\n' "$(env_quote_value "${DERP_INCLUDE_DEFAULTS}")"
    printf 'DERP_AUTO_ADD_EMBEDDED_REGION=%s\n' "$(env_quote_value "${DERP_AUTO_ADD_EMBEDDED_REGION}")"
    printf 'DNS_GLOBAL_NAMESERVERS=%s\n' "$(env_quote_value "${DNS_GLOBAL_NAMESERVERS}")"
  } >"${STATE_FILE}"
  safe_chmod 640 "${STATE_FILE}"
}

write_legacy_marker() {
  if [ "$(id -u)" != 0 ]; then
    return 0
  fi

  {
    printf 'HS_ROOT=%s\n' "$(env_quote_value "${HS_ROOT}")"
    printf 'HEADSCALE_IMAGE=%s\n' "$(env_quote_value "${HEADSCALE_IMAGE}")"
    printf 'HEADSCALE_TAG=%s\n' "$(env_quote_value "${HEADSCALE_TAG}")"
    printf 'HS_DOCKER_NETWORK=%s\n' "$(env_quote_value "${HS_DOCKER_NETWORK}")"
  } >"${LEGACY_MARKER}"
  safe_chmod 644 "${LEGACY_MARKER}"
}

write_instance_marker() {
  mkdir -p "${HS_ROOT}"
  cat >"${HS_INSTANCE_MARKER}" <<EOF
managed_by=hsctl
project_root=${PROJECT_ROOT}
EOF
  safe_chmod 640 "${HS_INSTANCE_MARKER}"
}

clear_state_files() {
  rm -f "${STATE_FILE}"
  if [ "$(id -u)" = 0 ]; then
    rm -f "${LEGACY_MARKER}"
  fi
}

require_install_files() {
  apply_hs_paths
  [ -f "${HS_CONF}" ] || exiterr "Missing ${HS_CONF}"
  [ -f "${HS_COMPOSE}" ] || exiterr "Missing ${HS_COMPOSE}"
}

has_install_files() {
  apply_hs_paths
  [ -f "${HS_CONF}" ] || [ -f "${HS_COMPOSE}" ] || [ -d "${HS_DATA_DIR}" ]
}

data_dir_has_content() {
  apply_hs_paths
  [ -d "${HS_DATA_DIR}" ] && find "${HS_DATA_DIR}" -mindepth 1 -print -quit 2>/dev/null | grep -q .
}
