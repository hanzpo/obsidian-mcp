#!/usr/bin/env bash
set -euo pipefail

if [ ! -t 0 ]; then
  exec </dev/tty
fi

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUNTIME_DIR="$PROJECT_DIR/.obsidian-mcp"
ENV_FILE="$PROJECT_DIR/.env"
OS="$(uname -s)"

info()    { echo -e "\033[1;34m==>\033[0m $*"; }
success() { echo -e "\033[1;32m==>\033[0m $*"; }
warn()    { echo -e "\033[1;33m==>\033[0m $*"; }
error()   { echo -e "\033[1;31m==>\033[0m $*" >&2; }

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

stop_quickstart_processes() {
  if [ ! -d "$RUNTIME_DIR/pids" ]; then
    return
  fi

  info "Stopping quickstart background processes..."
  for pid_file in "$RUNTIME_DIR/pids"/*.pid; do
    [ -f "$pid_file" ] || continue
    stop_pid_file "$pid_file"
  done
}

has_production_services() {
  case "$OS" in
    Darwin)
      find /Library/LaunchDaemons -maxdepth 1 -name 'com.obsidian-mcp*.plist' -print -quit 2>/dev/null | grep -q .
      ;;
    *)
      find /etc/systemd/system -maxdepth 1 \( -name 'obsidian-mcp.target' -o -name 'obsidian-mcp.service' -o -name 'obsidian-sync-*.service' \) -print -quit 2>/dev/null | grep -q .
      ;;
  esac
}

require_root_for_production_cleanup() {
  if has_production_services && [ "$(id -u)" -ne 0 ]; then
    error "Production services are installed on this machine."
    echo "    Re-run with sudo so uninstall can remove the system services cleanly:"
    echo "    sudo ./uninstall.sh"
    exit 1
  fi
}

remove_production_services_macos() {
  [ "$(id -u)" -eq 0 ] || return

  local plist
  for plist in /Library/LaunchDaemons/com.obsidian-mcp*.plist; do
    [ -f "$plist" ] || continue
    launchctl bootout system "$plist" 2>/dev/null || true
    rm -f "$plist"
  done
}

remove_production_services_linux() {
  [ "$(id -u)" -eq 0 ] || return

  systemctl stop obsidian-mcp.target 2>/dev/null || true
  systemctl disable obsidian-mcp.target 2>/dev/null || true

  local unit
  for unit in /etc/systemd/system/obsidian-mcp.target \
    /etc/systemd/system/obsidian-mcp.service \
    /etc/systemd/system/obsidian-sync-*.service; do
    [ -f "$unit" ] || continue
    rm -f "$unit"
  done

  systemctl daemon-reload 2>/dev/null || true
}

remove_local_runtime() {
  info "Removing obsidian-mcp runtime files from this install..."
  rm -rf "$RUNTIME_DIR"
  rm -f "$ENV_FILE"
}

print_summary() {
  echo ""
  echo "  obsidian-mcp uninstall"
  echo "  ======================"
  echo ""
  echo "  This will remove:"
  echo "  - quickstart background processes started by this install"
  echo "  - production services installed by obsidian-mcp on this machine"
  echo "  - generated local config in this install: .env and .obsidian-mcp/"
  echo ""
  echo "  This will NOT remove:"
  echo "  - your real Obsidian desktop vault folders"
  echo "  - synced vault contents under this install's vaults/ directory"
  echo "  - ~/.obsidian-headless auth or sync state"
  echo "  - your remote Obsidian Sync state"
  echo "  - installed dependencies such as Node.js, Caddy, cloudflared, or obsidian-headless"
  echo ""
  echo "  This is a safe uninstall, not a destructive note purge."
  echo ""
}

confirm_uninstall() {
  local reply
  read -rp "Type uninstall to continue: " reply
  if [ "$reply" != "uninstall" ]; then
    warn "Cancelled."
    exit 0
  fi
}

print_summary
require_root_for_production_cleanup
confirm_uninstall

stop_quickstart_processes
if [ "$OS" = "Darwin" ]; then
  remove_production_services_macos
else
  remove_production_services_linux
fi
remove_local_runtime

echo ""
success "obsidian-mcp uninstall complete."
echo "    Preserved: desktop vaults, synced vault contents, ~/.obsidian-headless, and remote Sync state."
echo "    If you also want to remove synced vault mirrors or headless auth state, do that manually."
