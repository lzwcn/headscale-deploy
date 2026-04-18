#!/usr/bin/env bash

log_ts() {
  date '+%Y-%m-%d %H:%M:%S'
}

log_raw() {
  printf '[%s] %s\n' "$(log_ts)" "$*"
}

log_step() {
  log_raw "==> $*"
}

log_detail() {
  log_raw "    $*"
}

warnmsg() {
  log_raw "WARN: $*"
}

log_cmd() {
  log_raw "+ $*"
}

exiterr() {
  log_raw "ERROR: $1"
  exit 1
}

run_cmd() {
  log_cmd "$*"
  "$@" || exiterr "Command failed: $*"
}

safe_chmod() {
  chmod "$@" 2>/dev/null || true
}

check_ip() {
  local ip_regex='^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$'
  printf '%s' "$1" | tr -d '\n' | grep -Eq "${ip_regex}"
}

check_ipv6() {
  local ipv6_regex='^([0-9a-fA-F]{0,4}:){2,7}[0-9a-fA-F]{0,4}$'
  printf '%s' "$1" | tr -d '\n' | grep -Eq "${ipv6_regex}"
}

check_pvt_ip() {
  local pvt_regex='^(10|127|172\.(1[6-9]|2[0-9]|3[0-1])|192\.168|169\.254)\.'
  printf '%s' "$1" | tr -d '\n' | grep -Eq "${pvt_regex}"
}

check_dns_name() {
  local fqdn_regex='^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$'
  printf '%s' "$1" | tr -d '\n' | grep -Eq "${fqdn_regex}"
}

check_url() {
  printf '%s' "$1" | tr -d '\n' | grep -Eq '^https?://[^[:space:]]+$'
}

check_port() {
  printf '%s' "$1" | tr -d '\n' | grep -Eq '^[0-9]+$' &&
    [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}

normalize_ip_literal() {
  local addr="$1"

  if [[ "${addr}" =~ ^\[(.*)\]$ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
    return 0
  fi

  printf '%s' "${addr}"
}

check_ip_or_ipv6() {
  local addr
  addr="$(normalize_ip_literal "$1")"
  check_ip "${addr}" || check_ipv6 "${addr}"
}

format_host_port() {
  local host="$1"
  local port="$2"
  local normalized_host

  normalized_host="$(normalize_ip_literal "${host}")"
  if check_ipv6 "${normalized_host}"; then
    printf '[%s]:%s' "${normalized_host}" "${port}"
  else
    printf '%s:%s' "${normalized_host}" "${port}"
  fi
}

extract_socket_port() {
  local addr="$1"
  local host=""
  local port=""

  case "${addr}" in
    :*)
      port="${addr#:}"
      ;;
    \[*\]:*)
      host="${addr%%]:*}"
      host="${host#[}"
      port="${addr##*:}"
      check_ipv6 "${host}" || return 1
      ;;
    *:*)
      host="${addr%:*}"
      port="${addr##*:}"
      check_ip "${host}" || return 1
      ;;
    *)
      return 1
      ;;
  esac

  check_port "${port}" || return 1
  printf '%s' "${port}"
}

sanitize_username() {
  # shellcheck disable=SC2034
  SANITIZED_USERNAME="${1//[^0-9a-zA-Z_-]/_}"
}

trim_whitespace() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "${value}"
}

decode_env_double_quoted() {
  local input="$1"
  local output=""
  local i=0
  local ch next

  while [ "${i}" -lt "${#input}" ]; do
    ch="${input:${i}:1}"
    if [ "${ch}" = "\\" ] && [ $((i + 1)) -lt "${#input}" ]; then
      next="${input:$((i + 1)):1}"
      case "${next}" in
        n) output+=$'\n' ;;
        r) output+=$'\r' ;;
        t) output+=$'\t' ;;
        '"') output+='"' ;;
        "\\") output+="\\" ;;
        '$') output+='$' ;;
        '`') output+='`' ;;
        *) output+="\\${next}" ;;
      esac
      i=$((i + 2))
      continue
    fi
    output+="${ch}"
    i=$((i + 1))
  done

  printf '%s' "${output}"
}

env_quote_value() {
  local value="$1"

  case "${value}" in
    *$'\n'*|*$'\r'*)
      exiterr "Refusing to persist multiline value."
      ;;
  esac

  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//\$/\\$}"
  value="${value//\`/\\\`}"
  value="${value//$'\t'/\\t}"

  printf '"%s"' "${value}"
}

