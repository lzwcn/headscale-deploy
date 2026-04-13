#!/usr/bin/env bash

parse_common_install_flags() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --auto)
        AUTO=1
        shift
        ;;
      --config)
        load_env_file "$2"
        shift 2
        ;;
      --prefix)
        HS_ROOT="$2"
        shift 2
        ;;
      --serverurl)
        SERVER_URL="$2"
        shift 2
        ;;
      --port)
        PORT="$2"
        shift 2
        ;;
      --listenaddr)
        LISTEN_ADDR="$2"
        shift 2
        ;;
      --username)
        FIRST_USERNAME="$2"
        shift 2
        ;;
      --basedomain)
        BASE_DOMAIN="$2"
        shift 2
        ;;
      --image-tag)
        HEADSCALE_TAG="$2"
        IMAGE_TAG_EXPLICIT=1
        shift 2
        ;;
      --docker-network)
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
        HS_CONTAINER="$2"
        shift 2
        ;;
      --derp-mode)
        DERP_MODE="$2"
        shift 2
        ;;
      --derp-ipv4)
        DERP_IPV4="$2"
        shift 2
        ;;
      --derp-ipv6)
        DERP_IPV6="$2"
        shift 2
        ;;
      --derp-stun-addr)
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

collect_interactive_install_settings() {
  echo
  log_step "Interactive install"

  HS_ROOT="$(prompt_with_default 'Install root' "${HS_ROOT}")"
  apply_hs_paths

  local mode_default mode_input
  if [ "${DOCKER_MODE}" = "network" ]; then
    mode_default="network"
  else
    mode_default="portmap"
  fi
  mode_input="$(prompt_with_default 'Docker mode (network/portmap)' "${mode_default}")"
  case "${mode_input}" in
    network) DOCKER_MODE="network" ;;
    portmap|none) DOCKER_MODE="portmap" ;;
    *) exiterr "Invalid Docker mode: ${mode_input}" ;;
  esac

  if [ "${DOCKER_MODE}" = "network" ]; then
    SERVER_URL="$(prompt_with_default 'Server URL (required, format: https://<your-headscale-domain>)' "${SERVER_URL}")"
    HS_DOCKER_NETWORK="$(prompt_with_default 'External Docker network' "${HS_DOCKER_NETWORK}")"
  else
    SERVER_URL="$(prompt_with_default 'Server URL (blank = auto-detect http://IP:PORT)' "${SERVER_URL}")"
    PORT="$(prompt_with_default 'Host TCP port' "${PORT}")"
  fi

  LISTEN_ADDR="$(prompt_with_default 'Listen address' "${LISTEN_ADDR}")"
  FIRST_USERNAME="$(prompt_with_default 'Initial user name' "${FIRST_USERNAME}")"
  BASE_DOMAIN="$(prompt_with_default 'MagicDNS base domain' "${BASE_DOMAIN}")"
  HEADSCALE_TAG="$(prompt_with_default 'Image tag' "${HEADSCALE_TAG}")"
  HS_CONTAINER="$(prompt_with_default 'Container name' "${HS_CONTAINER}")"
  DERP_MODE="$(prompt_with_default 'DERP mode (disabled/private/public)' "${DERP_MODE}")"
  if [ "${DERP_MODE}" != "disabled" ]; then
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
  COMPUTED_SERVER_URL="http://${PUBLIC_IP_ADDR:-${IP_ADDR}}:${PORT}"
}

show_install_summary() {
  echo
  log_detail "HS_ROOT=${HS_ROOT}"
  log_detail "Image=${HEADSCALE_IMAGE}:${HEADSCALE_TAG}"
  log_detail "Container=${HS_CONTAINER}"
  log_detail "server_url=${COMPUTED_SERVER_URL}"
  log_detail "listen_addr=${LISTEN_ADDR}:8080"
  log_detail "user=${FIRST_USERNAME} base_domain=${BASE_DOMAIN}"
  log_detail "derp_mode=${DERP_MODE}"
  if [ "${DOCKER_MODE}" = "network" ]; then
    log_detail "docker_mode=network external_network=${HS_DOCKER_NETWORK}"
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
  else
    log_detail "Published: host TCP ${PORT} -> container 8080"
  fi
  echo
  echo "Client:"
  echo "  tailscale up --login-server ${COMPUTED_SERVER_URL} --authkey <key>"
  echo
  echo "CLI on host:"
  echo "  docker compose -f ${HS_COMPOSE} exec ${HS_CONTAINER} headscale users list"
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
