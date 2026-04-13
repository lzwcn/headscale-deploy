#!/usr/bin/env bash

show_legacy_usage() {
  cat <<'EOF'
Legacy usage:
  bash headscale-install.sh [--auto] [install flags]
  bash headscale-install.sh --adduser NAME
  bash headscale-install.sh --deleteuser NAME
  bash headscale-install.sh --listusers
  bash headscale-install.sh --listnodes [--user NAME]
  bash headscale-install.sh --registernode KEY --user NAME
  bash headscale-install.sh --deletenode ID
  bash headscale-install.sh --createkey --user NAME
  bash headscale-install.sh --listkeys
  bash headscale-install.sh --createapikey [--expiration DURATION]
  bash headscale-install.sh --listapikeys
  bash headscale-install.sh --expireapikey PREFIX
  bash headscale-install.sh --upgrade [--image-tag TAG] [--no-backup]
  bash headscale-install.sh --fix-db
  bash headscale-install.sh --uninstall
EOF
}

select_menu_option() {
  echo
  echo "1) Add user  2) Delete user  3) List users  4) List nodes"
  echo "5) Register node  6) Delete node  7) Create key  8) List keys"
  echo "9) Uninstall  10) Upgrade image  11) Fix SQLite  12) Exit"
  read -rp "Option: " LEGACY_OPTION
}

legacy_interactive_menu() {
  assert_installed
  select_menu_option

  case "${LEGACY_OPTION}" in
    1)
      check_service_running
      read -rp "User name: " TARGET_USERNAME
      sanitize_username "${TARGET_USERNAME}"
      TARGET_USERNAME="${SANITIZED_USERNAME}"
      do_add_user
      ;;
    2)
      check_service_running
      read -rp "User name: " TARGET_USERNAME
      sanitize_username "${TARGET_USERNAME}"
      TARGET_USERNAME="${SANITIZED_USERNAME}"
      do_delete_user
      ;;
    3)
      check_service_running
      do_list_users
      ;;
    4)
      check_service_running
      TARGET_USER=""
      do_list_nodes
      ;;
    5)
      check_service_running
      read -rp "Username: " TARGET_USER
      read -rp "Node key: " TARGET_NODE_KEY
      do_register_node
      ;;
    6)
      check_service_running
      TARGET_USER=""
      do_list_nodes
      read -rp "Node ID to delete: " TARGET_NODE_ID
      validate_target_node_id "${TARGET_NODE_ID}"
      do_delete_node
      ;;
    7)
      check_service_running
      read -rp "Username: " TARGET_USER
      do_create_key
      ;;
    8)
      check_service_running
      do_list_keys
      ;;
    9)
      run_uninstall_command
      ;;
    10)
      local newtag skipbak
      read -rp "New image tag [Enter=keep current]: " newtag
      if [ -n "${newtag}" ]; then
        run_upgrade_command --image-tag "${newtag}"
      else
        read -rp "Skip data backup before recreate? [y/N]: " skipbak
        if [[ "${skipbak}" =~ ^[yY]$ ]]; then
          run_upgrade_command --no-backup
        else
          run_upgrade_command
        fi
      fi
      ;;
    11)
      run_repair_command db
      ;;
    12)
      exit 0
      ;;
    *)
      exiterr "Invalid option."
      ;;
  esac
}