load_env_file() {
  local file="$1"
  local line line_no=0 trimmed key raw value inner

  [ -f "${file}" ] || exiterr "Missing env file: ${file}"

  while IFS= read -r line || [ -n "${line}" ]; do
    line_no=$((line_no + 1))
    trimmed="$(trim_whitespace "${line}")"

    case "${trimmed}" in
      ''|'#'*) continue ;;
    esac

    if [[ "${trimmed}" =~ ^export[[:space:]]+ ]]; then
      trimmed="${trimmed#export}"
      trimmed="$(trim_whitespace "${trimmed}")"
    fi

    if ! [[ "${trimmed}" =~ ^([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=(.*)$ ]]; then
      exiterr "Invalid env assignment in ${file}:${line_no}"
    fi

    key="${BASH_REMATCH[1]}"
    raw="$(trim_whitespace "${BASH_REMATCH[2]}")"

    if [ -z "${raw}" ]; then
      value=""
    elif [[ "${raw}" == \"*\" ]]; then
      if [ "${#raw}" -lt 2 ] || [ "${raw: -1}" != '"' ]; then
        exiterr "Unterminated double-quoted value in ${file}:${line_no}"
      fi
      inner="${raw:1:${#raw}-2}"
      value="$(decode_env_double_quoted "${inner}")"
    elif [[ "${raw}" == \'*\' ]]; then
      if [ "${#raw}" -lt 2 ] || [ "${raw: -1}" != "'" ]; then
        exiterr "Unterminated single-quoted value in ${file}:${line_no}"
      fi
      value="${raw:1:${#raw}-2}"
    else
      case "${raw}" in
        *[[:space:]]*|*'$'*|*'`'*|*'"'*|*"'"*|*'('*|*')'*|*'{'*|*'}'*|*';'*|*'|'*|*'&'*|*'<'*|*'>'*)
          exiterr "Unsupported unquoted value in ${file}:${line_no}. Quote the value explicitly."
          ;;
      esac
      value="${raw}"
    fi

    declare -gx "${key}=${value}"
  done <"${file}"
}

check_root() {
  [ "$(id -u)" = 0 ] || exiterr "This command must be run as root."
}

check_shell() {
  if readlink /proc/$$/exe 2>/dev/null | grep -q 'dash'; then
    exiterr 'This command needs to run with "bash", not "sh".'
  fi
}

check_os() {
  if grep -qs "ubuntu" /etc/os-release; then
    OS_FAMILY="ubuntu"
    OS_VERSION="$(grep 'VERSION_ID' /etc/os-release | cut -d '"' -f 2 | tr -d '.')"
    if [[ -z "${OS_VERSION}" || ! "${OS_VERSION}" =~ ^[0-9]+$ || "${OS_VERSION}" -lt 2004 ]]; then
      case "$(grep 'UBUNTU_CODENAME' /etc/os-release | cut -d '=' -f 2 | tr -d '"')" in
        focal) OS_VERSION=2004 ;;
        jammy) OS_VERSION=2204 ;;
        noble) OS_VERSION=2404 ;;
      esac
    fi
  elif [[ -e /etc/debian_version ]]; then
    OS_FAMILY="debian"
    OS_VERSION="$(grep -oE '[0-9]+' /etc/debian_version | head -1)"
    if [[ -z "${OS_VERSION}" ]]; then
      case "$(grep '^DEBIAN_CODENAME' /etc/os-release 2>/dev/null | cut -d '=' -f 2)" in
        buster) OS_VERSION=10 ;;
        bullseye) OS_VERSION=11 ;;
        bookworm) OS_VERSION=12 ;;
        trixie) OS_VERSION=13 ;;
      esac
    fi
  elif grep -qs "Alibaba Cloud Linux" /etc/system-release 2>/dev/null; then
    OS_FAMILY="centos"
    if [[ "$(grep -oE '[0-9]+' /etc/system-release | head -1)" -ge 3 ]]; then
      OS_VERSION=9
    else
      OS_VERSION=7
    fi
  elif [[ -e /etc/almalinux-release || -e /etc/rocky-release || -e /etc/centos-release ]]; then
    OS_FAMILY="centos"
    OS_VERSION="$(grep -shoE '[0-9]+' /etc/almalinux-release /etc/rocky-release /etc/centos-release | head -1)"
  elif [[ -e /etc/fedora-release ]]; then
    OS_FAMILY="fedora"
    OS_VERSION="$(grep -oE '[0-9]+' /etc/fedora-release | head -1)"
  elif [[ -e /etc/redhat-release ]]; then
    OS_FAMILY="rhel"
    OS_VERSION="$(grep -oE '[0-9]+' /etc/redhat-release | head -1)"
  elif [[ -e /etc/SUSE-brand && "$(head -1 /etc/SUSE-brand)" == "openSUSE" ]] ||
    grep -qs '^ID=.*opensuse' /etc/os-release; then
    OS_FAMILY="openSUSE"
    if [[ -e /etc/SUSE-brand ]]; then
      OS_VERSION="$(tail -1 /etc/SUSE-brand | grep -oE '[0-9\.]+')"
    else
      OS_VERSION="$(grep 'VERSION_ID' /etc/os-release | cut -d '"' -f 2)"
    fi
  else
    exiterr "Unsupported distribution."
  fi
}

