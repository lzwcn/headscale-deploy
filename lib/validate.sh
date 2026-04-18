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
  ! check_ip_or_ipv6 "${LISTEN_ADDR}" && exiterr "Invalid listen address."
  ! check_dns_name "${BASE_DOMAIN}" && exiterr "Invalid base domain."

  sanitize_username "${FIRST_USERNAME}"
  [ -n "${SANITIZED_USERNAME}" ] || exiterr "Invalid initial user name."
  FIRST_USERNAME="${SANITIZED_USERNAME}"

  if [ "${DOCKER_MODE}" = "network" ] && [ -z "${SERVER_URL}" ]; then
    exiterr "--serverurl is required when using an external Docker network."
  fi

  if [ -n "${DERP_IPV4}" ] && ! check_ip "${DERP_IPV4}"; then
    exiterr "Invalid DERP IPv4 address."
  fi

  if [ -n "${DERP_IPV6}" ] && ! check_ipv6 "${DERP_IPV6}"; then
    exiterr "Invalid DERP IPv6 address."
  fi

  if ! DERP_STUN_PORT="$(extract_socket_port "${DERP_STUN_LISTEN_ADDR}")"; then
    exiterr "Invalid DERP STUN listen address."
  fi

  if [ "${DOCKER_MODE}" = "host" ] && [ "${PORT}" != "8080" ]; then
    warnmsg "PORT is ignored when DOCKER_MODE=host; Headscale still binds $(format_host_port "${LISTEN_ADDR}" 8080) on the host."
  fi

  if [ "${DERP_MODE}" != "disabled" ]; then
    [ -n "${SERVER_URL}" ] || exiterr "Embedded DERP requires an explicit HTTPS SERVER_URL."
    if ! printf '%s' "${SERVER_URL}" | grep -q '^https://'; then
      exiterr "DERP requires an HTTPS server_url."
    fi

    if [ -z "${DERP_IPV4}" ]; then
      warnmsg "Embedded DERP is enabled without DERP_IPV4. Publish the public IPv4 explicitly when possible."
    fi

    if [ -z "${DERP_IPV6}" ]; then
      warnmsg "DERP_IPV6 is empty. Embedded DERP will not advertise a public IPv6 address."
    fi

    if [ "${DERP_INCLUDE_DEFAULTS}" = "false" ]; then
      warnmsg "DERP_INCLUDE_DEFAULTS=false removes the upstream DERP fallback map."
    fi

    if [ -n "${DERP_IPV6}" ]; then
      case "${DERP_STUN_LISTEN_ADDR}" in
        ":${DERP_STUN_PORT}"|"[::]:${DERP_STUN_PORT}") ;;
        *)
          warnmsg "DERP IPv6 works best with DERP_STUN_LISTEN_ADDR=:${DERP_STUN_PORT} (or [::]:${DERP_STUN_PORT}) for dual-stack STUN."
          ;;
      esac
    fi

    case "${DOCKER_MODE}" in
      network)
        warnmsg "DOCKER_MODE=network still publishes udp/${DERP_STUN_PORT} through Docker. HTTPS success does not prove STUN is healthy."
        if [ -n "${DERP_IPV6}" ]; then
          warnmsg "Embedded DERP with IPv6 may fail behind Docker bridge networking. Prefer DOCKER_MODE=host."
        fi
        ;;
      portmap)
        warnmsg "DOCKER_MODE=portmap publishes udp/${DERP_STUN_PORT} through Docker. If clients need Embedded DERP IPv6, prefer DOCKER_MODE=host."
        ;;
    esac
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