legacy_main() {
  bootstrap_runtime_defaults
  load_persisted_state

  local install_args=()
  local saw_install_flag=0
  local action=""

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --auto)
        AUTO=1
        saw_install_flag=1
        install_args+=("$1")
        shift
        ;;
      --config)
        [ "$#" -ge 2 ] || exiterr "Missing value for $1"
        load_env_file "$2"
        saw_install_flag=1
        install_args+=("$1" "$2")
        shift 2
        ;;
      --prefix)
        [ "$#" -ge 2 ] || exiterr "Missing value for $1"
        HS_ROOT="$2"
        saw_install_flag=1
        install_args+=("$1" "$2")
        shift 2
        ;;
      --serverurl)
        [ "$#" -ge 2 ] || exiterr "Missing value for $1"
        SERVER_URL="$2"
        saw_install_flag=1
        install_args+=("$1" "$2")
        shift 2
        ;;
      --port)
        [ "$#" -ge 2 ] || exiterr "Missing value for $1"
        PORT="$2"
        saw_install_flag=1
        install_args+=("$1" "$2")
        shift 2
        ;;
      --listenaddr)
        [ "$#" -ge 2 ] || exiterr "Missing value for $1"
        LISTEN_ADDR="$2"
        saw_install_flag=1
        install_args+=("$1" "$2")
        shift 2
        ;;
      --username)
        [ "$#" -ge 2 ] || exiterr "Missing value for $1"
        FIRST_USERNAME="$2"
        saw_install_flag=1
        install_args+=("$1" "$2")
        shift 2
        ;;
      --basedomain)
        [ "$#" -ge 2 ] || exiterr "Missing value for $1"
        BASE_DOMAIN="$2"
        saw_install_flag=1
        install_args+=("$1" "$2")
        shift 2
        ;;
      --image-tag)
        [ "$#" -ge 2 ] || exiterr "Missing value for $1"
        HEADSCALE_TAG="$2"
        IMAGE_TAG_EXPLICIT=1
        saw_install_flag=1
        install_args+=("$1" "$2")
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
        saw_install_flag=1
        install_args+=("$1" "$2")
        shift 2
        ;;
      --container-name)
        [ "$#" -ge 2 ] || exiterr "Missing value for $1"
        HS_CONTAINER="$2"
        saw_install_flag=1
        install_args+=("$1" "$2")
        shift 2
        ;;
      --derp-mode)
        [ "$#" -ge 2 ] || exiterr "Missing value for $1"
        DERP_MODE="$2"
        saw_install_flag=1
        install_args+=("$1" "$2")
        shift 2
        ;;
      --derp-ipv4)
        [ "$#" -ge 2 ] || exiterr "Missing value for $1"
        DERP_IPV4="$2"
        saw_install_flag=1
        install_args+=("$1" "$2")
        shift 2
        ;;
      --derp-ipv6)
        [ "$#" -ge 2 ] || exiterr "Missing value for $1"
        DERP_IPV6="$2"
        saw_install_flag=1
        install_args+=("$1" "$2")
        shift 2
        ;;
      --derp-stun-addr)
        [ "$#" -ge 2 ] || exiterr "Missing value for $1"
        DERP_STUN_LISTEN_ADDR="$2"
        saw_install_flag=1
        install_args+=("$1" "$2")
        shift 2
        ;;
      -y|--yes)
        ASSUME_YES=1
        saw_install_flag=1
        install_args+=("$1")
        shift
        ;;
      --adduser)
        [ "$#" -ge 2 ] || exiterr "Missing value for $1"
        action="user-add"
        TARGET_USERNAME="$2"
        shift 2
        ;;
      --deleteuser)
        [ "$#" -ge 2 ] || exiterr "Missing value for $1"
        action="user-delete"
        TARGET_USERNAME="$2"
        shift 2
        ;;
      --listusers)
        action="user-list"
        shift
        ;;
      --listnodes)
        action="node-list"
        shift
        ;;
      --registernode)
        [ "$#" -ge 2 ] || exiterr "Missing value for $1"
        action="node-register"
        TARGET_NODE_KEY="$2"
        shift 2
        ;;
      --deletenode)
        [ "$#" -ge 2 ] || exiterr "Missing value for $1"
        action="node-delete"
        TARGET_NODE_ID="$2"
        shift 2
        ;;
      --createkey)
        action="key-create"
        shift
        ;;
      --listkeys)
        action="key-list"
        shift
        ;;
      --createapikey)
        action="apikey-create"
        shift
        ;;
      --listapikeys)
        action="apikey-list"
        shift
        ;;
      --expireapikey)
        [ "$#" -ge 2 ] || exiterr "Missing value for $1"
        action="apikey-expire"
        APIKEY_PREFIX="$2"
        shift 2
        ;;
      --expiration)
        [ "$#" -ge 2 ] || exiterr "Missing value for $1"
        APIKEY_EXPIRATION="$2"
        shift 2
        ;;
      --user)
        [ "$#" -ge 2 ] || exiterr "Missing value for $1"
        TARGET_USER="$2"
        shift 2
        ;;
      --uninstall)
        action="uninstall"
        shift
        ;;
      --upgrade|--update)
        action="upgrade"
        shift
        ;;
      --no-backup)
        NO_BACKUP=1
        shift
        ;;
      --fix-db|--fix-db-schema)
        action="repair-db"
        shift
        ;;
      -h|--help)
        show_legacy_usage
        exit 0
        ;;
      *)
        exiterr "Unknown parameter: $1"
        ;;
    esac
  done

  if [ -z "${action}" ] && [ "${#install_args[@]}" -eq 0 ]; then
    if has_install_files; then
      legacy_interactive_menu
    else
      run_install_command
    fi
    return 0
  fi

  case "${action}" in
    "")
      run_install_command "${install_args[@]}"
      ;;
    user-add)
      sanitize_username "${TARGET_USERNAME}"
      run_user_command add "${SANITIZED_USERNAME}"
      ;;
    user-delete)
      sanitize_username "${TARGET_USERNAME}"
      run_user_command delete "${SANITIZED_USERNAME}"
      ;;
    user-list)
      run_user_command list
      ;;
    node-list)
      if [ -n "${TARGET_USER}" ]; then
        sanitize_username "${TARGET_USER}"
        run_node_command list --user "${SANITIZED_USERNAME}"
      else
        run_node_command list
      fi
      ;;
    node-register)
      [ -n "${TARGET_USER}" ] || exiterr "--registernode requires --user NAME."
      sanitize_username "${TARGET_USER}"
      run_node_command register --user "${SANITIZED_USERNAME}" --key "${TARGET_NODE_KEY}"
      ;;
    node-delete)
      run_node_command delete "${TARGET_NODE_ID}"
      ;;
    key-create)
      [ -n "${TARGET_USER}" ] || exiterr "--createkey requires --user NAME."
      sanitize_username "${TARGET_USER}"
      run_key_command create --user "${SANITIZED_USERNAME}"
      ;;
    key-list)
      run_key_command list
      ;;
    apikey-create)
      if [ -n "${APIKEY_EXPIRATION:-}" ]; then
        run_apikey_command create --expiration "${APIKEY_EXPIRATION}"
      else
        run_apikey_command create
      fi
      ;;
    apikey-list)
      run_apikey_command list
      ;;
    apikey-expire)
      run_apikey_command expire --prefix "${APIKEY_PREFIX}"
      ;;
    uninstall)
      if [ "${ASSUME_YES}" -eq 1 ]; then
        run_uninstall_command --yes
      else
        run_uninstall_command
      fi
      ;;
    upgrade)
      if [ "${IMAGE_TAG_EXPLICIT}" -eq 1 ] && [ "${NO_BACKUP}" -eq 1 ]; then
        run_upgrade_command --image-tag "${HEADSCALE_TAG}" --no-backup
      elif [ "${IMAGE_TAG_EXPLICIT}" -eq 1 ]; then
        run_upgrade_command --image-tag "${HEADSCALE_TAG}"
      elif [ "${NO_BACKUP}" -eq 1 ]; then
        run_upgrade_command --no-backup
      else
        run_upgrade_command
      fi
      ;;
    repair-db)
      if [ "${ASSUME_YES}" -eq 1 ]; then
        run_repair_command db --yes
      else
        run_repair_command db
      fi
      ;;
    *)
      exiterr "Unsupported legacy action: ${action}"
      ;;
  esac
}
