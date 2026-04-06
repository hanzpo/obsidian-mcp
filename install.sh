#!/usr/bin/env bash
set -euo pipefail

REPO="https://github.com/hanzpo/obsidian-mcp.git"
ARCHIVE_URL="https://github.com/hanzpo/obsidian-mcp/archive/refs/heads/main.tar.gz"
INSTALL_DIR="${OBSIDIAN_MCP_INSTALL_DIR:-}"
OS="$(uname -s)"
DESKTOP_VAULT_COUNT=0

BLUE=$'\033[1;34m'
GREEN=$'\033[1;32m'
YELLOW=$'\033[1;33m'
RED=$'\033[1;31m'
CYAN=$'\033[1;36m'
BOLD=$'\033[1m'
DIM=$'\033[2m'
RESET=$'\033[0m'

info()    { echo -e "${BLUE}==>${RESET} $*"; }
success() { echo -e "${GREEN}==>${RESET} $*"; }
warn()    { echo -e "${YELLOW}==>${RESET} $*"; }
error()   { echo -e "${RED}==>${RESET} $*" >&2; }

section() {
  echo ""
  echo -e "${BOLD}${CYAN}$1${RESET}"
}

subtle() {
  echo -e "${DIM}$*${RESET}"
}

emphasize() {
  echo -e "${BOLD}$*${RESET}"
}

bullet() {
  echo -e "  ${CYAN}•${RESET} $*"
}

note_block() {
  local title="$1"
  shift
  echo ""
  echo -e "${BOLD}${title}${RESET}"
  for line in "$@"; do
    bullet "$line"
  done
}

read_prompt() {
  local prompt="$1"
  local reply
  if [ -t 0 ]; then
    read -rp "$prompt" reply
  else
    read -rp "$prompt" reply </dev/tty
  fi
  printf '%s' "$reply"
}

prompt_install_mode() {
  section "Choose Setup Mode"
  emphasize "  1) Local"
  bullet "Best for: your own laptop or desktop running the Obsidian app"
  bullet "Remote URL: yes"
  bullet "URL stability: temporary trycloudflare URL or stable Cloudflare Tunnel hostname"
  bullet "Vault access: uses local desktop vaults directly"
  bullet "Setup: no Caddy or system services; persistent mode needs a Cloudflare-managed domain"
  bullet "Reliability: remote access works while this machine stays on and the tunnel process is running"
  echo ""
  emphasize "  2) Production"
  bullet "Best for: a separate self-hosted server or always-on machine"
  bullet "Remote URL: yes"
  bullet "URL stability: stable domain"
  bullet "Vault access: obsidian-headless + Obsidian Sync only"
  bullet "Setup: more work, requires sudo/root, Caddy, and system services"
  bullet "Reliability: best for long-term self-hosting"
  echo ""

  local choice
  choice="$(read_prompt "Select mode [1]: ")"
  case "${choice:-1}" in
    1) MODE="local" ;;
    2) MODE="production" ;;
    *)
      error "Invalid choice. Enter 1 or 2."
      exit 1
      ;;
  esac
}

ensure_mode_permissions() {
  if [ "$MODE" = "local" ] && [ "$(id -u)" -eq 0 ]; then
    error "Local mode should be run as your normal user so desktop vault access and Cloudflare login live in your account."
    echo "    Re-run without sudo:"
    echo "    curl -fsSL https://raw.githubusercontent.com/hanzpo/obsidian-mcp/main/install.sh | bash"
    exit 1
  fi

  if [ "$MODE" = "production" ] && [ "$(id -u)" -ne 0 ]; then
    error "Production install needs root so it can install packages and register system services."
    echo "    Re-run with sudo:"
    echo "    curl -fsSL https://raw.githubusercontent.com/hanzpo/obsidian-mcp/main/install.sh | sudo bash"
    exit 1
  fi
}

