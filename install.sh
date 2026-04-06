#!/usr/bin/env bash
set -euo pipefail

REPO="https://github.com/hanzpo/obsidian-mcp.git"
INSTALL_DIR="$(pwd)/obsidian-mcp"
OS="$(uname -s)"

info()    { echo -e "\033[1;34m==>\033[0m $*"; }
success() { echo -e "\033[1;32m==>\033[0m $*"; }
warn()    { echo -e "\033[1;33m==>\033[0m $*"; }
error()   { echo -e "\033[1;31m==>\033[0m $*" >&2; }

if [ "$(id -u)" -ne 0 ]; then
  error "Run as root: curl -fsSL <url> | sudo bash"
  exit 1
fi

echo ""
echo "  obsidian-mcp installer"
echo "  ======================"
echo ""
echo "  This will install obsidian-mcp and its dependencies"
echo "  (Node.js, Caddy, obsidian-headless) if they're missing."
echo ""

# --- Install Node.js via nvm if missing ---
install_node() {
  if command -v node &>/dev/null; then
    NODE_VERSION=$(node -v | sed 's/v//' | cut -d. -f1)
    if [ "$NODE_VERSION" -ge 22 ]; then
      success "Node.js $(node -v) already installed."
      return
    fi
    warn "Node.js $(node -v) found, but v22+ is required. Upgrading..."
  fi

  info "Installing Node.js 22 via nvm (needed to run the MCP server and obsidian-headless)..."
  export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
  if [ ! -d "$NVM_DIR" ]; then
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
  fi
  # shellcheck source=/dev/null
  [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
  nvm install 22
  success "Node.js $(node -v) installed."
}

# --- Install Caddy if missing ---
install_caddy() {
  if command -v caddy &>/dev/null; then
    success "Caddy already installed."
    return
  fi

  info "Installing Caddy (handles HTTPS and reverse proxy)..."

  case "$OS" in
    Darwin)
      # macOS — use Homebrew
      if ! command -v brew &>/dev/null; then
        error "Homebrew is required on macOS. Install from https://brew.sh"
        exit 1
      fi
      sudo -u "${SUDO_USER:-$USER}" brew install caddy
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

      # Stop the default caddy service — we manage our own
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

# --- Install obsidian-headless if missing ---
install_ob() {
  if command -v ob &>/dev/null; then
    success "obsidian-headless already installed."
    return
  fi

  info "Installing obsidian-headless (syncs your vault via Obsidian Sync)..."
  npm install -g obsidian-headless
  success "obsidian-headless installed."
}

# --- Install dependencies ---
install_node
install_caddy
install_ob

echo ""

# --- Clone or update repo ---
if [ -d "$INSTALL_DIR/.git" ]; then
  info "Updating existing installation at $INSTALL_DIR..."
  git -C "$INSTALL_DIR" pull --ff-only
else
  info "Downloading obsidian-mcp to $INSTALL_DIR..."
  git clone "$REPO" "$INSTALL_DIR"
fi

echo ""

# --- Hand off to setup.sh ---
exec "$INSTALL_DIR/setup.sh"
