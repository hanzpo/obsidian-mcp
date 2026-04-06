#!/usr/bin/env bash
set -euo pipefail

REPO="https://github.com/hanzpo/obsidian-mcp.git"
INSTALL_DIR="/opt/obsidian-mcp"

info()    { echo -e "\033[1;34m==>\033[0m $*"; }
success() { echo -e "\033[1;32m==>\033[0m $*"; }
error()   { echo -e "\033[1;31m==>\033[0m $*" >&2; }

if [ "$(id -u)" -ne 0 ]; then
  error "Run as root: curl -fsSL <url> | sudo bash"
  exit 1
fi

echo ""
echo "  obsidian-mcp installer"
echo "  ======================"
echo ""

# --- Install Node.js via nvm if missing ---
install_node() {
  if command -v node &>/dev/null; then
    NODE_VERSION=$(node -v | sed 's/v//' | cut -d. -f1)
    if [ "$NODE_VERSION" -ge 22 ]; then
      success "Node.js $(node -v) found."
      return
    fi
    warn "Node.js $(node -v) found but v22+ required."
  fi

  info "Installing Node.js via nvm..."
  export NVM_DIR="${NVM_DIR:-/root/.nvm}"
  if [ ! -d "$NVM_DIR" ]; then
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
  fi
  # shellcheck source=/dev/null
  [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
  nvm install 22
  nvm use 22
  success "Node.js $(node -v) installed."
}

# --- Install Docker if missing ---
install_docker() {
  if command -v docker &>/dev/null; then
    success "Docker found."
    return
  fi

  info "Installing Docker..."
  curl -fsSL https://get.docker.com | sh
  systemctl enable --now docker
  success "Docker installed."
}

# --- Install obsidian-headless if missing ---
install_ob() {
  if command -v ob &>/dev/null; then
    success "obsidian-headless found."
    return
  fi

  info "Installing obsidian-headless..."
  npm install -g obsidian-headless
  success "obsidian-headless installed."
}

# --- Install dependencies ---
install_node
install_docker
install_ob

# --- Clone or update repo ---
if [ -d "$INSTALL_DIR/.git" ]; then
  info "Updating existing installation..."
  git -C "$INSTALL_DIR" pull --ff-only
else
  info "Cloning obsidian-mcp..."
  git clone "$REPO" "$INSTALL_DIR"
fi

# --- Hand off to setup.sh ---
exec "$INSTALL_DIR/setup.sh"
