#!/usr/bin/env sh
set -eu

SCRIPT_VERSION="1.0.1"
GOST_VERSION="${GOST_VERSION:-3.2.6}"
INSTALL_DIR="/usr/local/bin"
SERVICE_NAME="gost"

log() {
  printf '%s\n' "[INFO] $*"
}

warn() {
  printf '%s\n' "[WARN] $*" >&2
}

err() {
  printf '%s\n' "[ERROR] $*" >&2
  exit 1
}

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    err "Please run this script as root."
  fi
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

get_value() {
  var_name="$1"
  prompt="$2"
  default_value="${3:-}"
  current_value="$(eval "printf '%s' \"\${$var_name:-}\"")"

  if [ -n "$current_value" ]; then
    return 0
  fi

  if [ -n "$default_value" ]; then
    printf '%s' "$prompt [$default_value]: " >&2
  else
    printf '%s' "$prompt: " >&2
  fi

  input_value=""
  if [ -r /dev/tty ]; then
    IFS= read -r input_value < /dev/tty || true
  elif [ -t 0 ]; then
    IFS= read -r input_value || true
  else
    err "Interactive input is unavailable. Either run the script as a file, or pass SOCKS_USER, SOCKS_PASS, and SOCKS_PORT as environment variables."
  fi

  if [ -z "$input_value" ]; then
    input_value="$default_value"
  fi

  eval "$var_name=\"\$input_value\""
}

validate_inputs() {
  [ -n "${SOCKS_USER:-}" ] || err "SOCKS_USER cannot be empty."
  [ -n "${SOCKS_PASS:-}" ] || err "SOCKS_PASS cannot be empty."
  [ -n "${SOCKS_PORT:-}" ] || err "SOCKS_PORT cannot be empty."

  case "$SOCKS_PORT" in
    ''|*[!0-9]*) err "SOCKS_PORT must be a number." ;;
  esac

  if [ "$SOCKS_PORT" -lt 1 ] || [ "$SOCKS_PORT" -gt 65535 ]; then
    err "SOCKS_PORT must be between 1 and 65535."
  fi
}

urlencode() {
  input="$1"
  output=""

  while [ -n "$input" ]; do
    first_char="$(printf '%s' "$input" | cut -c1)"
    input="$(printf '%s' "$input" | cut -c2-)"
    case "$first_char" in
      [a-zA-Z0-9.~_-]) output="${output}${first_char}" ;;
      *)
        hex="$(printf '%s' "$first_char" | od -An -tx1 | tr -d ' \n')"
        output="${output}%$(printf '%s' "$hex" | tr '[:lower:]' '[:upper:]')"
        ;;
    esac
  done

  printf '%s' "$output"
}

detect_os() {
  if [ -r /etc/os-release ]; then
    OS_ID="$(. /etc/os-release; printf '%s' "$ID")"
    OS_LIKE="$(. /etc/os-release; printf '%s' "${ID_LIKE:-}")"
  else
    err "/etc/os-release not found. Unsupported system."
  fi

  SERVICE_MANAGER=""
  PKG_MANAGER=""

  case "$OS_ID" in
    alpine)
      SERVICE_MANAGER="openrc"
      PKG_MANAGER="apk"
      ;;
    ubuntu|debian)
      SERVICE_MANAGER="systemd"
      PKG_MANAGER="apt"
      ;;
    centos|rhel|rocky|almalinux|ol|fedora)
      SERVICE_MANAGER="systemd"
      if command_exists dnf; then
        PKG_MANAGER="dnf"
      else
        PKG_MANAGER="yum"
      fi
      ;;
    *)
      case "$OS_LIKE" in
        *debian*)
          SERVICE_MANAGER="systemd"
          PKG_MANAGER="apt"
          ;;
        *rhel*|*fedora*)
          SERVICE_MANAGER="systemd"
          if command_exists dnf; then
            PKG_MANAGER="dnf"
          else
            PKG_MANAGER="yum"
          fi
          ;;
        *)
          err "Unsupported system: $OS_ID"
          ;;
      esac
      ;;
  esac
}

install_packages() {
  log "Installing dependencies with $PKG_MANAGER"

  case "$PKG_MANAGER" in
    apk)
      apk update
      apk add --no-cache wget tar curl ca-certificates
      ;;
    apt)
      export DEBIAN_FRONTEND=noninteractive
      apt-get update
      apt-get install -y wget tar curl ca-certificates
      ;;
    yum)
      yum install -y wget tar curl ca-certificates
      ;;
    dnf)
      dnf install -y wget tar curl ca-certificates
      ;;
    *)
      err "Unsupported package manager: $PKG_MANAGER"
      ;;
  esac
}

detect_arch() {
  raw_arch="$(uname -m)"
  case "$raw_arch" in
    x86_64|amd64) GOST_ARCH="amd64" ;;
    aarch64|arm64) GOST_ARCH="arm64" ;;
    armv7l|armv7) GOST_ARCH="armv7" ;;
    armv6l|armv6) GOST_ARCH="armv6" ;;
    i386|i686) GOST_ARCH="386" ;;
    *) err "Unsupported architecture: $raw_arch" ;;
  esac
}

