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

# Sanitize vault name to a safe identifier for systemd unit names and directories
sanitize_name() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//'
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
info "Checking that required tools are installed..."
check_command node "https://nodejs.org/ (v22+)"
check_command caddy "https://caddyserver.com/docs/install"
check_command ob "npm install -g obsidian-headless"
check_command openssl

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

info "Your MCP server needs a domain for HTTPS."
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

echo ""

# --- Step 3: Obsidian login ---
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

# --- Step 4: Vault setup ---
VAULT_BASE="$PROJECT_DIR/vaults"
mkdir -p "$VAULT_BASE"

# Collect list of vaults to sync (new + existing)
VAULT_NAMES=()

# Detect already-synced vaults (subdirectories of vaults/)
for dir in "$VAULT_BASE"/*/; do
  [ -d "$dir" ] || continue
  name=$(basename "$dir")
  VAULT_NAMES+=("$name")
  success "Vault \"$name\" already synced. Skipping."
done

# If no vaults exist yet, we need at least one
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
  mkdir -p "$VAULT_DIR"

  info "Connecting to vault \"$VAULT_NAME\"..."
  ob sync-setup --vault "$VAULT_NAME" --path "$VAULT_DIR"

  info "Downloading vault contents (this may take a moment for large vaults)..."
  ob sync --path "$VAULT_DIR"
  success "Vault \"$VAULT_NAME\" synced to $VAULT_DIR."

  VAULT_NAMES+=("$SAFE_NAME")
  SHOWN_REMOTE_LIST=true
fi

# Ask if they want to add more vaults
while true; do
  echo ""
  read -rp "Add another vault? [y/N]: " ADD_MORE
  if [[ ! "${ADD_MORE:-n}" =~ ^[Yy] ]]; then
    break
  fi

  # Only show vault list if we haven't already
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

  # Skip if already synced
  if [[ " ${VAULT_NAMES[*]} " == *" $SAFE_NAME "* ]]; then
    warn "Vault \"$VAULT_NAME\" is already set up. Skipping."
    continue
  fi

  VAULT_DIR="$VAULT_BASE/$SAFE_NAME"
  mkdir -p "$VAULT_DIR"

  info "Connecting to vault \"$VAULT_NAME\"..."
  ob sync-setup --vault "$VAULT_NAME" --path "$VAULT_DIR"

  info "Downloading vault contents (this may take a moment for large vaults)..."
  ob sync --path "$VAULT_DIR"
  success "Vault \"$VAULT_NAME\" synced to $VAULT_DIR."

  VAULT_NAMES+=("$SAFE_NAME")
done

echo ""
info "Vaults configured: ${VAULT_NAMES[*]}"
echo ""

# --- Step 5: Generate API key and .env ---
info "Configuring authentication..."
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
    info "Generated API key for securing your MCP server."
  fi
else
  API_KEY=$(openssl rand -hex 32)
  info "Generated API key for securing your MCP server."
fi

# Update .env in place if it exists (preserves custom vars), otherwise create
ENV_FILE="$PROJECT_DIR/.env"
if [ -f "$ENV_FILE" ]; then
  if grep -q '^DOMAIN=' "$ENV_FILE"; then
    sed -i.bak "s|^DOMAIN=.*|DOMAIN=$DOMAIN|" "$ENV_FILE" && rm -f "$ENV_FILE.bak"
  else
    echo "DOMAIN=$DOMAIN" >> "$ENV_FILE"
  fi
  if grep -q '^API_KEY=' "$ENV_FILE"; then
    sed -i.bak "s|^API_KEY=.*|API_KEY=$API_KEY|" "$ENV_FILE" && rm -f "$ENV_FILE.bak"
  else
    echo "API_KEY=$API_KEY" >> "$ENV_FILE"
  fi
else
  cat > "$ENV_FILE" <<EOF
DOMAIN=$DOMAIN
API_KEY=$API_KEY
EOF
fi

success "Configuration saved to .env"
echo ""

# --- Step 6: Build the MCP server ---
info "Installing Node.js dependencies and building..."
cd "$PROJECT_DIR"
npm ci --silent
npm run build --silent
success "MCP server built."
echo ""

# --- Step 7: Detect paths for systemd templates ---
OB_BIN=$(command -v ob)
NODE_BIN=$(command -v node)
NODE_BIN_DIR=$(dirname "$NODE_BIN")
CADDY_BIN=$(command -v caddy)

# --- Step 8: Generate and install systemd units ---
info "Setting up services to run on boot..."
mkdir -p /etc/systemd/system

# Clean up orphaned sync services from previous runs
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

# Build list of sync service names
SYNC_SERVICES=""
for name in "${VAULT_NAMES[@]}"; do
  SYNC_SERVICES="$SYNC_SERVICES obsidian-sync-${name}.service"
done
SYNC_SERVICES="${SYNC_SERVICES# }"  # trim leading space

# Generate one sync service per vault
for name in "${VAULT_NAMES[@]}"; do
  sed \
    -e "s|__VAULT_NAME__|$name|g" \
    -e "s|__VAULT_DIR__|$VAULT_BASE/$name|g" \
    -e "s|__NODE_BIN_DIR__|$NODE_BIN_DIR|g" \
    -e "s|__OB_BIN__|$OB_BIN|g" \
    "$PROJECT_DIR/systemd/obsidian-sync.service.template" \
    > "/etc/systemd/system/obsidian-sync-${name}.service"
done

# Generate MCP service, Caddy service, and target
for tmpl in "$PROJECT_DIR/systemd/"*.template; do
  unit=$(basename "$tmpl" .template)
  # Skip sync template (handled per-vault above)
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
success "Services installed (${#VAULT_NAMES[@]} vault sync + MCP server + Caddy)."
echo ""

# --- Step 9: Start services ---
info "Starting services..."
systemctl start obsidian-mcp.target
success "All services running."
echo ""

# --- Step 10: Print client config ---
echo "========================================="
echo ""
echo "  Setup complete! Add this to your AI"
echo "  tool's MCP config to connect it to"
echo "  your vault:"
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
        "url": "https://${DOMAIN}/mcp",
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
echo "========================================="
echo ""
success "Your MCP server is live at https://${DOMAIN}/mcp"
