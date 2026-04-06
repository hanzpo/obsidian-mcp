#!/usr/bin/env bash
set -euo pipefail

KEY=$(openssl rand -hex 32)

echo "Generated API key:"
echo ""
echo "  $KEY"
echo ""

# If .env exists, update/add API_KEY; otherwise create from example
if [ -f .env ]; then
  if grep -q '^API_KEY=' .env; then
    sed -i.bak "s|^API_KEY=.*|API_KEY=$KEY|" .env && rm -f .env.bak
    echo "Updated API_KEY in .env"
  else
    echo "API_KEY=$KEY" >> .env
    echo "Added API_KEY to .env"
  fi
else
  cp .env.example .env
  sed -i.bak "s|^API_KEY=.*|API_KEY=$KEY|" .env && rm -f .env.bak
  echo "Created .env from .env.example with API_KEY set"
fi

DOMAIN=$(grep '^DOMAIN=' .env 2>/dev/null | cut -d= -f2 || echo "obsidian.example.com")
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
