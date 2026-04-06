#!/usr/bin/env bash
set -euo pipefail

# Reopen stdin from terminal so interactive prompts work when piped (curl | bash)
if [ ! -t 0 ]; then
  exec </dev/tty
fi

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
OS="$(uname -s)"
export PATH="$HOME/.local/bin:$PATH"
RUNTIME_DIR="$PROJECT_DIR/.obsidian-mcp"
PID_DIR="$RUNTIME_DIR/pids"
LOG_DIR="$RUNTIME_DIR/logs"
MODE_FILE="$RUNTIME_DIR/mode"
PORT="${PORT:-3456}"
HOST="${HOST:-127.0.0.1}"
MODE=""
VAULT_MARKER=".obsidian-mcp-vault"
VAULT_SOURCE="headless"
VAULT_MAP_FILE="$RUNTIME_DIR/vault-map.json"
LOCAL_TUNNEL_ENV_FILE="$RUNTIME_DIR/local-tunnel.env"
LOCAL_TUNNEL_CONFIG_FILE="$RUNTIME_DIR/cloudflared-config.yml"
DESKTOP_CONFIG_PATH=""
DESKTOP_VAULT_LINES=()
LOCAL_TUNNEL_MODE=""
PUBLIC_HOSTNAME=""
TUNNEL_NAME=""
TUNNEL_UUID=""
TUNNEL_CREDENTIALS_FILE=""
LOCAL_URL=""

case "${1:-}" in
  "")
    MODE=""
    ;;
  --local|--quickstart)
    MODE="local"
    ;;
  --production)
    MODE="production"
    ;;
  *)
    echo "Unsupported mode: ${1:-}" >&2
    exit 1
    ;;
esac

info()    { echo -e "\033[1;34m==>\033[0m $*"; }
success() { echo -e "\033[1;32m==>\033[0m $*"; }
warn()    { echo -e "\033[1;33m==>\033[0m $*"; }
error()   { echo -e "\033[1;31m==>\033[0m $*" >&2; }
BOLD="\033[1m"
CYAN="\033[1;36m"
GREEN="\033[1;32m"
RESET="\033[0m"

prompt_setup_mode() {
  echo "Choose setup mode:"
  echo ""
  echo "  1) Local"
  echo "     For your own laptop or desktop running the Obsidian app."
  echo "     Uses the real local vault folders directly."
  echo "     Creates a persistent Cloudflare Tunnel hostname."
  echo ""
  echo "  2) Production"
  echo "     For a separate self-hosted server or always-on machine."
  echo "     Uses obsidian-headless, system services, and Caddy."
  echo "     Stable endpoint, but more setup."
  echo ""

  local choice
  read -rp "Select mode [1]: " choice
  case "${choice:-1}" in
    1) MODE="local" ;;
    2) MODE="production" ;;
    *)
      error "Invalid choice. Enter 1 or 2."
      exit 1
      ;;
  esac
  echo ""
}

check_command() {
  if ! command -v "$1" &>/dev/null; then
    error "$1 is not installed."
    [ -n "${2:-}" ] && echo "    Install: $2"
    exit 1
  fi
}

sanitize_name() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//'
}

ip_to_sslip_hostname() {
  local ip="$1"
  ip="${ip#[}"
  ip="${ip%]}"
  ip="${ip%%%*}"
  printf '%s.sslip.io' "${ip//[:.]/-}"
}

detect_public_ip() {
  local ip=""

  ip=$(curl -4 -fsSL --max-time 5 https://ifconfig.me 2>/dev/null || curl -4 -fsSL --max-time 5 https://api.ipify.org 2>/dev/null || true)
  if [ -n "$ip" ]; then
    printf '%s' "$ip"
    return 0
  fi

  ip=$(curl -6 -fsSL --max-time 5 https://ifconfig.me 2>/dev/null || curl -6 -fsSL --max-time 5 https://api.ipify.org 2>/dev/null || true)
  if [ -n "$ip" ]; then
    printf '%s' "$ip"
    return 0
  fi

  return 1
}

alias_exists() {
  local candidate="$1"
  local entry
  for entry in "${SELECTED_VAULTS[@]:-}"; do
    if [ "${entry%%|*}" = "$candidate" ]; then
      return 0
    fi
  done
  return 1
}

path_selected() {
  local candidate="$1"
  local entry
  for entry in "${SELECTED_VAULTS[@]:-}"; do
    if [ "${entry#*|}" = "$candidate" ]; then
      return 0
    fi
  done
  return 1
}

make_unique_alias() {
  local preferred="$1"
  local base
  base="$(sanitize_name "$preferred")"
  if [ -z "$base" ]; then
    base="vault"
  fi

  local candidate="$base"
  local suffix=2
  while alias_exists "$candidate"; do
    candidate="${base}-${suffix}"
    suffix=$((suffix + 1))
  done

  printf '%s' "$candidate"
}

find_desktop_config() {
  case "$OS" in
    Darwin)
      printf '%s' "$HOME/Library/Application Support/obsidian/obsidian.json"
      ;;
    Linux)
      printf '%s' "${XDG_CONFIG_HOME:-$HOME/.config}/obsidian/obsidian.json"
      ;;
    *)
      return 1
      ;;
  esac
}

