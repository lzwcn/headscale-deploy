#!/usr/bin/env bash

parse_common_install_flags() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --auto)
        AUTO=1
        shift
        ;;
      --config)
        [ "$#" -ge 2 ] || exiterr "Missing value for $1"
        load_env_file "$2"
        shift 2
        ;;
      --prefix)
        [ "$#" -ge 2 ] || exiterr "Missing value for $1"
        HS_ROOT="$2"
        shift 2
        ;;
      --serverurl)
        [ "$#" -ge 2 ] || exiterr "Missing value for $1"
        SERVER_URL="$2"
        shift 2
        ;;
      --port)
        [ "$#" -ge 2 ] || exiterr "Missing value for $1"
        PORT="$2"
        shift 2
        ;;
      --listenaddr)
        [ "$#" -ge 2 ] || exiterr "Missing value for $1"
        LISTEN_ADDR="$2"
        shift 2
        ;;
      --username)
        [ "$#" -ge 2 ] || exiterr "Missing value for $1"
        FIRST_USERNAME="$2"
        shift 2
        ;;
      --basedomain)
        [ "$#" -ge 2 ] || exiterr "Missing value for $1"
        BASE_DOMAIN="$2"
        shift 2
        ;;
      --image-tag)
        [ "$#" -ge 2 ] || exiterr "Missing value for $1"
        HEADSCALE_TAG="$2"
        shift 2
        ;;
      --docker-mode)
        [ "$#" -ge 2 ] || exiterr "Missing value for $1"
        case "$2" in
          network)
            DOCKER_MODE="network"
            ;;
          portmap|none)
            DOCKER_MODE="portmap"
            HS_DOCKER_NETWORK=""
            ;;
          host)
            DOCKER_MODE="host"
            HS_DOCKER_NETWORK=""
            ;;
          *)
            exiterr "Invalid docker mode: $2"
            ;;
        esac
        shift 2
        ;;
      --docker-network)
        [ "$#" -ge 2 ] || exiterr "Missing value for $1"
        if [ "$2" = "none" ] || [ "$2" = "-" ]; then
          DOCKER_MODE="portmap"
          HS_DOCKER_NETWORK=""
        else
          DOCKER_MODE="network"
          HS_DOCKER_NETWORK="$2"
        fi
        shift 2
        ;;
      --container-name)
        [ "$#" -ge 2 ] || exiterr "Missing value for $1"
        HS_CONTAINER="$2"
        shift 2
        ;;
      --derp-mode)
        [ "$#" -ge 2 ] || exiterr "Missing value for $1"
        DERP_MODE="$2"
        shift 2
        ;;
      --derp-ipv4)
        [ "$#" -ge 2 ] || exiterr "Missing value for $1"
        DERP_IPV4="$2"
        shift 2
        ;;
      --derp-ipv6)
        [ "$#" -ge 2 ] || exiterr "Missing value for $1"
        DERP_IPV6="$2"
        shift 2
        ;;
      --derp-stun-addr)
        [ "$#" -ge 2 ] || exiterr "Missing value for $1"
        DERP_STUN_LISTEN_ADDR="$2"
        shift 2
        ;;
      -y|--yes)
        ASSUME_YES=1
        shift
        ;;
      -h|--help)
        show_help
        exit 0
        ;;
      *)
        exiterr "Unknown install flag: $1"
        ;;
    esac
  done
}

install_bind_addr() {
  format_host_port "${LISTEN_ADDR}" 8080
}

prompt_with_default() {
  local prompt="$1"
  local current="$2"
  local answer=""

  if [ -n "${current}" ]; then
    read -rp "${prompt} [${current}]: " answer
    printf '%s' "${answer:-${current}}"
  else
    read -rp "${prompt}: " answer
    printf '%s' "${answer}"
  fi
}

require_interactive_server_url_for_derp() {
  if [ -z "${SERVER_URL}" ]; then
    exiterr "Embedded DERP requires an explicit HTTPS SERVER_URL. Please enter https://<your-headscale-domain> during interactive install."
  fi

  if ! printf '%s' "${SERVER_URL}" | grep -q '^https://'; then
    exiterr "Embedded DERP requires SERVER_URL to start with https:// during interactive install."
  fi
}

