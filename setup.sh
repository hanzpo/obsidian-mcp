#!/usr/bin/env bash
set -euo pipefail

# Reopen stdin from terminal so interactive prompts work when piped (curl | bash)
if [ ! -t 0 ]; then
  exec </dev/tty
fi

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- Formatting helpers ---
info()    { echo -e "\033[1;34m==>\033[0m $*"; }
success() { echo -e "\033[1;32m==>\033[0m $*"; }
warn()    { echo -e "\033[1;33m==>\033[0m $*"; }
error()   { echo -e "\033[1;31m==>\033[0m $*" >&2; }

check_command() {
  if ! command -v "$1" &>/dev/null; then
    error "$1 is not installed."
    [ -n "${2:-}" ] && echo "    Install: $2"
    exit 1
  fi
}

# --- Root check ---
if [ "$(id -u)" -ne 0 ]; then
  error "Run as root: sudo ./setup.sh"
  exit 1
fi

echo ""
echo "  obsidian-mcp setup"
echo "  ==================="
echo ""

# --- Step 1: Check prerequisites ---
info "Checking prerequisites..."
check_command docker "https://docs.docker.com/engine/install/"
check_command node "https://nodejs.org/ (v22+)"
check_command ob "npm install -g obsidian-headless"
check_command openssl

# Check docker compose v2
if ! docker compose version &>/dev/null; then
  error "docker compose v2 is required (docker compose, not docker-compose)"
  exit 1
fi

success "All prerequisites found."
echo ""

# --- Step 2: Domain ---
EXISTING_DOMAIN=""
if [ -f "$PROJECT_DIR/.env" ]; then
  EXISTING_DOMAIN=$(grep '^DOMAIN=' "$PROJECT_DIR/.env" 2>/dev/null | cut -d= -f2 || true)
fi

if [ -n "$EXISTING_DOMAIN" ]; then
  DEFAULT_DOMAIN="$EXISTING_DOMAIN"
else
  # Auto-detect public IP and use sslip.io (free wildcard DNS, no config needed)
  PUBLIC_IP=$(curl -fsSL --max-time 5 https://ifconfig.me 2>/dev/null || curl -fsSL --max-time 5 https://api.ipify.org 2>/dev/null || true)
  if [ -n "$PUBLIC_IP" ]; then
    DEFAULT_DOMAIN="${PUBLIC_IP//./-}.sslip.io"
  else
    DEFAULT_DOMAIN="obsidian.example.com"
  fi
fi

info "Domain determines where your MCP server is reachable."
echo "    Leave blank to use the default (sslip.io works with any IP, no DNS setup needed)."
echo ""
read -rp "Domain [$DEFAULT_DOMAIN]: " DOMAIN
DOMAIN="${DOMAIN:-$DEFAULT_DOMAIN}"
echo ""

# --- Step 3: Obsidian login ---
info "Checking Obsidian login..."
if ob sync-list-remote &>/dev/null; then
  success "Already logged in."
else
  warn "Not logged in. Running ob login..."
  ob login
fi
echo ""

# --- Step 4: Vault setup ---
VAULT_DIR="$PROJECT_DIR/vault"

if [ -d "$VAULT_DIR" ] && [ -n "$(ls -A "$VAULT_DIR" 2>/dev/null)" ]; then
  success "Vault directory already has files. Skipping sync setup."
else
  mkdir -p "$VAULT_DIR"

  info "Remote vaults:"
  echo ""
  ob sync-list-remote
  echo ""

  read -rp "Vault name to sync: " VAULT_NAME
  if [ -z "$VAULT_NAME" ]; then
    error "Vault name is required."
    exit 1
  fi

  info "Setting up sync..."
  ob sync-setup --vault "$VAULT_NAME" --path "$VAULT_DIR"

  info "Running initial sync (this may take a moment)..."
  ob sync --path "$VAULT_DIR"
  success "Initial sync complete."
fi
echo ""

# --- Step 5: Generate API key and .env ---
if [ -f "$PROJECT_DIR/.env" ]; then
  EXISTING_KEY=$(grep '^API_KEY=' "$PROJECT_DIR/.env" 2>/dev/null | cut -d= -f2 || true)
  if [ -n "$EXISTING_KEY" ]; then
    read -rp "API key already exists. Regenerate? [y/N]: " REGEN
    if [[ "${REGEN:-n}" =~ ^[Yy] ]]; then
      API_KEY=$(openssl rand -hex 32)
      info "Generated new API key."
    else
      API_KEY="$EXISTING_KEY"
      info "Keeping existing API key."
    fi
  else
    API_KEY=$(openssl rand -hex 32)
    info "Generated API key."
  fi
else
  API_KEY=$(openssl rand -hex 32)
  info "Generated API key."
fi

cat > "$PROJECT_DIR/.env" <<EOF
DOMAIN=$DOMAIN
API_KEY=$API_KEY
EOF

success "Wrote .env"
echo ""

# --- Step 6: Detect paths for systemd templates ---
OB_BIN=$(command -v ob)
NODE_BIN_DIR=$(dirname "$(command -v node)")
DOCKER_BIN=$(command -v docker)

# --- Step 7: Generate and install systemd units ---
info "Installing systemd services..."
mkdir -p /etc/systemd/system

for tmpl in "$PROJECT_DIR/systemd/"*.template; do
  unit=$(basename "$tmpl" .template)
  sed \
    -e "s|__PROJECT_DIR__|$PROJECT_DIR|g" \
    -e "s|__NODE_BIN_DIR__|$NODE_BIN_DIR|g" \
    -e "s|__OB_BIN__|$OB_BIN|g" \
    -e "s|__DOCKER_BIN__|$DOCKER_BIN|g" \
    "$tmpl" > "/etc/systemd/system/$unit"
done

systemctl daemon-reload
systemctl enable obsidian-mcp.target
success "Systemd units installed."
echo ""

# --- Step 8: Start services ---
info "Starting services..."
systemctl start obsidian-mcp.target
success "Services started."
echo ""

# --- Step 9: Print client config ---
echo "========================================="
echo ""
echo "  Add this to your MCP client config"
echo "  (Claude Desktop, Claude Code, Cursor):"
echo ""
cat <<EOF
  {
    "mcpServers": {
      "obsidian": {
        "type": "streamableHttp",
        "url": "https://${DOMAIN}/mcp",
        "headers": {
          "Authorization": "Bearer $API_KEY"
        }
      }
    }
  }
EOF
echo ""
echo "========================================="
echo ""
success "Done! Your MCP server is running at https://${DOMAIN}/mcp"