load_desktop_vaults() {
  DESKTOP_CONFIG_PATH="$(find_desktop_config || true)"
  if [ -z "$DESKTOP_CONFIG_PATH" ] || [ ! -f "$DESKTOP_CONFIG_PATH" ]; then
    return 1
  fi

  DESKTOP_VAULT_LINES=()
  while IFS=$'\t' read -r vault_name vault_path; do
    [ -n "$vault_path" ] || continue
    DESKTOP_VAULT_LINES+=("$vault_name|$vault_path")
  done < <(
    node - "$DESKTOP_CONFIG_PATH" <<'NODE'
const fs = require("node:fs");
const path = require("node:path");

const configPath = process.argv[2];
const raw = fs.readFileSync(configPath, "utf8");
const parsed = JSON.parse(raw);
const vaults = parsed.vaults || {};

for (const entry of Object.values(vaults)) {
  if (!entry || typeof entry.path !== "string") continue;
  const vaultPath = entry.path;
  if (!fs.existsSync(vaultPath) || !fs.statSync(vaultPath).isDirectory()) {
    continue;
  }
  const name = path.basename(vaultPath) || vaultPath;
  process.stdout.write(`${name}\t${vaultPath}\n`);
}
NODE
  )

  [ ${#DESKTOP_VAULT_LINES[@]} -gt 0 ]
}

determine_vault_source() {
  if load_desktop_vaults; then
    if [ "$MODE" = "production" ]; then
      error "Local Obsidian desktop vaults were detected on this machine."
      echo "    Production mode uses obsidian-headless, which should not run alongside desktop Sync on the same device."
      echo "    Use local mode on this machine, or run production on a separate server or always-on machine."
      exit 1
    fi

    VAULT_SOURCE="desktop"
    info "Detected local Obsidian vaults."
    echo "    Local mode will use the desktop vault folders directly on this machine."
    echo "    obsidian-headless is blocked here to avoid sync conflicts with the Obsidian app."
    echo ""
    return
  fi

  VAULT_SOURCE="headless"
  if [ "$MODE" = "local" ]; then
    error "No local Obsidian desktop vaults were detected on this machine."
    echo "    Local mode requires the Obsidian app and at least one local vault."
    echo "    Use production on a separate server-style machine instead."
    exit 1
  fi
}

dir_has_contents() {
  local dir="$1"
  [ -d "$dir" ] || return 1
  find "$dir" -mindepth 1 -maxdepth 1 -print -quit | grep -q .
}

is_managed_vault_dir() {
  local dir="$1"
  [ -f "$dir/$VAULT_MARKER" ]
}

prepare_vault_dir() {
  local vault_label="$1"
  local vault_dir="$2"

  if is_managed_vault_dir "$vault_dir"; then
    return
  fi

  if [ -d "$vault_dir" ] && dir_has_contents "$vault_dir"; then
    error "Refusing to sync vault \"$vault_label\" into a non-empty directory: $vault_dir"
    echo "    Choose a different install directory or move/empty this folder first."
    echo "    This is a safety check to avoid overwriting unrelated files."
    exit 1
  fi

  mkdir -p "$vault_dir"
}

bootstrap_vault_sync() {
  local vault_label="$1"
  local vault_dir="$2"

  info "Connecting to vault \"$vault_label\"..."
  ob sync-setup --vault "$vault_label" --path "$vault_dir"

  info "Running first sync..."
  ob sync --path "$vault_dir"
  touch "$vault_dir/$VAULT_MARKER"

  success "Vault \"$vault_label\" synced safely to $vault_dir."
}

ensure_mode_permissions() {
  if [ -z "$MODE" ]; then
    prompt_setup_mode
  fi

  if [ "$MODE" = "local" ] && [ "$(id -u)" -eq 0 ]; then
    error "Local mode should be run as your normal user so desktop vault access and Cloudflare login live in your account."
    echo "    Re-run without sudo:"
    echo "    npm run setup"
    exit 1
  fi

  if [ "$MODE" = "production" ] && [ "$(id -u)" -ne 0 ]; then
    warn "Production setup needs root so it can register system services."
    echo "    Re-running with sudo..."
    exec sudo "$0" --production
  fi
}

write_active_mode() {
  mkdir -p "$RUNTIME_DIR"
  printf '%s\n' "$MODE" > "$MODE_FILE"
}

require_prerequisites() {
  info "Checking that required tools are installed..."
  check_command node "https://nodejs.org/ (v22+)"
  check_command openssl
  check_command curl

  if [ "$MODE" = "local" ]; then
    check_command cloudflared "Install with ./install.sh local or from https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/"
  else
    check_command caddy "https://caddyserver.com/docs/install"
  fi

  success "All prerequisites found."
  echo ""
}

require_headless_sync() {
  check_command ob "npm install -g obsidian-headless"
}

configure_domain() {
  EXISTING_DOMAIN=""
  PUBLIC_IP=""
  if [ -f "$PROJECT_DIR/.env" ]; then
    EXISTING_DOMAIN=$(grep '^DOMAIN=' "$PROJECT_DIR/.env" 2>/dev/null | cut -d= -f2 || true)
  fi

  if [ -n "$EXISTING_DOMAIN" ]; then
    DEFAULT_DOMAIN="$EXISTING_DOMAIN"
  else
    PUBLIC_IP="$(detect_public_ip || true)"
    if [ -n "$PUBLIC_IP" ]; then
      DEFAULT_DOMAIN="$(ip_to_sslip_hostname "$PUBLIC_IP")"
    else
      DEFAULT_DOMAIN="obsidian.example.com"
    fi
  fi

  info "Your production MCP server needs a domain for HTTPS."
  echo "    If you have a domain, enter it. Otherwise, press Enter to use the"
  echo "    auto-generated sslip.io domain (free, no DNS config needed)."
  echo ""
  read -rp "Domain [$DEFAULT_DOMAIN]: " DOMAIN
  DOMAIN="${DOMAIN:-$DEFAULT_DOMAIN}"

  if [ "$DOMAIN" = "obsidian.example.com" ]; then
    error "Could not auto-detect your server's public IP."
    echo "    Please enter your domain or IP-based sslip.io domain manually."
    echo "    Example: 49-13-100-42.sslip.io"
    exit 1
  fi

  if [[ "$DOMAIN" != *.sslip.io ]]; then
    if [ -n "$PUBLIC_IP" ]; then
      info "DNS reminder for your custom domain"
      if [[ "$PUBLIC_IP" == *:* ]]; then
        echo "    Point an AAAA record for $DOMAIN to $PUBLIC_IP before expecting HTTPS to work."
      else
        echo "    Point an A record for $DOMAIN to $PUBLIC_IP before expecting HTTPS to work."
      fi
    else
      info "DNS reminder for your custom domain"
      echo "    Point an A record or AAAA record for $DOMAIN to this server's public IP before expecting HTTPS to work."
    fi
    echo "    Caddy will obtain TLS automatically once DNS resolves and ports 80 and 443 are reachable."
    echo ""
  fi

  echo ""
}

ensure_obsidian_login() {
  require_headless_sync
  local ob_state_dir="$HOME/.obsidian-headless"
  if [ -e "$ob_state_dir" ] && [ ! -w "$ob_state_dir" ]; then
    error "obsidian-headless state directory is not writable: $ob_state_dir"
    echo "    This usually means it was created by a previous sudo/root install."
    echo "    Fix it with:"
    echo "    sudo chown -R $(id -un):$(id -gn) \"$ob_state_dir\""
    exit 1
  fi

  info "Checking if you're logged into Obsidian..."
  if ob sync-list-remote &>/dev/null; then
    success "Already logged into Obsidian."
  else
    warn "Not logged in. Opening Obsidian login..."
    echo "    You'll need your Obsidian account email and password."
    echo ""
    ob login
  fi
  echo ""
}

load_local_tunnel_settings() {
  [ -f "$LOCAL_TUNNEL_ENV_FILE" ] || return

  LOCAL_TUNNEL_MODE=$(grep '^LOCAL_TUNNEL_MODE=' "$LOCAL_TUNNEL_ENV_FILE" 2>/dev/null | cut -d= -f2- || true)
  PUBLIC_HOSTNAME=$(grep '^PUBLIC_HOSTNAME=' "$LOCAL_TUNNEL_ENV_FILE" 2>/dev/null | cut -d= -f2- || true)
  TUNNEL_NAME=$(grep '^TUNNEL_NAME=' "$LOCAL_TUNNEL_ENV_FILE" 2>/dev/null | cut -d= -f2- || true)
  TUNNEL_UUID=$(grep '^TUNNEL_UUID=' "$LOCAL_TUNNEL_ENV_FILE" 2>/dev/null | cut -d= -f2- || true)
  TUNNEL_CREDENTIALS_FILE=$(grep '^TUNNEL_CREDENTIALS_FILE=' "$LOCAL_TUNNEL_ENV_FILE" 2>/dev/null | cut -d= -f2- || true)
}

write_local_tunnel_settings() {
  mkdir -p "$RUNTIME_DIR"
  cat > "$LOCAL_TUNNEL_ENV_FILE" <<EOF
LOCAL_TUNNEL_MODE=$LOCAL_TUNNEL_MODE
PUBLIC_HOSTNAME=$PUBLIC_HOSTNAME
TUNNEL_NAME=$TUNNEL_NAME
TUNNEL_UUID=$TUNNEL_UUID
TUNNEL_CREDENTIALS_FILE=$TUNNEL_CREDENTIALS_FILE
EOF
}

prompt_local_tunnel_mode() {
  load_local_tunnel_settings

  local default_choice="1"
  if [ "$LOCAL_TUNNEL_MODE" = "persistent" ]; then
    default_choice="2"
  fi

  echo "Choose local access type:"
  echo ""
  echo "  1) Temporary tunnel"
  echo "     Uses a random trycloudflare.com URL."
  echo "     Easiest setup, but the URL changes when the tunnel changes."
  echo ""
  echo "  2) Persistent tunnel"
  echo "     Uses a named Cloudflare Tunnel and your own Cloudflare-managed hostname."
  echo "     Stable URL, but requires a Cloudflare-managed domain."
  echo ""

  local choice
  read -rp "Select local access type [$default_choice]: " choice
  case "${choice:-$default_choice}" in
    1) LOCAL_TUNNEL_MODE="temporary" ;;
    2) LOCAL_TUNNEL_MODE="persistent" ;;
    *)
      error "Invalid choice. Enter 1 or 2."
      exit 1
      ;;
  esac
  echo ""
}