expand_path() {
  local raw_path="$1"
  case "$raw_path" in
    "~")
      printf '%s' "$HOME"
      ;;
    \~/*)
      printf '%s/%s' "$HOME" "${raw_path#~/}"
      ;;
    *)
      printf '%s' "$raw_path"
      ;;
  esac
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

detect_desktop_vaults() {
  local config_path
  config_path="$(find_desktop_config || true)"
  if [ -z "$config_path" ] || [ ! -f "$config_path" ]; then
    DESKTOP_VAULT_COUNT=0
    return 1
  fi

  DESKTOP_VAULT_COUNT="$(
    node - "$config_path" <<'NODE'
const fs = require("node:fs");

const configPath = process.argv[2];
const raw = fs.readFileSync(configPath, "utf8");
const parsed = JSON.parse(raw);
const vaults = parsed.vaults || {};
let count = 0;

for (const entry of Object.values(vaults)) {
  if (!entry || typeof entry.path !== "string") continue;
  try {
    if (fs.existsSync(entry.path) && fs.statSync(entry.path).isDirectory()) {
      count += 1;
    }
  } catch {
    // Ignore stale entries.
  }
}

process.stdout.write(String(count));
NODE
  )"

  [ "${DESKTOP_VAULT_COUNT:-0}" -gt 0 ]
}

prompt_install_dir() {
  if [ -n "$INSTALL_DIR" ]; then
    INSTALL_DIR="$(expand_path "$INSTALL_DIR")"
    return
  fi

  local default_dir
  if [ "$MODE" = "local" ]; then
    default_dir="$HOME/.local/share/obsidian-mcp"
  else
    default_dir="/opt/obsidian-mcp"
  fi

  section "Install Location"
  bullet "Default: $default_dir"
  bullet "Safety: setup refuses to install into an unrelated non-empty directory"
  echo ""

  local chosen_dir
  chosen_dir="$(read_prompt "Install dir [$default_dir]: ")"
  INSTALL_DIR="$(expand_path "${chosen_dir:-$default_dir}")"
}

dir_has_contents() {
  local dir="$1"
  [ -d "$dir" ] || return 1
  find "$dir" -mindepth 1 -maxdepth 1 -print -quit | grep -q .
}

is_managed_install_dir() {
  local dir="$1"
  [ -f "$dir/package.json" ] &&
    [ -f "$dir/setup.sh" ] &&
    grep -q '"name":[[:space:]]*"obsidian-mcp"' "$dir/package.json"
}

ensure_safe_install_dir() {
  if [ -e "$INSTALL_DIR" ] && [ ! -d "$INSTALL_DIR" ]; then
    error "Install path exists but is not a directory: $INSTALL_DIR"
    exit 1
  fi

  if [ -d "$INSTALL_DIR" ]; then
    if is_managed_install_dir "$INSTALL_DIR"; then
      return
    fi

    if dir_has_contents "$INSTALL_DIR"; then
      error "Refusing to install into a non-empty unrelated directory: $INSTALL_DIR"
      echo "    Choose an empty directory or set OBSIDIAN_MCP_INSTALL_DIR to a dedicated path."
      exit 1
    fi
  fi
}

print_installer_banner() {
  echo ""
  echo -e "${BOLD}${CYAN}obsidian-mcp installer${RESET}"
  echo -e "${DIM}======================${RESET}"
  bullet "Install dir: $INSTALL_DIR"

  if [ "$MODE" = "local" ]; then
    note_block "Local Summary" \
      "Installs obsidian-mcp, Node.js, and cloudflared" \
      "Best on your own laptop or desktop with the Obsidian app installed" \
      "Uses local desktop vaults directly" \
      "Lets you choose a temporary trycloudflare URL or a persistent Cloudflare Tunnel hostname"
  else
    note_block "Production Summary" \
      "Best on a separate self-hosted server or always-on machine" \
      "Installs obsidian-mcp, Node.js, Caddy, and obsidian-headless" \
      "Registers system services and configures a stable HTTPS endpoint" \
      "Tradeoff: more setup, but better long-term durability"
  fi
}

install_node() {
  section "Node.js"
  if command -v node &>/dev/null; then
    NODE_VERSION=$(node -v | sed 's/v//' | cut -d. -f1)
    if [ "$NODE_VERSION" -ge 22 ]; then
      success "Node.js $(node -v) already installed."
      return
    fi
    warn "Node.js $(node -v) found, but v22+ is required. Upgrading..."
  fi

  info "Installing Node.js 22 via nvm..."
  export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
  if [ ! -d "$NVM_DIR" ]; then
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
  fi
  # shellcheck source=/dev/null
  [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
  nvm install 22
  success "Node.js $(node -v) installed."
}

install_caddy() {
  section "Caddy"
  if command -v caddy &>/dev/null; then
    success "Caddy already installed."
    return
  fi

  info "Installing Caddy (production mode HTTPS reverse proxy)..."

  case "$OS" in
    Darwin)
      if ! command -v brew &>/dev/null; then
        error "Homebrew is required on macOS. Install from https://brew.sh"
        exit 1
      fi
      sudo -u "${SUDO_USER:-$USER}" brew install caddy </dev/null
      ;;
    Linux)
      if command -v apt &>/dev/null; then
        apt update -qq
        apt install -y -qq debian-keyring debian-archive-keyring apt-transport-https curl >/dev/null 2>&1
        curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg 2>/dev/null
        curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null
        apt update -qq
        apt install -y -qq caddy >/dev/null 2>&1
      elif command -v dnf &>/dev/null; then
        dnf install -y 'dnf-command(copr)' >/dev/null 2>&1
        dnf copr enable -y @caddy/caddy >/dev/null 2>&1
        dnf install -y caddy >/dev/null 2>&1
      elif command -v yum &>/dev/null; then
        yum install -y yum-plugin-copr >/dev/null 2>&1
        yum copr enable -y @caddy/caddy >/dev/null 2>&1
        yum install -y caddy >/dev/null 2>&1
      else
        error "Could not detect package manager. Install Caddy manually: https://caddyserver.com/docs/install"
        exit 1
      fi

      systemctl stop caddy 2>/dev/null || true
      systemctl disable caddy 2>/dev/null || true
      ;;
    *)
      error "Unsupported OS: $OS"
      exit 1
      ;;
  esac

  success "Caddy installed."
}

download_cloudflared_binary() {
  local arch
  arch="$(uname -m)"
  local bin_dir="$HOME/.local/bin"
  local target="$bin_dir/cloudflared"
  local url=""
  mkdir -p "$bin_dir"

  case "$OS:$arch" in
    Linux:x86_64)
      url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
      ;;
    Linux:arm64|Linux:aarch64)
      url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64"
      ;;
    Darwin:x86_64)
      url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-darwin-amd64.tgz"
      ;;
    Darwin:arm64|Darwin:aarch64)
      url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-darwin-arm64.tgz"
      ;;
    *)
      error "Unsupported OS/architecture for automatic cloudflared install: $OS / $arch"
      exit 1
      ;;
  esac

  section "cloudflared"
  info "Installing cloudflared (persistent local tunnel)..."

  if [[ "$url" == *.tgz ]]; then
    local tmpdir
    tmpdir="$(mktemp -d)"
    curl -fsSL "$url" -o "$tmpdir/cloudflared.tgz"
    tar -xzf "$tmpdir/cloudflared.tgz" -C "$tmpdir"
    cp "$tmpdir/cloudflared" "$target"
    rm -rf "$tmpdir"
  else
    curl -fsSL "$url" -o "$target"
  fi

  chmod +x "$target"
  export PATH="$bin_dir:$PATH"
  success "cloudflared installed to $target"
}

install_cloudflared() {
  section "cloudflared"
  if command -v cloudflared &>/dev/null; then
    success "cloudflared already installed."
    return
  fi

  if [ "$OS" = "Darwin" ] && command -v brew &>/dev/null; then
    info "Installing cloudflared via Homebrew..."
    brew install cloudflared </dev/null
    success "cloudflared installed."
    return
  fi

  download_cloudflared_binary
}

install_ob() {
  section "obsidian-headless"
  if command -v ob &>/dev/null; then
    success "obsidian-headless already installed."
    return
  fi

  info "Installing obsidian-headless (syncs your vault via Obsidian Sync)..."
  npm install -g obsidian-headless </dev/null
  success "obsidian-headless installed."
}

expose_installed_tools() {
  local target_bin_dir
  if [ "$MODE" = "local" ]; then
    target_bin_dir="$HOME/.local/bin"
    mkdir -p "$target_bin_dir"
    export PATH="$target_bin_dir:$PATH"
  else
    target_bin_dir="/usr/local/bin"
    mkdir -p "$target_bin_dir"
  fi

  local tool
  for tool in node npm npx ob; do
    if command -v "$tool" &>/dev/null; then
      local source_path
      source_path="$(command -v "$tool")"
      if [ "$source_path" != "$target_bin_dir/$tool" ]; then
        ln -sf "$source_path" "$target_bin_dir/$tool"
      fi
    fi
  done
}

download_repo_archive() {
  local tmpdir
  tmpdir="$(mktemp -d)"
  curl -fsSL "$ARCHIVE_URL" -o "$tmpdir/obsidian-mcp.tar.gz"
  mkdir -p "$INSTALL_DIR"
  tar -xzf "$tmpdir/obsidian-mcp.tar.gz" --strip-components=1 -C "$INSTALL_DIR"
  rm -rf "$tmpdir"
}

MODE="${OBSIDIAN_MCP_MODE:-}"
if [ -z "$MODE" ]; then
  prompt_install_mode
fi

case "$MODE" in
  local|quickstart|production) ;;
  *)
    error "Unsupported mode: $MODE"
    exit 1
    ;;
esac

ensure_mode_permissions
prompt_install_dir
ensure_safe_install_dir
print_installer_banner

install_node
detect_desktop_vaults || true

if [ "$MODE" = "quickstart" ]; then
  MODE="local"
fi

if [ "$MODE" = "local" ]; then
  if [ "$DESKTOP_VAULT_COUNT" -gt 0 ]; then
    section "Vault Mode"
    success "Detected ${DESKTOP_VAULT_COUNT} local Obsidian vault(s)."
    bullet "Local mode will use the desktop vault folders directly"
    bullet "obsidian-headless will NOT be installed on this machine"
    bullet "This avoids sync conflicts with the Obsidian desktop app"
  else
    error "No local Obsidian desktop vaults were detected on this machine."
    echo "    Local mode requires the Obsidian app and at least one local vault."
    echo "    Use production on a separate server or always-on machine instead."
    exit 1
  fi
  install_cloudflared
else
  if [ "$DESKTOP_VAULT_COUNT" -gt 0 ]; then
    error "Local Obsidian vaults were detected on this machine."
    echo "    Production mode uses obsidian-headless and is blocked here to avoid sync conflicts with the Obsidian app."
    echo "    Use local mode on this machine, or run production on a separate server or always-on machine."
    exit 1
  fi
  install_caddy
fi
if [ "$MODE" = "production" ]; then
  install_ob
fi
expose_installed_tools

section "Repository"

if [ -d "$INSTALL_DIR/.git" ] && command -v git &>/dev/null; then
  info "Updating existing installation at $INSTALL_DIR..."
  git -C "$INSTALL_DIR" pull --ff-only </dev/null
elif [ ! -e "$INSTALL_DIR" ] && command -v git &>/dev/null; then
  info "Downloading obsidian-mcp to $INSTALL_DIR..."
  git clone "$REPO" "$INSTALL_DIR" </dev/null
else
  info "Downloading obsidian-mcp to $INSTALL_DIR..."
  download_repo_archive
fi

section "Next Step"
subtle "Handing off to setup..."

exec "$INSTALL_DIR/setup.sh" "--$MODE"