collect_interactive_install_settings() {
  echo
  log_step "Interactive install"

  HS_ROOT="$(prompt_with_default 'Install root' "${HS_ROOT}")"
  apply_hs_paths

  local mode_default mode_input
  mode_default="${DOCKER_MODE}"
  mode_input="$(prompt_with_default 'Docker mode (network/portmap/host)' "${mode_default}")"
  case "${mode_input}" in
    network) DOCKER_MODE="network" ;;
    portmap|none) DOCKER_MODE="portmap" ;;
    host) DOCKER_MODE="host" ;;
    *) exiterr "Invalid Docker mode: ${mode_input}" ;;
  esac

  if [ "${DOCKER_MODE}" = "network" ]; then
    SERVER_URL="$(prompt_with_default 'Server URL (required, format: https://<your-headscale-domain>)' "${SERVER_URL}")"
    HS_DOCKER_NETWORK="$(prompt_with_default 'External Docker network' "${HS_DOCKER_NETWORK}")"
  elif [ "${DOCKER_MODE}" = "host" ]; then
    SERVER_URL="$(prompt_with_default 'Server URL (blank = auto-detect http://IP:8080; required for DERP/HTTPS setups)' "${SERVER_URL}")"
  else
    SERVER_URL="$(prompt_with_default 'Server URL (blank = auto-detect http://IP:PORT)' "${SERVER_URL}")"
    PORT="$(prompt_with_default 'Host TCP port' "${PORT}")"
  fi

  LISTEN_ADDR="$(prompt_with_default 'Listen address (IPv4 or IPv6 literal; :: means dual-stack if supported)' "${LISTEN_ADDR}")"
  FIRST_USERNAME="$(prompt_with_default 'Initial user name' "${FIRST_USERNAME}")"
  BASE_DOMAIN="$(prompt_with_default 'MagicDNS base domain' "${BASE_DOMAIN}")"
  HEADSCALE_TAG="$(prompt_with_default 'Image tag' "${HEADSCALE_TAG}")"
  HS_CONTAINER="$(prompt_with_default 'Container name' "${HS_CONTAINER}")"
  DERP_MODE="$(prompt_with_default 'DERP mode (disabled/private/public)' "${DERP_MODE}")"
  if [ "${DERP_MODE}" != "disabled" ]; then
    require_interactive_server_url_for_derp
    DERP_IPV4="$(prompt_with_default 'DERP public IPv4 (optional but recommended)' "${DERP_IPV4}")"
    DERP_IPV6="$(prompt_with_default 'DERP public IPv6 (optional)' "${DERP_IPV6}")"
    DERP_STUN_LISTEN_ADDR="$(prompt_with_default 'DERP STUN listen addr' "${DERP_STUN_LISTEN_ADDR}")"
  fi
  normalize_network_mode
  normalize_derp_mode
}

compute_server_url() {
  if [ -n "${SERVER_URL}" ]; then
    COMPUTED_SERVER_URL="${SERVER_URL%/}"
    return 0
  fi

  if [ "${DOCKER_MODE}" = "network" ]; then
    exiterr "--serverurl is required when DOCKER_MODE=network."
  fi

  detect_ip
  check_nat_ip
  if [ "${DOCKER_MODE}" = "host" ]; then
    COMPUTED_SERVER_URL="http://${PUBLIC_IP_ADDR:-${IP_ADDR}}:8080"
  else
    COMPUTED_SERVER_URL="http://${PUBLIC_IP_ADDR:-${IP_ADDR}}:${PORT}"
  fi
}

show_install_summary() {
  echo
  log_detail "HS_ROOT=${HS_ROOT}"
  log_detail "Image=${HEADSCALE_IMAGE}:${HEADSCALE_TAG}"
  log_detail "Container=${HS_CONTAINER}"
  log_detail "server_url=${COMPUTED_SERVER_URL}"
  log_detail "listen_addr=$(install_bind_addr)"
  log_detail "user=${FIRST_USERNAME} base_domain=${BASE_DOMAIN}"
  log_detail "derp_mode=${DERP_MODE}"
  if [ "${DOCKER_MODE}" = "network" ]; then
    log_detail "docker_mode=network external_network=${HS_DOCKER_NETWORK}"
  elif [ "${DOCKER_MODE}" = "host" ]; then
    log_detail "docker_mode=host bind=$(install_bind_addr)"
  else
    log_detail "docker_mode=portmap publish=${PORT}:8080"
  fi
}

