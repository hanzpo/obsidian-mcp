#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUNTIME_DIR="$PROJECT_DIR/.obsidian-mcp"
MODE_FILE="$RUNTIME_DIR/mode"
OS="$(uname -s)"
ARCHIVE_URL="https://github.com/hanzpo/obsidian-mcp/archive/refs/heads/main.tar.gz"

print_help() {
  echo "obsidian-mcp commands"
  echo ""
  echo "  npm run setup       Interactive setup. Choose quickstart or production."
  echo "  npm run status      Show status for the active mode"
  echo "  npm run logs        Tail logs for the active mode"
  echo "  npm run stop        Stop the active mode"
  echo "  npm run restart     Restart the active mode"
  echo "  npm run update      Refresh repo files and rerun setup for the active mode"
  echo "  npm run keygen      Generate or rotate the API key"
  echo "  npm run uninstall   Safely remove obsidian-mcp setup from this machine"
  echo ""
  echo "Other"
  echo "  npm run build"
  echo "  npm run check"
}

update_repo_files() {
  if [ -d "$PROJECT_DIR/.git" ] && command -v git >/dev/null 2>&1; then
    git pull
    return
  fi

  if ! command -v curl >/dev/null 2>&1 || ! command -v tar >/dev/null 2>&1; then
    echo "Update requires either git, or both curl and tar." >&2
    exit 1
  fi

  local tmpdir
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' RETURN

  curl -fsSL "$ARCHIVE_URL" -o "$tmpdir/obsidian-mcp.tar.gz"
  tar -xzf "$tmpdir/obsidian-mcp.tar.gz" --strip-components=1 -C "$PROJECT_DIR"
}

stop_pid_file() {
  local pid_file="$1"
  [ -f "$pid_file" ] || return

  local pid
  pid=$(cat "$pid_file" 2>/dev/null || true)
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
  fi
  rm -f "$pid_file"
}

