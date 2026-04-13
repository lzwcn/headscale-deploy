#!/usr/bin/env bash

render_template_file() {
  local template_file="$1"
  local dest_file="$2"
  shift 2

  local key value content

  content="$(cat "${template_file}")"

  while [ "$#" -gt 0 ]; do
    key="$1"
    value="$2"
    content="${content//__${key}__/${value}}"
    shift 2
  done

  printf '%s\n' "${content}" >"${dest_file}"
}

create_directories() {
  log_step "Creating directories under ${HS_ROOT}"
  mkdir -p "${RUNTIME_DIR}" "${HS_CONF_DIR}" "${HS_DATA_DIR}"
  safe_chmod 750 "${HS_CONF_DIR}" "${HS_DATA_DIR}"
}

render_config_template() {
  local derp_enabled derp_verify_clients derp_urls_block derp_ipv4 derp_ipv6

  case "${DERP_MODE}" in
    disabled)
      derp_enabled="false"
      derp_verify_clients="true"
      ;;
    private)
      derp_enabled="true"
      derp_verify_clients="true"
      ;;
    public)
      derp_enabled="true"
      derp_verify_clients="false"
      ;;
  esac

  if [ "${DERP_INCLUDE_DEFAULTS}" = "false" ]; then
    derp_urls_block="[]"
  else
    derp_urls_block=$'- https://controlplane.tailscale.com/derpmap/default'
  fi

  derp_ipv4="${DERP_IPV4:-\"\"}"
  derp_ipv6="${DERP_IPV6:-\"\"}"

  log_step "Rendering ${HS_CONF}"
  render_template_file \
    "${TEMPLATE_DIR}/config.yaml.tpl" "${HS_CONF}" \
    SERVER_URL "${COMPUTED_SERVER_URL}" \
    LISTEN_ADDR "${LISTEN_ADDR}" \
    BASE_DOMAIN "${BASE_DOMAIN}" \
    OFFICIAL_GIT "${OFFICIAL_GIT}" \
    DERP_ENABLED "${derp_enabled}" \
    DERP_REGION_ID "${DERP_REGION_ID}" \
    DERP_REGION_CODE "${DERP_REGION_CODE}" \
    DERP_REGION_NAME "${DERP_REGION_NAME}" \
    DERP_VERIFY_CLIENTS "${derp_verify_clients}" \
    DERP_STUN_LISTEN_ADDR "${DERP_STUN_LISTEN_ADDR}" \
    DERP_IPV4 "${derp_ipv4}" \
    DERP_IPV6 "${derp_ipv6}" \
    DERP_URLS_BLOCK "${derp_urls_block}" \
    DERP_AUTO_ADD_EMBEDDED_REGION "${DERP_AUTO_ADD_EMBEDDED_REGION}"
  safe_chmod 640 "${HS_CONF}"
}

render_compose_template() {
  local optional_ports_block=""

  if [ "${DERP_MODE}" != "disabled" ]; then
    optional_ports_block=$'    ports:\n      - "__DERP_STUN_PORT__:__DERP_STUN_PORT__/udp"'
  fi

  log_step "Rendering ${HS_COMPOSE}"
  if [ "${DOCKER_MODE}" = "network" ]; then
    render_template_file \
      "${TEMPLATE_DIR}/compose.network.yaml.tpl" "${HS_COMPOSE}" \
      HEADSCALE_IMAGE "${HEADSCALE_IMAGE}" \
      HEADSCALE_TAG "${HEADSCALE_TAG}" \
      HS_CONTAINER "${HS_CONTAINER}" \
      HS_CONF_DIR "${HS_CONF_DIR}" \
      HS_DATA_DIR "${HS_DATA_DIR}" \
      HS_DOCKER_NETWORK "${HS_DOCKER_NETWORK}" \
      OPTIONAL_PORTS_BLOCK "${optional_ports_block}" \
      DERP_STUN_PORT "${DERP_STUN_PORT}" \
      OFFICIAL_GIT "${OFFICIAL_GIT}"
  else
    render_template_file \
      "${TEMPLATE_DIR}/compose.portmap.yaml.tpl" "${HS_COMPOSE}" \
      HEADSCALE_IMAGE "${HEADSCALE_IMAGE}" \
      HEADSCALE_TAG "${HEADSCALE_TAG}" \
      HS_CONTAINER "${HS_CONTAINER}" \
      HS_CONF_DIR "${HS_CONF_DIR}" \
      HS_DATA_DIR "${HS_DATA_DIR}" \
      PORT "${PORT}" \
      OPTIONAL_DERP_PORT_LINE "${optional_ports_block:+      - \"${DERP_STUN_PORT}:${DERP_STUN_PORT}/udp\"}" \
      OFFICIAL_GIT "${OFFICIAL_GIT}"
  fi
  # Remove blank lines left by empty optional placeholders
  sed -i '/^[[:space:]]*$/d' "${HS_COMPOSE}"
  safe_chmod 644 "${HS_COMPOSE}"
}

render_install_artifacts() {
  create_directories
  render_config_template
  render_compose_template
}

ensure_docker_network() {
  [ "${DOCKER_MODE}" = "network" ] || return 0
  log_step "Checking external Docker network: ${HS_DOCKER_NETWORK}"
  docker network inspect "${HS_DOCKER_NETWORK}" >/dev/null 2>&1 ||
    exiterr "Docker network '${HS_DOCKER_NETWORK}' not found."
}