confirm_setup() {
  if [ "${AUTO}" -eq 1 ] || [ "${ASSUME_YES}" -eq 1 ]; then
    return 0
  fi

  printf 'Continue? [Y/n] '
  read -r response
  case "${response}" in
    [yY][eE][sS]|[yY]|'') ;;
    *) exiterr "Aborted." ;;
  esac
}

create_initial_user() {
  local create_output

  log_step "Creating user '${FIRST_USERNAME}'"
  create_output="$(hs_cmd --force -o json users create "${FIRST_USERNAME}")"
  printf '%s\n' "${create_output}"

  INITIAL_USER_ID="$(
    printf '%s' "${create_output}" | tr -d ' \n\t' |
      grep -o '"id":[0-9]*' | head -1 | cut -d: -f2
  )"
  if [ -z "${INITIAL_USER_ID}" ]; then
    INITIAL_USER_ID="$(get_user_id "${FIRST_USERNAME}")"
  fi
  [ -n "${INITIAL_USER_ID}" ] || exiterr "User '${FIRST_USERNAME}' was not created successfully."
}

create_initial_key() {
  local user_id="${INITIAL_USER_ID:-}"
  [ -n "${user_id}" ] || user_id="$(get_user_id "${FIRST_USERNAME}")"

  echo
  echo "=================================================================="
  echo " Initial pre-auth key (user: ${FIRST_USERNAME}, reusable, ~90 days)"
  echo "=================================================================="
  [ -n "${user_id}" ] || exiterr "Could not resolve user id for '${FIRST_USERNAME}'."
  hs_cmd --force preauthkeys create --user "${user_id}" --reusable --expiration 90d
  echo "=================================================================="
}

finish_setup() {
  echo
  log_step "Done."
  log_detail "Directory: ${HS_ROOT}"
  log_detail "Compose: ${HS_COMPOSE}"
  log_detail "Config: ${HS_CONF}"
  log_detail "server_url: ${COMPUTED_SERVER_URL}"
  if [ "${DOCKER_MODE}" = "network" ]; then
    log_detail "Docker network: ${HS_DOCKER_NETWORK}"
  elif [ "${DOCKER_MODE}" = "host" ]; then
    log_detail "Host bind: $(install_bind_addr)"
  else
    log_detail "Published: host TCP ${PORT} -> container 8080"
  fi
  echo
  echo "Client:"
  echo "  tailscale up --login-server ${COMPUTED_SERVER_URL} --authkey <key>"
  if [ "${DERP_MODE}" != "disabled" ]; then
    echo "  tailscale netcheck"
  fi
  echo
  echo "CLI on host:"
  echo "  docker compose -f ${HS_COMPOSE} exec ${HS_CONTAINER} headscale users list"
  echo
  echo "Recommended checks on the server:"
  echo "  bash bin/hsctl status"
  if [ "${DERP_MODE}" != "disabled" ]; then
    echo "  docker compose -f ${HS_COMPOSE} logs --tail=100 ${HS_CONTAINER}"
    echo "  ss -lunp | grep ${DERP_STUN_PORT}"
    if [ -n "${DERP_IPV6}" ]; then
      echo "  tcpdump -ni any udp port ${DERP_STUN_PORT}"
    fi
  fi
}

run_install_pipeline() {
  check_root
  check_shell
  check_os
  check_os_ver
  check_docker
  install_curl_or_wget

  normalize_network_mode
  apply_hs_paths
  assert_not_installed

  if [ "${AUTO}" -eq 0 ]; then
    show_header
    collect_interactive_install_settings
  fi

  validate_install_settings
  compute_server_url
  show_install_summary
  confirm_setup

  render_install_artifacts
  ensure_docker_network
  docker_pull
  docker_up

  if ! wait_for_headscale; then
    exiterr "Headscale did not become ready in time."
  fi

  create_initial_user
  create_initial_key
  write_instance_marker
  write_state_file
  write_legacy_marker
  finish_setup
}

run_install_command() {
  bootstrap_runtime_defaults
  load_persisted_state
  parse_common_install_flags "$@"
  run_install_pipeline
}

run_render_command() {
  bootstrap_runtime_defaults
  load_persisted_state
  parse_common_install_flags "$@"
  normalize_network_mode

  if [ "${AUTO}" -eq 0 ]; then
    collect_interactive_install_settings
  fi

  validate_install_settings
  compute_server_url
  show_install_summary
  confirm_setup
  render_install_artifacts
  log_step "Render completed."
}