quickstart_stop() {
  for pid_file in "$RUNTIME_DIR/pids"/*.pid; do
    [ -f "$pid_file" ] || continue
    stop_pid_file "$pid_file"
  done
}

quickstart_status() {
  local found=0
  for pid_file in "$RUNTIME_DIR/pids"/*.pid; do
    [ -f "$pid_file" ] || continue
    found=1
    local name
    local pid
    name=$(basename "$pid_file" .pid)
    pid=$(cat "$pid_file" 2>/dev/null || true)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      echo "$name: running (pid $pid)"
    else
      echo "$name: stopped"
    fi
  done

  if [ "$found" -eq 0 ]; then
    echo "Quickstart is not running."
  fi
}

quickstart_logs() {
  local logs_dir="$RUNTIME_DIR/logs"
  if [ ! -d "$logs_dir" ] || ! find "$logs_dir" -maxdepth 1 -name '*.log' -print -quit 2>/dev/null | grep -q .; then
    echo "No quickstart logs found yet. Run npm run setup first, or wait for the background processes to write logs." >&2
    exit 1
  fi
  tail -f "$logs_dir"/*.log
}

prod_up_macos() {
  sudo launchctl bootstrap system /Library/LaunchDaemons/com.obsidian-mcp.server.plist 2>/dev/null || true
  sudo launchctl bootstrap system /Library/LaunchDaemons/com.obsidian-mcp.caddy.plist 2>/dev/null || true
  local plist
  for plist in /Library/LaunchDaemons/com.obsidian-mcp.sync-*.plist; do
    [ -f "$plist" ] || continue
    sudo launchctl bootstrap system "$plist" 2>/dev/null || true
  done
}

prod_down_macos() {
  sudo launchctl bootout system /Library/LaunchDaemons/com.obsidian-mcp.server.plist 2>/dev/null || true
  sudo launchctl bootout system /Library/LaunchDaemons/com.obsidian-mcp.caddy.plist 2>/dev/null || true
  local plist
  for plist in /Library/LaunchDaemons/com.obsidian-mcp.sync-*.plist; do
    [ -f "$plist" ] || continue
    sudo launchctl bootout system "$plist" 2>/dev/null || true
  done
}

prod_status_macos() {
  sudo launchctl print system/com.obsidian-mcp.server 2>/dev/null || echo "MCP server: not running"
  sudo launchctl print system/com.obsidian-mcp.caddy 2>/dev/null || echo "Caddy: not running"
  local label
  while IFS= read -r label; do
    sudo launchctl print system/"$label" 2>/dev/null || echo "$label: not running"
  done < <(
    find /Library/LaunchDaemons -maxdepth 1 -name 'com.obsidian-mcp.sync-*.plist' -exec basename {} .plist \; 2>/dev/null
  )
}

prod_logs_macos() {
  local logs=()
  [ -f /tmp/obsidian-mcp.log ] && logs+=(/tmp/obsidian-mcp.log)
  [ -f /tmp/obsidian-caddy.log ] && logs+=(/tmp/obsidian-caddy.log)

  local sync_log
  for sync_log in /tmp/obsidian-sync-*.log; do
    [ -f "$sync_log" ] || continue
    logs+=("$sync_log")
  done

  if [ ${#logs[@]} -eq 0 ]; then
    echo "No production logs found yet. Run npm run setup first, or check whether the services have started." >&2
    exit 1
  fi

  tail -f "${logs[@]}"
}

prod_up_linux() {
  sudo systemctl start obsidian-mcp.target
}

prod_down_linux() {
  sudo systemctl stop obsidian-mcp.target
}

prod_status_linux() {
  local svc
  for svc in $(systemctl list-unit-files 'obsidian-sync-*.service' --no-legend 2>/dev/null | awk '{print $1}'); do
    sudo systemctl status "$svc" --no-pager || true
    echo ""
  done
  sudo systemctl status obsidian-mcp.service --no-pager || true
  echo ""
  sudo systemctl status caddy.service --no-pager || true
}

prod_logs_linux() {
  sudo journalctl -u 'obsidian-sync-*' -u obsidian-mcp -u caddy -f
}

prod_up() {
  if [ "$OS" = "Darwin" ]; then
    prod_up_macos
  else
    prod_up_linux
  fi
}

prod_down() {
  if [ "$OS" = "Darwin" ]; then
    prod_down_macos
  else
    prod_down_linux
  fi
}

prod_restart() {
  if [ "$OS" = "Darwin" ]; then
    prod_down_macos
    prod_up_macos
  else
    sudo systemctl restart obsidian-mcp.target
  fi
}

prod_status() {
  if [ "$OS" = "Darwin" ]; then
    prod_status_macos
  else
    prod_status_linux
  fi
}

prod_logs() {
  if [ "$OS" = "Darwin" ]; then
    prod_logs_macos
  else
    prod_logs_linux
  fi
}

detect_active_mode() {
  if [ -f "$MODE_FILE" ]; then
    local mode
    mode=$(tr -d '\r\n' < "$MODE_FILE")
    case "$mode" in
      quickstart|production)
        printf '%s\n' "$mode"
        return 0
        ;;
    esac
  fi

  if [ -d "$RUNTIME_DIR/pids" ] && find "$RUNTIME_DIR/pids" -name '*.pid' -print -quit 2>/dev/null | grep -q .; then
    printf '%s\n' quickstart
    return 0
  fi

  case "$OS" in
    Darwin)
      if find /Library/LaunchDaemons -maxdepth 1 -name 'com.obsidian-mcp*.plist' -print -quit 2>/dev/null | grep -q .; then
        printf '%s\n' production
        return 0
      fi
      ;;
    *)
      if find /etc/systemd/system -maxdepth 1 \( -name 'obsidian-mcp.target' -o -name 'obsidian-mcp.service' -o -name 'obsidian-sync-*.service' \) -print -quit 2>/dev/null | grep -q .; then
        printf '%s\n' production
        return 0
      fi
      ;;
  esac

  return 1
}

require_active_mode() {
  local mode
  if ! mode="$(detect_active_mode)"; then
    echo "No active obsidian-mcp mode detected. Run npm run setup first." >&2
    exit 1
  fi
  printf '%s\n' "$mode"
}

setup_cmd() {
  ./setup.sh "${1:-}"
}

status_cmd() {
  local mode
  mode="$(require_active_mode)"
  echo "Active mode: $mode"
  if [ "$mode" = "quickstart" ]; then
    quickstart_status
  else
    prod_status
  fi
}

logs_cmd() {
  local mode
  mode="$(require_active_mode)"
  echo "Active mode: $mode"
  if [ "$mode" = "quickstart" ]; then
    quickstart_logs
  else
    prod_logs
  fi
}

stop_cmd() {
  local mode
  mode="$(require_active_mode)"
  echo "Active mode: $mode"
  if [ "$mode" = "quickstart" ]; then
    quickstart_stop
  else
    prod_down
  fi
}

restart_cmd() {
  local mode
  mode="$(require_active_mode)"
  echo "Active mode: $mode"
  if [ "$mode" = "quickstart" ]; then
    PATH="$HOME/.local/bin:$PATH" ./setup.sh --quickstart
  else
    prod_restart
  fi
}

update_cmd() {
  local mode
  mode="$(require_active_mode)"
  echo "Active mode: $mode"
  update_repo_files
  if [ "$mode" = "quickstart" ]; then
    PATH="$HOME/.local/bin:$PATH" ./setup.sh --quickstart
  else
    sudo ./setup.sh --production
  fi
}

main() {
  local command="${1:-help}"
  case "$command" in
    help|-h|--help)
      print_help
      ;;
    setup)
      setup_cmd "${2:-}"
      ;;
    status)
      status_cmd
      ;;
    logs)
      logs_cmd
      ;;
    stop)
      stop_cmd
      ;;
    restart)
      restart_cmd
      ;;
    update)
      update_cmd
      ;;
    *)
      echo "Unknown command: $command" >&2
      exit 1
      ;;
  esac
}

cd "$PROJECT_DIR"
main "$@"
