#!/usr/bin/env bash

validate_install_settings() {
  normalize_network_mode
  normalize_derp_mode
  apply_hs_paths

  [ -n "${HS_ROOT}" ] || exiterr "HS_ROOT is required."
  validate_hs_root
  [ -n "${HEADSCALE_IMAGE}" ] || exiterr "HEADSCALE_IMAGE is required."
  [ -n "${HEADSCALE_TAG}" ] || exiterr "HEADSCALE_TAG is required."

  [ -n "${SERVER_URL}" ] && SERVER_URL="${SERVER_URL%/}"
  [ -n "${SERVER_URL}" ] && ! check_url "${SERVER_URL}" && exiterr "Invalid server URL."
  ! check_port "${PORT}" && exiterr "Invalid port."
  ! check_ip "${LISTEN_ADDR}" && exiterr "Invalid listen address (IPv4 only)."
  ! check_dns_name "${BASE_DOMAIN}" && exiterr "Invalid base domain."

  sanitize_username "${FIRST_USERNAME}"
  [ -n "${SANITIZED_USERNAME}" ] || exiterr "Invalid initial user name."
  FIRST_USERNAME="${SANITIZED_USERNAME}"

  if [ "${DOCKER_MODE}" = "network" ] && [ -z "${SERVER_URL}" ]; then
    exiterr "--serverurl is required when using an external Docker network."
  fi

  if [ "${DERP_MODE}" != "disabled" ] && [ -n "${SERVER_URL}" ] &&
    ! printf '%s' "${SERVER_URL}" | grep -q '^https://'; then
    exiterr "DERP requires an HTTPS server_url."
  fi

  if [ -n "${DERP_IPV4}" ] && ! check_ip "${DERP_IPV4}"; then
    exiterr "Invalid DERP IPv4 address."
  fi

  if [ -n "${DERP_IPV6}" ] && ! check_ipv6 "${DERP_IPV6}"; then
    exiterr "Invalid DERP IPv6 address."
  fi

  if [ -n "${DERP_STUN_PORT}" ] && ! check_port "${DERP_STUN_PORT}"; then
    exiterr "Invalid DERP STUN port."
  fi
}

validate_target_user() {
  sanitize_username "${1}"
  [ -n "${SANITIZED_USERNAME}" ] || exiterr "Invalid user name."
  TARGET_USER="${SANITIZED_USERNAME}"
}

validate_target_node_id() {
  printf '%s' "${1}" | grep -Eq '^[0-9]+$' || exiterr "Node ID must be numeric."
  TARGET_NODE_ID="${1}"
}

validate_hs_root() {
  case "${HS_ROOT}" in
    ''|/|/bin|/boot|/dev|/etc|/home|/lib|/lib64|/media|/mnt|/opt|/proc|/root|/run|/sbin|/srv|/sys|/tmp|/usr|/var)
      exiterr "Refusing unsafe HS_ROOT: ${HS_ROOT}"
      ;;
  esac

  case "${HS_ROOT}" in
    "${PROJECT_ROOT}"|"${RUNTIME_DIR}")
      exiterr "Refusing unsafe HS_ROOT: ${HS_ROOT}"
      ;;
  esac
}

assert_managed_remove_target() {
  validate_hs_root
  [ -f "${HS_INSTANCE_MARKER}" ] ||
    exiterr "Refusing to delete ${HS_ROOT}: missing managed instance marker ${HS_INSTANCE_MARKER}."
}

assert_not_installed() {
  if [ -f "${STATE_FILE}" ] || [ -f "${LEGACY_MARKER}" ]; then
    exiterr "An existing managed install is already recorded. This repo currently manages one active instance at a time; remove the old install state before creating another."
  fi

  if data_dir_has_content; then
    exiterr "The data directory under ${HS_ROOT} is not empty. Refusing to overwrite an existing instance."
  fi
}

assert_installed() {
  load_persisted_state
  validate_hs_root
  require_install_files
}