check_os_ver() {
  if [[ "${OS_FAMILY}" == "ubuntu" && "${OS_VERSION}" -lt 2004 ]]; then
    exiterr "Ubuntu 20.04+ required."
  fi
  if [[ "${OS_FAMILY}" == "debian" && "${OS_VERSION}" -lt 11 ]]; then
    exiterr "Debian 11+ required."
  fi
  if [[ "${OS_FAMILY}" == "centos" && "${OS_VERSION}" -lt 8 ]]; then
    exiterr "CentOS 8+ required."
  fi
  if [[ "${OS_FAMILY}" == "rhel" && "${OS_VERSION}" -lt 8 ]]; then
    exiterr "RHEL 8+ required."
  fi
}

check_docker() {
  log_step "Checking Docker Engine and Compose plugin"
  command -v docker >/dev/null 2>&1 || exiterr "docker not found. Install Docker Engine first."
  log_detail "docker version: $(docker --version 2>&1)"
  docker compose version >/dev/null 2>&1 || exiterr "'docker compose' (v2 plugin) not found."
  log_detail "docker compose version: $(docker compose version 2>&1)"
  log_step "Docker check OK"
}

install_curl_or_wget() {
  if command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1; then
    log_detail "curl/wget already available"
    return 0
  fi

  log_step "Installing wget"
  if [[ "${OS_FAMILY}" == "debian" || "${OS_FAMILY}" == "ubuntu" ]]; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get -yqq update
    apt-get -yqq install wget
  elif [[ "${OS_FAMILY}" == "openSUSE" ]]; then
    zypper install -y wget
  else
    yum -y -q install wget
  fi
}

find_public_ip() {
  local ip_url1="http://ipv4.icanhazip.com"
  local ip_url2="http://ip1.dynupdate.no-ip.com"

  PUBLIC_IP_ADDR="$(
    grep -m 1 -oE '^[0-9]{1,3}(\.[0-9]{1,3}){3}$' \
      <<<"$(wget -T 10 -t 1 -4qO- "${ip_url1}" 2>/dev/null || curl -m 10 -4Ls "${ip_url1}" 2>/dev/null || true)"
  )"
  if ! check_ip "${PUBLIC_IP_ADDR}"; then
    PUBLIC_IP_ADDR="$(
      grep -m 1 -oE '^[0-9]{1,3}(\.[0-9]{1,3}){3}$' \
        <<<"$(wget -T 10 -t 1 -4qO- "${ip_url2}" 2>/dev/null || curl -m 10 -4Ls "${ip_url2}" 2>/dev/null || true)"
    )"
  fi
}