ensure_cloudflare_login() {
  local cert_file="$HOME/.cloudflared/cert.pem"
  if [ -f "$cert_file" ]; then
    success "Cloudflare tunnel login already present."
    echo ""
    return
  fi

  info "Logging into Cloudflare for persistent local tunnel setup..."
  echo "    A browser will open so you can authorize cloudflared for a Cloudflare-managed domain."
  echo ""
  cloudflared tunnel login
  echo ""
}

configure_local_tunnel() {
  load_local_tunnel_settings
  local existing_public_hostname="$PUBLIC_HOSTNAME"
  local existing_tunnel_uuid="$TUNNEL_UUID"

  local default_hostname="${PUBLIC_HOSTNAME:-}"
  local default_tunnel_name="${TUNNEL_NAME:-obsidian-mcp-$(sanitize_name "$(hostname -s 2>/dev/null || echo local)")}"

  info "Configuring persistent local tunnel..."
  echo "    Enter a hostname on a domain managed by Cloudflare."
  echo "    Example: obsidian.example.com"
  echo ""

  read -rp "Public hostname [${default_hostname:-obsidian.example.com}]: " PUBLIC_HOSTNAME_INPUT
  PUBLIC_HOSTNAME="${PUBLIC_HOSTNAME_INPUT:-${default_hostname:-obsidian.example.com}}"
  if [ -z "$PUBLIC_HOSTNAME" ] || [ "$PUBLIC_HOSTNAME" = "obsidian.example.com" ]; then
    error "A real Cloudflare-managed hostname is required for local mode."
    exit 1
  fi

  read -rp "Tunnel name [$default_tunnel_name]: " TUNNEL_NAME_INPUT
  TUNNEL_NAME="${TUNNEL_NAME_INPUT:-$default_tunnel_name}"
  if [ -z "$TUNNEL_NAME" ]; then
    error "Tunnel name is required."
    exit 1
  fi

  if [ -z "$TUNNEL_UUID" ] || [ ! -f "${TUNNEL_CREDENTIALS_FILE:-}" ]; then
    local create_output
    info "Creating Cloudflare tunnel \"$TUNNEL_NAME\"..."
    create_output="$(cloudflared tunnel create "$TUNNEL_NAME" 2>&1)" || {
      printf '%s\n' "$create_output" >&2
      error "Failed to create Cloudflare tunnel."
      exit 1
    }
    printf '%s\n' "$create_output"
    TUNNEL_UUID="$(printf '%s\n' "$create_output" | grep -Eo '[0-9a-f]{8}-[0-9a-f-]{27}' | head -n 1 || true)"
    if [ -z "$TUNNEL_UUID" ]; then
      error "Could not determine tunnel ID from cloudflared output."
      exit 1
    fi
    TUNNEL_CREDENTIALS_FILE="$HOME/.cloudflared/$TUNNEL_UUID.json"
  else
    info "Reusing Cloudflare tunnel \"$TUNNEL_NAME\"."
  fi

  if [ ! -f "$TUNNEL_CREDENTIALS_FILE" ]; then
    error "Cloudflare tunnel credentials file not found: $TUNNEL_CREDENTIALS_FILE"
    exit 1
  fi

  if [ "$PUBLIC_HOSTNAME" = "$existing_public_hostname" ] && [ "$TUNNEL_UUID" = "$existing_tunnel_uuid" ] && [ -f "$LOCAL_TUNNEL_CONFIG_FILE" ]; then
    info "Reusing existing Cloudflare hostname route for $PUBLIC_HOSTNAME."
  else
    info "Routing $PUBLIC_HOSTNAME through Cloudflare Tunnel..."
    if ! cloudflared tunnel route dns "$TUNNEL_UUID" "$PUBLIC_HOSTNAME"; then
      error "Failed to route hostname through Cloudflare Tunnel."
      echo "    If the hostname is already routed elsewhere, remove that route in Cloudflare and rerun setup."
      exit 1
    fi
  fi

  cat > "$LOCAL_TUNNEL_CONFIG_FILE" <<EOF
tunnel: $TUNNEL_UUID
credentials-file: $TUNNEL_CREDENTIALS_FILE
ingress:
  - hostname: $PUBLIC_HOSTNAME
    service: http://$HOST:$PORT
  - service: http_status:404
EOF

  write_local_tunnel_settings
  LOCAL_URL="https://${PUBLIC_HOSTNAME}/mcp"
  success "Local tunnel configured at $PUBLIC_HOSTNAME"
  echo ""
}

