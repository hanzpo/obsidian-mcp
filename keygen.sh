#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

KEY=$(openssl rand -hex 32)

echo "Generated API key:"
echo ""
echo "  $KEY"
echo ""

# If .env exists, update/add API_KEY; otherwise create from example
if [ -f "$SCRIPT_DIR/.env" ]; then
  if grep -q '^API_KEY=' "$SCRIPT_DIR/.env"; then
    sed -i.bak "s|^API_KEY=.*|API_KEY=$KEY|" "$SCRIPT_DIR/.env" && rm -f "$SCRIPT_DIR/.env.bak"
    echo "Updated API_KEY in .env"
  else
    echo "API_KEY=$KEY" >> "$SCRIPT_DIR/.env"
    echo "Added API_KEY to .env"
  fi
else
  cp "$SCRIPT_DIR/.env.example" "$SCRIPT_DIR/.env"
  sed -i.bak "s|^API_KEY=.*|API_KEY=$KEY|" "$SCRIPT_DIR/.env" && rm -f "$SCRIPT_DIR/.env.bak"
  echo "Created .env from .env.example with API_KEY set"
fi

DOMAIN=$(grep '^DOMAIN=' "$SCRIPT_DIR/.env" 2>/dev/null | cut -d= -f2 || echo "obsidian.example.com")
DOMAIN=${DOMAIN:-obsidian.example.com}

echo ""
echo "Client config:"
echo ""
cat <<EOF
{
  "mcpServers": {
    "obsidian": {
      "type": "streamableHttp",
      "url": "https://${DOMAIN}/mcp",
      "headers": {
        "Authorization": "Bearer $KEY"
      }
    }
  }
}
EOF
