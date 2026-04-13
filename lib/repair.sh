#!/usr/bin/env bash

ensure_sqlite3() {
  if command -v sqlite3 >/dev/null 2>&1; then
    log_detail "sqlite3: $(sqlite3 --version)"
    return 0
  fi

  log_step "Installing sqlite3"
  if [[ "${OS_FAMILY}" == "debian" || "${OS_FAMILY}" == "ubuntu" ]]; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get -yqq update
    apt-get -yqq install sqlite3
  elif [[ "${OS_FAMILY}" == "openSUSE" ]]; then
    zypper install -y sqlite3
  else
    yum -y -q install sqlite sqlite3 2>/dev/null || yum -y -q install sqlite
  fi

  command -v sqlite3 >/dev/null 2>&1 || exiterr "sqlite3 not in PATH after install"
}

run_repair_db_command() {
  local dbf ts confirm

  check_root
  check_shell
  check_os
  check_os_ver
  assert_installed

  dbf="${HS_DATA_DIR}/db.sqlite"
  [ -f "${dbf}" ] || exiterr "Missing ${dbf}"

  if [ "${ASSUME_YES}" -ne 1 ]; then
    read -rp "Stop Headscale, backup db.sqlite, drop legacy table database_versions, then restart? [y/N]: " confirm
    case "${confirm}" in
      [yY][eE][sS]|[yY]) ;;
      *) exiterr "Aborted." ;;
    esac
  fi

  ensure_sqlite3
  ts="$(date +%Y%m%d-%H%M%S)"

  docker_compose stop "${HS_CONTAINER}" || true
  cp -a "${dbf}" "${dbf}.bak.${ts}"
  sqlite3 "${dbf}" "DROP TABLE IF EXISTS database_versions;"
  docker_up

  if ! wait_for_headscale; then
    exiterr "Repair failed. Check logs."
  fi

  log_step "Repair finished."
}

run_repair_command() {
  bootstrap_runtime_defaults
  load_persisted_state

  case "${1:-}" in
    db)
      shift || true
      while [ "$#" -gt 0 ]; do
        case "$1" in
          -y|--yes)
            ASSUME_YES=1
            shift
            ;;
          *)
            exiterr "Unknown repair db flag: $1"
            ;;
        esac
      done
      run_repair_db_command
      ;;
    *)
      exiterr "Usage: hsctl repair db"
      ;;
  esac
}