clear_persistent_local_tunnel_settings() {
  PUBLIC_HOSTNAME=""
  TUNNEL_NAME=""
  TUNNEL_UUID=""
  TUNNEL_CREDENTIALS_FILE=""
}

setup_headless_vaults() {
  VAULT_BASE="$PROJECT_DIR/vaults"
  mkdir -p "$VAULT_BASE"
  VAULT_NAMES=()

  for dir in "$VAULT_BASE"/*/; do
    [ -d "$dir" ] || continue
    name=$(basename "$dir")
    if is_managed_vault_dir "$dir"; then
      VAULT_NAMES+=("$name")
      success "Vault \"$name\" already synced. Skipping."
    else
      warn "Found unmanaged directory under vaults/: $dir"
      warn "It will not be used automatically."
    fi
  done

  if [ ${#VAULT_NAMES[@]} -eq 0 ]; then
    info "Your Obsidian Sync vaults:"
    echo ""
    ob sync-list-remote
    echo ""

    echo "    Enter the name of the vault you want AI agents to access."
    read -rp "Vault name: " VAULT_NAME
    if [ -z "$VAULT_NAME" ]; then
      error "Vault name is required."
      exit 1
    fi

    SAFE_NAME=$(sanitize_name "$VAULT_NAME")
    VAULT_DIR="$VAULT_BASE/$SAFE_NAME"
    prepare_vault_dir "$VAULT_NAME" "$VAULT_DIR"
    bootstrap_vault_sync "$VAULT_NAME" "$VAULT_DIR"

    VAULT_NAMES+=("$SAFE_NAME")
    SHOWN_REMOTE_LIST=true
  fi

  while true; do
    echo ""
    read -rp "Add another vault? [y/N]: " ADD_MORE
    if [[ ! "${ADD_MORE:-n}" =~ ^[Yy] ]]; then
      break
    fi

    if [ "${SHOWN_REMOTE_LIST:-}" != "true" ]; then
      echo ""
      info "Your Obsidian Sync vaults:"
      echo ""
      ob sync-list-remote
      echo ""
      SHOWN_REMOTE_LIST=true
    fi

    read -rp "Vault name: " VAULT_NAME
    if [ -z "$VAULT_NAME" ]; then
      warn "Skipped (empty name)."
      continue
    fi

    SAFE_NAME=$(sanitize_name "$VAULT_NAME")
    if [[ " ${VAULT_NAMES[*]} " == *" $SAFE_NAME "* ]]; then
      warn "Vault \"$VAULT_NAME\" is already set up. Skipping."
      continue
    fi

    VAULT_DIR="$VAULT_BASE/$SAFE_NAME"
    prepare_vault_dir "$VAULT_NAME" "$VAULT_DIR"
    bootstrap_vault_sync "$VAULT_NAME" "$VAULT_DIR"

    VAULT_NAMES+=("$SAFE_NAME")
  done

  echo ""
  info "Vaults configured: ${VAULT_NAMES[*]}"
  echo ""
}

write_vault_map_file() {
  mkdir -p "$RUNTIME_DIR"
  node - "$VAULT_MAP_FILE" "${SELECTED_VAULTS[@]}" <<'NODE'
const fs = require("node:fs");
const path = require("node:path");

const outputPath = process.argv[2];
const entries = process.argv.slice(3);
const mounts = {};

for (const entry of entries) {
  const separator = entry.indexOf("|");
  if (separator === -1) continue;
  mounts[entry.slice(0, separator)] = entry.slice(separator + 1);
}

fs.mkdirSync(path.dirname(outputPath), { recursive: true });
fs.writeFileSync(outputPath, JSON.stringify(mounts, null, 2));
NODE
}

setup_desktop_vaults() {
  if [ ${#DESKTOP_VAULT_LINES[@]} -eq 0 ]; then
    error "No desktop vaults were detected."
    exit 1
  fi

  VAULT_NAMES=()
  SELECTED_VAULTS=()

  while true; do
    echo "Available local Obsidian vaults:"
    local i=1
    local entry
    for entry in "${DESKTOP_VAULT_LINES[@]}"; do
      local vault_name="${entry%%|*}"
      local vault_path="${entry#*|}"
      echo "  $i) $vault_name"
      echo "     $vault_path"
      i=$((i + 1))
    done
    echo ""

    local selection
    read -rp "Pick a vault number: " selection
    if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt ${#DESKTOP_VAULT_LINES[@]} ]; then
      error "Please choose a valid vault number."
      exit 1
    fi

    entry="${DESKTOP_VAULT_LINES[$((selection - 1))]}"
    local vault_name="${entry%%|*}"
    local vault_path="${entry#*|}"
    if path_selected "$vault_path"; then
      warn "That vault is already selected. Pick another one."
      echo ""
      continue
    fi
    local alias_name
    alias_name="$(make_unique_alias "$vault_name")"
    SELECTED_VAULTS+=("$alias_name|$vault_path")
    VAULT_NAMES+=("$alias_name")
    success "Using desktop vault \"$vault_name\" as $alias_name/"

    echo ""
    read -rp "Add another desktop vault? [y/N]: " add_more
    if [[ ! "${add_more:-n}" =~ ^[Yy] ]]; then
      break
    fi
    echo ""
  done

  write_vault_map_file
  info "Desktop vaults configured: ${VAULT_NAMES[*]}"
  echo ""
}

setup_vaults() {
  if [ "$VAULT_SOURCE" = "desktop" ]; then
    setup_desktop_vaults
  else
    setup_headless_vaults
  fi
}

configure_auth() {
  info "Configuring authentication..."
  local existing_key=""
  if [ -f "$PROJECT_DIR/.env" ]; then
    existing_key=$(grep '^API_KEY=' "$PROJECT_DIR/.env" 2>/dev/null | cut -d= -f2 || true)
  fi

  if [ -n "$existing_key" ]; then
    read -rp "API key already exists. Regenerate? [y/N]: " REGEN
    if [[ "${REGEN:-n}" =~ ^[Yy] ]]; then
      API_KEY=$(openssl rand -hex 32)
      info "Generated new API key."
    else
      API_KEY="$existing_key"
      info "Keeping existing API key."
    fi
  else
    API_KEY=$(openssl rand -hex 32)
    info "Generated API key for securing your MCP server."
  fi

  local env_file="$PROJECT_DIR/.env"
  if [ -f "$env_file" ]; then
    if grep -q '^API_KEY=' "$env_file"; then
      sed -i.bak "s|^API_KEY=.*|API_KEY=$API_KEY|" "$env_file" && rm -f "$env_file.bak"
    else
      echo "API_KEY=$API_KEY" >> "$env_file"
    fi

    if [ -n "${DOMAIN:-}" ]; then
      if grep -q '^DOMAIN=' "$env_file"; then
        sed -i.bak "s|^DOMAIN=.*|DOMAIN=$DOMAIN|" "$env_file" && rm -f "$env_file.bak"
      else
        echo "DOMAIN=$DOMAIN" >> "$env_file"
      fi
    fi
  else
    {
      [ -n "${DOMAIN:-}" ] && echo "DOMAIN=$DOMAIN"
      echo "API_KEY=$API_KEY"
    } > "$env_file"
  fi

  success "Configuration saved to .env"
  echo ""
}

build_server() {
  info "Installing Node.js dependencies and building..."
  cd "$PROJECT_DIR"
  npm ci --silent
  npm run build --silent
  success "MCP server built."
  echo ""
}

stop_pid_file() {
  local pid_file="$1"
  if [ ! -f "$pid_file" ]; then
    return
  fi

  local pid
  pid=$(cat "$pid_file" 2>/dev/null || true)
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    for _ in $(seq 1 10); do
      if ! kill -0 "$pid" 2>/dev/null; then
        break
      fi
      sleep 1
    done
    kill -9 "$pid" 2>/dev/null || true
  fi

  rm -f "$pid_file"
}

stop_local_processes() {
  mkdir -p "$PID_DIR"
  for pid_file in "$PID_DIR"/*.pid; do
    [ -f "$pid_file" ] || continue
    stop_pid_file "$pid_file"
  done
}

wait_for_local_server() {
  local url="http://$HOST:$PORT/mcp"
  for _ in $(seq 1 20); do
    local code
    code=$(curl -s -o /dev/null -w '%{http_code}' "$url" || true)
    if [ "$code" != "000" ]; then
      return 0
    fi
    sleep 1
  done

  error "Timed out waiting for the local MCP server to start."
  echo "    Check log: $LOG_DIR/obsidian-mcp.log"
  exit 1
}

start_local_processes() {
  info "Starting local background processes..."
  mkdir -p "$PID_DIR" "$LOG_DIR"
  stop_local_processes

  local mcp_log="$LOG_DIR/obsidian-mcp.log"
  local -a server_env
  server_env=(env API_KEY="$API_KEY" PORT="$PORT" HOST="$HOST")

  server_env+=(VAULT_MAP_FILE="$VAULT_MAP_FILE")

  nohup "${server_env[@]}" "$NODE_BIN" "$PROJECT_DIR/dist/index.js" >"$mcp_log" 2>&1 &
  echo $! > "$PID_DIR/obsidian-mcp.pid"
  wait_for_local_server

  local tunnel_log="$LOG_DIR/cloudflared.log"
  if [ "$LOCAL_TUNNEL_MODE" = "persistent" ]; then
    nohup "$CLOUDFLARED_BIN" tunnel --config "$LOCAL_TUNNEL_CONFIG_FILE" --no-autoupdate run "$TUNNEL_UUID" >"$tunnel_log" 2>&1 &
    echo $! > "$PID_DIR/cloudflared.pid"
    sleep 2
    if ! kill -0 "$(cat "$PID_DIR/cloudflared.pid" 2>/dev/null || true)" 2>/dev/null; then
      error "Cloudflare tunnel process exited unexpectedly."
      echo "    Check log: $LOG_DIR/cloudflared.log"
      exit 1
    fi
    LOCAL_URL="https://${PUBLIC_HOSTNAME}/mcp"
    success "Persistent local MCP endpoint is live."
    return
  fi

  nohup "$CLOUDFLARED_BIN" tunnel --url "http://$HOST:$PORT" --no-autoupdate >"$tunnel_log" 2>&1 &
  echo $! > "$PID_DIR/cloudflared.pid"

  for _ in $(seq 1 30); do
    local temp_base_url
    temp_base_url=$(grep -Eo 'https://[-a-z0-9]+\.trycloudflare\.com' "$tunnel_log" | head -n 1 || true)
    if [ -n "$temp_base_url" ]; then
      LOCAL_URL="${temp_base_url}/mcp"
      success "Temporary local MCP endpoint is live."
      return
    fi
    sleep 1
  done

  error "Timed out waiting for cloudflared to publish a public URL."
  echo "    Check log: $LOG_DIR/cloudflared.log"
  exit 1
}

install_services_linux() {
  info "Setting up systemd services to run on boot..."
  mkdir -p /etc/systemd/system

  for existing in /etc/systemd/system/obsidian-sync-*.service; do
    [ -f "$existing" ] || continue
    unit_name=$(basename "$existing" .service)
    vault_name="${unit_name#obsidian-sync-}"
    if [[ ! " ${VAULT_NAMES[*]} " == *" $vault_name "* ]]; then
      systemctl stop "$unit_name.service" 2>/dev/null || true
      systemctl disable "$unit_name.service" 2>/dev/null || true
      rm -f "$existing"
      info "Removed orphaned service: $unit_name"
    fi
  done

  SYNC_SERVICES=""
  for name in "${VAULT_NAMES[@]}"; do
    SYNC_SERVICES="$SYNC_SERVICES obsidian-sync-${name}.service"
  done
  SYNC_SERVICES="${SYNC_SERVICES# }"

  for name in "${VAULT_NAMES[@]}"; do
    sed \
      -e "s|__VAULT_NAME__|$name|g" \
      -e "s|__VAULT_DIR__|$VAULT_BASE/$name|g" \
      -e "s|__NODE_BIN_DIR__|$NODE_BIN_DIR|g" \
      -e "s|__OB_BIN__|$OB_BIN|g" \
      "$PROJECT_DIR/systemd/obsidian-sync.service.template" \
      > "/etc/systemd/system/obsidian-sync-${name}.service"
  done

  for tmpl in "$PROJECT_DIR/systemd/"*.template; do
    unit=$(basename "$tmpl" .template)
    [[ "$unit" == "obsidian-sync" ]] && continue
    sed \
      -e "s|__PROJECT_DIR__|$PROJECT_DIR|g" \
      -e "s|__NODE_BIN_DIR__|$NODE_BIN_DIR|g" \
      -e "s|__NODE_BIN__|$NODE_BIN|g" \
      -e "s|__OB_BIN__|$OB_BIN|g" \
      -e "s|__CADDY_BIN__|$CADDY_BIN|g" \
      -e "s|__SYNC_SERVICES__|$SYNC_SERVICES|g" \
      "$tmpl" > "/etc/systemd/system/$unit"
  done

  systemctl daemon-reload
  systemctl enable obsidian-mcp.target

  info "Starting services..."
  systemctl start obsidian-mcp.target
  success "Services installed and running (${#VAULT_NAMES[@]} vault sync + MCP server + Caddy)."
}

install_services_macos() {
  info "Setting up launchd services..."

  PLIST_DIR="/Library/LaunchDaemons"
  mkdir -p "$PLIST_DIR"

  ENV_VARS=$(cat <<ENVBLOCK
        <key>DOMAIN</key>
        <string>$DOMAIN</string>
        <key>API_KEY</key>
        <string>$API_KEY</string>
        <key>VAULT_PATH</key>
        <string>$VAULT_BASE</string>
        <key>PORT</key>
        <string>3456</string>
        <key>HOST</key>
        <string>0.0.0.0</string>
        <key>PATH</key>
        <string>$NODE_BIN_DIR:/usr/local/bin:/usr/bin:/bin</string>
ENVBLOCK
  )

  for name in "${VAULT_NAMES[@]}"; do
    LABEL="com.obsidian-mcp.sync-${name}"
    cat > "$PLIST_DIR/$LABEL.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$OB_BIN</string>
        <string>sync</string>
        <string>--continuous</string>
        <string>--path</string>
        <string>$VAULT_BASE/$name</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>$NODE_BIN_DIR:/usr/local/bin:/usr/bin:/bin</string>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/obsidian-sync-${name}.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/obsidian-sync-${name}.log</string>
</dict>
</plist>
PLIST
    launchctl bootout system "$PLIST_DIR/$LABEL.plist" 2>/dev/null || true
    launchctl bootstrap system "$PLIST_DIR/$LABEL.plist"
  done

  LABEL="com.obsidian-mcp.server"
  cat > "$PLIST_DIR/$LABEL.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$NODE_BIN</string>
        <string>$PROJECT_DIR/dist/index.js</string>
    </array>
    <key>WorkingDirectory</key>
    <string>$PROJECT_DIR</string>
    <key>EnvironmentVariables</key>
    <dict>
$ENV_VARS
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/obsidian-mcp.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/obsidian-mcp.log</string>
</dict>
</plist>
PLIST
  launchctl bootout system "$PLIST_DIR/$LABEL.plist" 2>/dev/null || true
  launchctl bootstrap system "$PLIST_DIR/$LABEL.plist"

  LABEL="com.obsidian-mcp.caddy"
  cat > "$PLIST_DIR/$LABEL.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$CADDY_BIN</string>
        <string>run</string>
        <string>--config</string>
        <string>$PROJECT_DIR/Caddyfile</string>
        <string>--adapter</string>
        <string>caddyfile</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>DOMAIN</key>
        <string>$DOMAIN</string>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/obsidian-caddy.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/obsidian-caddy.log</string>
</dict>
</plist>
PLIST
  launchctl bootout system "$PLIST_DIR/$LABEL.plist" 2>/dev/null || true
  launchctl bootstrap system "$PLIST_DIR/$LABEL.plist"

  success "Services installed and running (${#VAULT_NAMES[@]} vault sync + MCP server + Caddy)."
  echo "    Logs: /tmp/obsidian-*.log"
}

print_client_config() {
  local url="$1"
  echo -e "${CYAN}=========================================${RESET}"
  echo ""
  echo -e "  ${BOLD}URL${RESET}"
  echo -e "    ${GREEN}$url${RESET}"
  echo ""
  echo -e "  ${BOLD}API key${RESET}"
  echo -e "    ${GREEN}$API_KEY${RESET}"
  echo ""
  echo -e "  ${BOLD}Full client config${RESET}"
  echo ""
  echo "  Claude Code:  ~/.claude/settings.json"
  echo "  Claude Desktop: Settings > MCP Servers"
  echo "  Cursor:       .cursor/mcp.json"
  echo ""
  cat <<EOF
  {
    "mcpServers": {
      "obsidian": {
        "type": "streamableHttp",
        "url": "$url",
        "headers": {
          "Authorization": "Bearer $API_KEY"
        }
      }
    }
  }
EOF
  echo ""
  if [ ${#VAULT_NAMES[@]} -gt 1 ]; then
    echo "  Your vaults are accessible as subfolders:"
    for name in "${VAULT_NAMES[@]}"; do
      echo "    - $name/"
    done
    echo ""
  fi
  echo -e "${CYAN}=========================================${RESET}"
  echo ""
}

print_local_summary() {
  print_client_config "$LOCAL_URL"
  success "Your local MCP endpoint is live at $LOCAL_URL"
  if [ "$LOCAL_TUNNEL_MODE" = "persistent" ]; then
    echo "    This hostname stays the same as long as the Cloudflare tunnel route stays configured."
  else
    echo "    This URL is temporary. If cloudflared restarts or the machine reboots, expect a new URL."
  fi
  echo "    Vault source: local Obsidian desktop vaults."
  echo "    Sync stays managed by the Obsidian app on this device."
  echo "    Logs: $LOG_DIR"
  echo "    Stop processes: npm run stop"
}

print_production_summary() {
  print_client_config "https://${DOMAIN}/mcp"
  success "Your MCP server is live at https://${DOMAIN}/mcp"
  echo "    This is the durable mode: stable domain, system services, better long-term uptime."
}

ensure_mode_permissions

echo ""
echo "  obsidian-mcp setup"
echo "  ==================="
echo ""

if [ "$MODE" = "local" ]; then
  echo "  Local mode: for your own laptop or desktop with Obsidian installed."
  echo "  Uses local desktop vaults directly."
  echo "  You can choose a temporary trycloudflare URL or a persistent Cloudflare Tunnel hostname."
  echo "  Tradeoff: temporary is easiest; persistent requires a Cloudflare-managed domain."
else
  echo "  Production mode: for a separate self-hosted server or always-on machine."
  echo "  Uses obsidian-headless + system services + Caddy for a stable HTTPS endpoint."
  echo "  This mode is blocked on machines that already have local Obsidian desktop vaults."
  echo "  Tradeoff: more setup, but better durability and a stable endpoint."
fi
echo ""

require_prerequisites
determine_vault_source
if [ "$MODE" = "production" ]; then
  configure_domain
fi
if [ "$MODE" = "local" ]; then
  prompt_local_tunnel_mode
  if [ "$LOCAL_TUNNEL_MODE" = "persistent" ]; then
    ensure_cloudflare_login
    configure_local_tunnel
  else
    clear_persistent_local_tunnel_settings
    write_local_tunnel_settings
  fi
fi
if [ "$MODE" = "production" ] || [ "$VAULT_SOURCE" = "headless" ]; then
  ensure_obsidian_login
fi
setup_vaults
configure_auth
build_server

NODE_BIN=$(command -v node)
NODE_BIN_DIR=$(dirname "$NODE_BIN")
if [ "$MODE" = "production" ] || [ "$VAULT_SOURCE" = "headless" ]; then
  OB_BIN=$(command -v ob)
fi

if [ "$MODE" = "local" ]; then
  CLOUDFLARED_BIN=$(command -v cloudflared)
  start_local_processes
  write_active_mode
  echo ""
  print_local_summary
else
  CADDY_BIN=$(command -v caddy)
  if [ "$OS" = "Darwin" ]; then
    install_services_macos
  else
    install_services_linux
  fi
  write_active_mode
  echo ""
  print_production_summary
fi
