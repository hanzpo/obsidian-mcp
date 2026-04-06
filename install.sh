#!/usr/bin/env bash
set -euo pipefail

REPO="https://github.com/hanzpo/obsidian-mcp.git"
ARCHIVE_URL="https://github.com/hanzpo/obsidian-mcp/archive/refs/heads/main.tar.gz"
INSTALL_DIR="${OBSIDIAN_MCP_INSTALL_DIR:-}"
OS="$(uname -s)"

info()    { echo -e "\033[1;34m==>\033[0m $*"; }
success() { echo -e "\033[1;32m==>\033[0m $*"; }
warn()    { echo -e "\033[1;33m==>\033[0m $*"; }
error()   { echo -e "\033[1;31m==>\033[0m $*" >&2; }

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
  echo ""
  echo "Choose setup mode:"
  echo ""
  echo "  1) Quickstart"
  echo "     Best for: trying it fast on your own machine"
  echo "     Remote URL: yes"
  echo "     URL stability: temporary, changes if the tunnel restarts"
  echo "     Vault access: local desktop vaults when available, headless sync otherwise"
  echo "     Setup: easiest, no sudo, no Caddy, no system services"
  echo "     Reliability: fine while this machine stays on and the processes keep running"
  echo ""
  echo "  2) Production"
  echo "     Best for: a stable always-on endpoint"
  echo "     Remote URL: yes"
  echo "     URL stability: stable domain"
  echo "     Setup: more work, requires sudo/root, Caddy, and system services"
  echo "     Reliability: best for long-term self-hosting"
  echo ""

  local choice
  choice="$(read_prompt "Mode [1]: ")"
  case "${choice:-1}" in
    1) MODE="quickstart" ;;
    2) MODE="production" ;;
    *)
      error "Invalid choice. Enter 1 or 2."
      exit 1
      ;;
  esac
}

ensure_mode_permissions() {
  if [ "$MODE" = "quickstart" ] && [ "$(id -u)" -eq 0 ]; then
    error "Quickstart should be run as your normal user so Obsidian login and background processes live in your account."
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

prompt_install_dir() {
  if [ -n "$INSTALL_DIR" ]; then
    INSTALL_DIR="$(expand_path "$INSTALL_DIR")"
    return
  fi

  local default_dir
  if [ "$MODE" = "quickstart" ]; then
    default_dir="$HOME/.local/share/obsidian-mcp"
  else
    default_dir="/opt/obsidian-mcp"
  fi

  echo ""
  echo "Install location:"
  echo "  Default: $default_dir"
  echo "  Safety: setup refuses to install into an unrelated non-empty directory."
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

install_node() {
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

  info "Installing cloudflared (quickstart tunnel)..."

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
  if [ "$MODE" = "quickstart" ]; then
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
  quickstart|production) ;;
  *)
    error "Unsupported mode: $MODE"
    exit 1
    ;;
esac

ensure_mode_permissions
prompt_install_dir
ensure_safe_install_dir

echo ""
echo "  obsidian-mcp installer"
echo "  ======================"
echo ""
echo "  Install dir: $INSTALL_DIR"
echo ""
if [ "$MODE" = "quickstart" ]; then
  echo "  This will install obsidian-mcp, Node.js, cloudflared, and"
  echo "  obsidian-headless, then give you a public remote MCP URL fast."
  echo "  Tradeoff: easiest setup, but the URL is temporary."
else
  echo "  This will install obsidian-mcp and its production dependencies"
  echo "  (Node.js, Caddy, obsidian-headless), then register system services."
  echo "  Tradeoff: more setup, but you get a stable long-lived endpoint."
fi
echo ""

install_node
if [ "$MODE" = "quickstart" ]; then
  install_cloudflared
else
  install_caddy
fi
install_ob
expose_installed_tools

echo ""

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

echo ""

exec "$INSTALL_DIR/setup.sh" "--$MODE"
