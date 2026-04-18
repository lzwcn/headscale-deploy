#!/usr/bin/env bash

do_add_user() {
  log_step "Adding user '${TARGET_USERNAME}'"
  hs_cmd users create "${TARGET_USERNAME}"
}

do_delete_user() {
  if [ "${ASSUME_YES}" -ne 1 ]; then
    read -rp "Delete user '${TARGET_USERNAME}' and all nodes/keys? [y/N]: " confirm
    case "${confirm}" in
      [yY][eE][sS]|[yY]) ;;
      *) exiterr "Aborted." ;;
    esac
  fi
  hs_cmd users delete --name "${TARGET_USERNAME}" --force
}

do_list_users() {
  hs_cmd users list
}

do_list_nodes() {
  if [ -n "${TARGET_USER}" ]; then
    hs_cmd nodes list --user "${TARGET_USER}"
  else
    hs_cmd nodes list
  fi
}

do_register_node() {
  [ -n "${TARGET_USER}" ] || exiterr "--user is required."
  [ -n "${TARGET_NODE_KEY}" ] || exiterr "--key is required."
  hs_cmd nodes register --user "${TARGET_USER}" --key "${TARGET_NODE_KEY}"
}

do_delete_node() {
  [ -n "${TARGET_NODE_ID}" ] || exiterr "Node ID is required."
  if [ "${ASSUME_YES}" -ne 1 ]; then
    read -rp "Delete node ID ${TARGET_NODE_ID}? [y/N]: " confirm
    case "${confirm}" in
      [yY][eE][sS]|[yY]) ;;
      *) exiterr "Aborted." ;;
    esac
  fi
  hs_cmd nodes delete --identifier "${TARGET_NODE_ID}" --force
}

do_create_key() {
  local user_id
  [ -n "${TARGET_USER}" ] || exiterr "--user is required."
  user_id="$(get_user_id "${TARGET_USER}")"
  [ -n "${user_id}" ] || exiterr "User '${TARGET_USER}' not found."
  hs_cmd preauthkeys create --user "${user_id}" --reusable --expiration 90d
}

do_list_keys() {
  hs_cmd preauthkeys list
}

do_create_apikey() {
  if [ -n "${APIKEY_EXPIRATION:-}" ]; then
    hs_cmd apikeys create --expiration "${APIKEY_EXPIRATION}"
  else
    hs_cmd apikeys create
  fi
}

do_list_apikeys() {
  hs_cmd apikeys list
}

do_expire_apikey() {
  [ -n "${APIKEY_PREFIX:-}" ] || exiterr "--prefix is required."
  hs_cmd apikeys expire --prefix "${APIKEY_PREFIX}"
}

run_up_command() {
  assert_installed
  docker_up
  docker_compose ps -a || true
}

run_down_command() {
  assert_installed
  docker_down
}

run_status_command() {
  assert_installed
  local exec_status listen_line region_code_line region_name_line
  local verify_clients_line stun_line derp_ipv4_line derp_ipv6_line

  echo "Headscale deployment status"
  echo "---------------------------"
  echo "root: ${HS_ROOT}"
  echo "compose: ${HS_COMPOSE}"
  echo "config: ${HS_CONF}"
  echo "image: ${HEADSCALE_IMAGE}:${HEADSCALE_TAG}"
  echo "server_url: ${SERVER_URL:-"(computed in config)"}"
  echo "docker_mode: ${DOCKER_MODE}"
  if [ "${DOCKER_MODE}" = "network" ]; then
    echo "docker_network: ${HS_DOCKER_NETWORK}"
  elif [ "${DOCKER_MODE}" = "host" ]; then
    echo "host_network: true"
  else
    echo "published_port: ${PORT}"
  fi
  echo "derp_mode: ${DERP_MODE}"

  if [ -f "${HS_CONF}" ]; then
    listen_line="$(grep -m1 '^listen_addr:' "${HS_CONF}" | sed 's/^[[:space:]]*//')"
    region_code_line="$(grep -m1 '^[[:space:]]*region_code:' "${HS_CONF}" | sed 's/^[[:space:]]*//')"
    region_name_line="$(grep -m1 '^[[:space:]]*region_name:' "${HS_CONF}" | sed 's/^[[:space:]]*//')"
    verify_clients_line="$(grep -m1 '^[[:space:]]*verify_clients:' "${HS_CONF}" | sed 's/^[[:space:]]*//')"
    stun_line="$(grep -m1 '^[[:space:]]*stun_listen_addr:' "${HS_CONF}" | sed 's/^[[:space:]]*//')"
    derp_ipv4_line="$(grep -m1 '^[[:space:]]*ipv4:' "${HS_CONF}" | sed 's/^[[:space:]]*//')"
    derp_ipv6_line="$(grep -m1 '^[[:space:]]*ipv6:' "${HS_CONF}" | sed 's/^[[:space:]]*//')"
    [ -n "${listen_line}" ] && echo "${listen_line}"
    [ -n "${region_code_line}" ] && echo "${region_code_line}"
    [ -n "${region_name_line}" ] && echo "${region_name_line}"
    [ -n "${verify_clients_line}" ] && echo "${verify_clients_line}"
    [ -n "${stun_line}" ] && echo "${stun_line}"
    [ -n "${derp_ipv4_line}" ] && echo "${derp_ipv4_line}"
    [ -n "${derp_ipv6_line}" ] && echo "${derp_ipv6_line}"
  fi

  if docker_compose exec -T "${HS_CONTAINER}" headscale version >/dev/null 2>&1; then
    exec_status="ok"
  else
    exec_status="failed"
  fi
  echo "container_exec: ${exec_status}"
  echo
  echo "Compose containers"
  echo "------------------"
  docker_compose ps -a
}