detect_ip() {
  local ip_list ip_num

  if [[ $(ip -4 addr | grep inet | grep -vEc '127(\.[0-9]{1,3}){3}') -eq 1 ]]; then
    IP_ADDR="$(
      ip -4 addr | grep inet | grep -vE '127(\.[0-9]{1,3}){3}' |
        cut -d '/' -f 1 | grep -oE '[0-9]{1,3}(\.[0-9]{1,3}){3}'
    )"
  else
    IP_ADDR="$(ip -4 route get 1 | sed 's/ uid .*//' | awk '{print $NF; exit}' 2>/dev/null)"
    if ! check_ip "${IP_ADDR}"; then
      find_public_ip
      ip_list="$(
        ip -4 addr | grep inet | grep -vE '127(\.[0-9]{1,3}){3}' |
          cut -d '/' -f 1 | grep -oE '[0-9]{1,3}(\.[0-9]{1,3}){3}'
      )"
      if printf '%s\n' "${ip_list}" | grep -qx "${PUBLIC_IP_ADDR}"; then
        IP_ADDR="${PUBLIC_IP_ADDR}"
      elif [ "${AUTO}" -eq 0 ]; then
        echo
        echo "Which IPv4 address should be used?"
        printf '%s\n' "${ip_list}" | nl -s ') '
        read -rp "IPv4 address [1]: " ip_num
        [[ -z "${ip_num}" ]] && ip_num=1
        IP_ADDR="$(printf '%s\n' "${ip_list}" | sed -n "${ip_num}p")"
      else
        IP_ADDR="$(printf '%s\n' "${ip_list}" | sed -n '1p')"
      fi
    fi
  fi

  check_ip "${IP_ADDR}" || exiterr "Could not detect this server's IPv4."
}

check_nat_ip() {
  if check_pvt_ip "${IP_ADDR}"; then
    find_public_ip
    if ! check_ip "${PUBLIC_IP_ADDR}"; then
      if [ "${AUTO}" -eq 0 ]; then
        echo
        read -rp "Public IPv4 (NAT): " PUBLIC_IP_ADDR
        until check_ip "${PUBLIC_IP_ADDR}"; do
          read -rp "Public IPv4: " PUBLIC_IP_ADDR
        done
      else
        exiterr "Could not detect public IP (NAT). Set --serverurl explicitly."
      fi
    fi
  fi
}

docker_compose() {
  docker compose --project-directory "${HS_ROOT}" -f "${HS_COMPOSE}" "$@"
}

docker_pull() {
  log_step "Pulling image ${HEADSCALE_IMAGE}:${HEADSCALE_TAG}"
  docker pull "${HEADSCALE_IMAGE}:${HEADSCALE_TAG}"
}

docker_up() {
  log_step "Starting stack"
  docker_compose up -d "$@"
}

docker_down() {
  log_step "Stopping stack"
  if [ -f "${HS_COMPOSE}" ]; then
    docker_compose down || true
  fi
}

wait_for_headscale() {
  log_step "Waiting for Headscale to stay running (up to 90s)"
  local i=0 cid st st2

  while [ "${i}" -lt 90 ]; do
    cid="$(docker_compose ps -q "${HS_CONTAINER}" 2>/dev/null || true)"
    if [ -n "${cid}" ]; then
      st="$(docker inspect -f '{{.State.Status}}' "${cid}" 2>/dev/null || echo "")"
      if [ "${st}" = "running" ]; then
        if docker_compose exec -T "${HS_CONTAINER}" headscale version >/dev/null 2>&1; then
          sleep 4
          st2="$(docker inspect -f '{{.State.Status}}' "${cid}" 2>/dev/null || echo "")"
          if [ "${st2}" = "running" ]; then
            log_detail "container stable: Status=running"
            return 0
          fi
        fi
      fi
    fi
    printf '.'
    sleep 1
    i=$((i + 1))
  done
  echo
  log_raw "Headscale did not stay healthy."
  log_detail "Run: docker compose -f \"${HS_COMPOSE}\" logs --tail=100 ${HS_CONTAINER}"
  return 1
}

hs_cmd() {
  docker_compose exec -T "${HS_CONTAINER}" headscale "$@"
}

get_user_id() {
  local uname="$1"
  hs_cmd -o json users list 2>/dev/null |
    tr -d ' \n\t' |
    grep -oE "\\{\"id\":[0-9]*,[^}]*\"(name|username)\":\"${uname}\"[^}]*}" |
    head -1 | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2
}

check_service_running() {
  docker info >/dev/null 2>&1 || exiterr "Docker daemon not reachable."
  docker_compose exec -T "${HS_CONTAINER}" headscale version >/dev/null 2>&1 ||
    exiterr "Container ${HS_CONTAINER} not running."
  log_detail "container ${HS_CONTAINER}: exec check OK"
}

show_header() {
  log_raw "--- Headscale deploy helper ---"
  log_detail "Upstream: ${OFFICIAL_GIT}"
  log_detail "Registry: ${HEADSCALE_IMAGE}:${HEADSCALE_TAG}"
}
