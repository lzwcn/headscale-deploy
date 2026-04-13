#!/usr/bin/env bash

parse_compose_image_ref() {
  local line ref

  line="$(grep -E '^[[:space:]]*image:[[:space:]]*' "${HS_COMPOSE}" | head -1 || true)"
  [ -n "${line}" ] || exiterr "No image line in ${HS_COMPOSE}"
  ref="$(printf '%s' "${line}" | sed 's/^[[:space:]]*image:[[:space:]]*//;s/[[:space:]]*$//')"
  [ -n "${ref}" ] || exiterr "Empty image ref in ${HS_COMPOSE}"

  if [[ "${ref}" == *:* ]]; then
    COMPOSE_IMAGE_NAME="${ref%:*}"
    COMPOSE_IMAGE_TAG="${ref##*:}"
  else
    COMPOSE_IMAGE_NAME="${ref}"
    COMPOSE_IMAGE_TAG="latest"
  fi
}

backup_compose_file() {
  local ts
  ts="$(date +%Y%m%d-%H%M%S)"
  cp -a "${HS_COMPOSE}" "${HS_COMPOSE}.bak.${ts}"
}

run_upgrade_command() {
  bootstrap_runtime_defaults
  load_persisted_state
  assert_installed

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --image-tag)
        HEADSCALE_TAG="$2"
        IMAGE_TAG_EXPLICIT=1
        shift 2
        ;;
      --no-backup)
        NO_BACKUP=1
        shift
        ;;
      *)
        exiterr "Unknown upgrade flag: $1"
        ;;
    esac
  done

  parse_compose_image_ref
  HEADSCALE_IMAGE="${COMPOSE_IMAGE_NAME}"
  if [ "${IMAGE_TAG_EXPLICIT}" -ne 1 ]; then
    HEADSCALE_TAG="${COMPOSE_IMAGE_TAG}"
  fi

  if [ "${NO_BACKUP}" -ne 1 ]; then
    local bak
    bak="${HS_DATA_DIR}.bak.$(date +%Y%m%d-%H%M%S)"
    log_step "Backing up data directory -> ${bak}"
    cp -a "${HS_DATA_DIR}" "${bak}"
  fi

  backup_compose_file
  render_compose_template
  docker_pull
  docker_up --force-recreate

  if ! wait_for_headscale; then
    exiterr "Headscale did not become healthy after upgrade."
  fi

  write_state_file
  write_legacy_marker
  docker_compose exec -T "${HS_CONTAINER}" headscale version || true
  log_step "Upgrade finished."
}