run_logs_command() {
  assert_installed
  docker_compose logs -f "${HS_CONTAINER}"
}

run_user_command() {
  assert_installed
  check_service_running

  case "${1:-}" in
    add)
      [ -n "${2:-}" ] || exiterr "Usage: hsctl user add NAME"
      sanitize_username "${2}"
      TARGET_USERNAME="${SANITIZED_USERNAME}"
      do_add_user
      ;;
    delete)
      [ -n "${2:-}" ] || exiterr "Usage: hsctl user delete NAME"
      sanitize_username "${2}"
      TARGET_USERNAME="${SANITIZED_USERNAME}"
      do_delete_user
      ;;
    list)
      do_list_users
      ;;
    *)
      exiterr "Usage: hsctl user add NAME | delete NAME | list"
      ;;
  esac
}

run_node_command() {
  assert_installed
  check_service_running

  case "${1:-}" in
    list)
      shift || true
      TARGET_USER=""
      while [ "$#" -gt 0 ]; do
        case "$1" in
          --user)
            validate_target_user "$2"
            shift 2
            ;;
          *)
            exiterr "Unknown node list flag: $1"
            ;;
        esac
      done
      do_list_nodes
      ;;
    register)
      shift || true
      TARGET_USER=""
      TARGET_NODE_KEY=""
      while [ "$#" -gt 0 ]; do
        case "$1" in
          --user)
            validate_target_user "$2"
            shift 2
            ;;
          --key)
            TARGET_NODE_KEY="$2"
            shift 2
            ;;
          *)
            exiterr "Unknown node register flag: $1"
            ;;
        esac
      done
      do_register_node
      ;;
    delete)
      [ -n "${2:-}" ] || exiterr "Usage: hsctl node delete ID"
      validate_target_node_id "${2}"
      do_delete_node
      ;;
    *)
      exiterr "Usage: hsctl node list [--user NAME] | register --user NAME --key NODEKEY | delete ID"
      ;;
  esac
}

run_key_command() {
  assert_installed
  check_service_running

  case "${1:-}" in
    create)
      shift || true
      TARGET_USER=""
      while [ "$#" -gt 0 ]; do
        case "$1" in
          --user)
            validate_target_user "$2"
            shift 2
            ;;
          *)
            exiterr "Unknown key create flag: $1"
            ;;
        esac
      done
      do_create_key
      ;;
    list)
      do_list_keys
      ;;
    *)
      exiterr "Usage: hsctl key create --user NAME | list"
      ;;
  esac
}

run_apikey_command() {
  assert_installed
  check_service_running

  case "${1:-}" in
    create)
      shift || true
      APIKEY_EXPIRATION=""
      while [ "$#" -gt 0 ]; do
        case "$1" in
          --expiration)
            APIKEY_EXPIRATION="$2"
            shift 2
            ;;
          *)
            exiterr "Unknown apikey create flag: $1"
            ;;
        esac
      done
      do_create_apikey
      ;;
    list)
      do_list_apikeys
      ;;
    expire)
      shift || true
      APIKEY_PREFIX=""
      while [ "$#" -gt 0 ]; do
        case "$1" in
          --prefix)
            APIKEY_PREFIX="$2"
            shift 2
            ;;
          *)
            exiterr "Unknown apikey expire flag: $1"
            ;;
        esac
      done
      do_expire_apikey
      ;;
    *)
      exiterr "Usage: hsctl apikey create [--expiration DURATION] | list | expire --prefix PREFIX"
      ;;
  esac
}

run_uninstall_command() {
  bootstrap_runtime_defaults
  load_persisted_state
  assert_installed

  while [ "$#" -gt 0 ]; do
    case "$1" in
      -y|--yes)
        ASSUME_YES=1
        shift
        ;;
      *)
        exiterr "Unknown uninstall flag: $1"
        ;;
    esac
  done

  local remove_stack="n"
  local remove_data="n"

  if [ "${ASSUME_YES}" -eq 1 ]; then
    remove_stack="y"
    remove_data="y"
  else
    read -rp "Remove Headscale stack? [y/N]: " remove_stack
    if [[ ! "${remove_stack}" =~ ^[yY]$ ]]; then
      exiterr "Aborted."
    fi
    read -rp "Delete ${HS_ROOT} (config + database + keys)? [y/N]: " remove_data
  fi

  if [[ "${remove_data}" =~ ^[yY]$ ]]; then
    assert_managed_remove_target
  fi

  docker_down
  clear_state_files

  if [[ "${remove_data}" =~ ^[yY]$ ]]; then
    log_step "Removing ${HS_ROOT}"
    rm -rf "${HS_ROOT}"
  else
    log_detail "Kept ${HS_ROOT}"
  fi

  log_step "Uninstall finished."
}