download_gost() {
  mkdir -p "$INSTALL_DIR"
  tmp_dir="$(mktemp -d)"
  archive_name="gost_${GOST_VERSION}_linux_${GOST_ARCH}.tar.gz"
  download_url="https://github.com/go-gost/gost/releases/download/v${GOST_VERSION}/${archive_name}"

  log "Downloading Gost v${GOST_VERSION} for ${GOST_ARCH}"
  if ! wget -O "$tmp_dir/$archive_name" "$download_url"; then
    rm -rf "$tmp_dir"
    err "Failed to download $download_url"
  fi

  tar -xzf "$tmp_dir/$archive_name" -C "$tmp_dir"
  [ -f "$tmp_dir/gost" ] || err "gost binary not found in archive."

  install -m 0755 "$tmp_dir/gost" "$INSTALL_DIR/gost"
  rm -rf "$tmp_dir"

  log "Installed Gost to $INSTALL_DIR/gost"
}

build_listen_url() {
  enc_user="$(urlencode "$SOCKS_USER")"
  enc_pass="$(urlencode "$SOCKS_PASS")"
  LISTEN_URL="socks5://${enc_user}:${enc_pass}@:${SOCKS_PORT}"
}

create_env_file_systemd() {
  mkdir -p /etc/gost
  cat > /etc/gost/gost.env <<EOFENV
GOST_LISTEN_URL=${LISTEN_URL}
EOFENV
}

create_systemd_service() {
  create_env_file_systemd
  cat > /etc/systemd/system/${SERVICE_NAME}.service <<'EOFSVC'
[Unit]
Description=Gost SOCKS5 Proxy
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=/etc/gost/gost.env
ExecStart=/usr/local/bin/gost -L ${GOST_LISTEN_URL}
Restart=always
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOFSVC

  systemctl daemon-reload
  systemctl enable --now "${SERVICE_NAME}.service"
}

create_openrc_service() {
  cat > /etc/init.d/${SERVICE_NAME} <<EOFRC
#!/sbin/openrc-run

name="${SERVICE_NAME}"
description="Gost SOCKS5 proxy"
command="/usr/local/bin/gost"
command_args="-L ${LISTEN_URL}"
command_background="yes"
pidfile="/run/${SERVICE_NAME}.pid"
output_log="/var/log/${SERVICE_NAME}.log"
error_log="/var/log/${SERVICE_NAME}.log"

start_pre() {
    rm -f /run/${SERVICE_NAME}.pid
}

depend() {
    need net
}
EOFRC

  sed -i 's/\r$//' /etc/init.d/${SERVICE_NAME}
  chmod +x /etc/init.d/${SERVICE_NAME}
  rc-update add "${SERVICE_NAME}" default
  rc-service "${SERVICE_NAME}" restart || rc-service "${SERVICE_NAME}" start
}

check_port_conflict() {
  if command_exists ss; then
    if ss -lnt | awk '{print $4}' | grep -Eq "(^|:)${SOCKS_PORT}$"; then
      warn "Port ${SOCKS_PORT} appears to already be in use. The service may fail to start."
    fi
  fi
}

show_status() {
  printf '\n'
  log "Gost version: $(/usr/local/bin/gost -V 2>/dev/null || true)"
  log "SOCKS5 address: $(hostname -I 2>/dev/null | awk '{print $1}'):${SOCKS_PORT}"
  log "Username: ${SOCKS_USER}"
  log "Password: ${SOCKS_PASS}"
  log "Service manager: ${SERVICE_MANAGER}"

  if [ "$SERVICE_MANAGER" = "systemd" ]; then
    systemctl --no-pager --full status "${SERVICE_NAME}.service" || true
  else
    rc-service "${SERVICE_NAME}" status || true
    [ -f "/var/log/${SERVICE_NAME}.log" ] && tail -n 20 "/var/log/${SERVICE_NAME}.log" || true
  fi

  printf '\n'
  log "Test locally with:"
  printf '%s\n' "curl --socks5 ${SOCKS_USER}:${SOCKS_PASS}@127.0.0.1:${SOCKS_PORT} http://ifconfig.me"
}

main() {
  require_root
  detect_os

  get_value SOCKS_USER "Enter SOCKS5 username" "global"
  get_value SOCKS_PASS "Enter SOCKS5 password" "ChangeMe123456"
  get_value SOCKS_PORT "Enter SOCKS5 port" "22026"

  validate_inputs
  install_packages
  detect_arch
  build_listen_url
  check_port_conflict
  download_gost

  if [ "$SERVICE_MANAGER" = "systemd" ]; then
    create_systemd_service
  else
    create_openrc_service
  fi

  show_status
}

main "$@"
