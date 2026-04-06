# obsidian-mcp

Remote MCP server that gives AI agents read/write access to your Obsidian vault. Runs on a VPS alongside [obsidian-headless](https://github.com/obsidianmd/obsidian-headless) to keep the vault in sync via Obsidian Sync.

## Architecture

```
AI Agent (Claude, Cursor, etc.)
  -- Streamable HTTP (HTTPS) -->
    Caddy (auto-TLS) -> Node.js MCP Server
                            |
                        vault files on disk
                            |
                        ob sync --continuous  (systemd)
                            |
                        Obsidian Sync <-> your devices
```

All three services (Caddy, MCP server, vault sync) run directly on the host via systemd. No Docker required.

## Prerequisites

- A server (e.g. Hetzner VPS)
- An [Obsidian Sync](https://obsidian.md/sync) subscription

That's it. No domain needed -- the installer auto-configures one via [sslip.io](https://sslip.io). Node.js, Caddy, and everything else is handled automatically.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/hanzpo/obsidian-mcp/main/install.sh | sudo bash
```

The script installs dependencies, walks you through Obsidian login and vault selection, and starts all services. You can sync multiple vaults -- the setup script will ask if you want to add more. At the end it prints the MCP client config to paste into Claude Desktop, Claude Code, Cursor, etc.

## Manual Setup

If you prefer to set things up yourself:

1. Clone and enter the repo:

```bash
git clone https://github.com/hanzpo/obsidian-mcp.git
cd obsidian-mcp
```

2. Install obsidian-headless and log in:

```bash
npm install -g obsidian-headless
ob login
```

3. Create the vault directory and sync (each vault gets its own subfolder):

```bash
mkdir -p vaults/my-vault
ob sync-list-remote                                      # find your vault name
ob sync-setup --vault "My Vault" --path ./vaults/my-vault
ob sync --path ./vaults/my-vault                         # initial pull
```

Repeat for additional vaults (`vaults/work`, `vaults/notes`, etc.).

4. Generate API key and configure:

```bash
make keygen       # creates .env with a random API key
```

Edit `.env` to set your domain (or use `<your-ip>.sslip.io` if you don't have one):

```
DOMAIN=obsidian.example.com
API_KEY=<generated>
```

5. Build, install, and start (requires root for systemd):

```bash
sudo make install      # builds app, generates systemd units, enables services
sudo make start
```

## Client Config

Add to your MCP client (Claude Desktop, Claude Code, Cursor, etc.):

```json
{
  "mcpServers": {
    "obsidian": {
      "type": "streamableHttp",
      "url": "https://your-domain.com/mcp",
      "headers": {
        "Authorization": "Bearer <your-api-key>"
      }
    }
  }
}
```

## Tools

| Tool | Description |
|------|-------------|
| `read_note` | Read a note's content and metadata |
| `read_notes` | Batch read up to 10 notes |
| `create_note` | Create a note with optional frontmatter |
| `edit_note` | Append, prepend, or find-and-replace |
| `delete_note` | Delete a note (requires confirmation) |
| `move_note` | Move or rename a note |
| `list_directory` | Browse vault structure |
| `search_notes` | Full-text search with BM25 ranking |
| `get_frontmatter` | Read YAML frontmatter as JSON |
| `update_frontmatter` | Merge or remove frontmatter fields |
| `manage_tags` | Add, remove, or list tags |
| `get_vault_stats` | Vault statistics and recent files |
| `get_links` | Outgoing wikilinks and backlinks |

## Operations

| Command | What it does |
|---------|-------------|
| `make build` | Install deps and compile TypeScript |
| `make install` | Build + generate systemd units + enable services |
| `make start` | Start all services |
| `make stop` | Stop all services |
| `make restart` | Restart all services |
| `make status` | Check service status |
| `make logs` | Tail all logs |
| `make logs-sync` | Tail vault sync logs |
| `make logs-mcp` | Tail MCP server logs |
| `make logs-caddy` | Tail Caddy logs |
| `make keygen` | Generate/rotate API key |
| `make update` | Pull latest, rebuild, reinstall, and restart |

## Troubleshooting

**Services won't start**

```bash
make status              # check which service failed
make logs                # see what went wrong
```

**HTTPS/certificate errors**

If using sslip.io, make sure ports 80 and 443 are open in your firewall. Caddy needs port 80 for the Let's Encrypt ACME challenge.

```bash
ufw allow 80/tcp
ufw allow 443/tcp
```

**Sync not working**

```bash
make logs-sync           # check for auth or network errors
ob sync-list-remote      # verify you're still logged in
```

If `ob login` keeps asking for credentials, your auth token may have expired. Run `ob login` again and restart:

```bash
ob login
make restart
```

**Port 443 already in use**

Another service (nginx, apache) may be using port 443. Stop it first:

```bash
ss -tlnp | grep 443     # find what's using the port
```

**Re-running setup**

`setup.sh` is safe to re-run. It skips steps that are already done (vault exists, API key exists) and asks before overwriting anything.

## Development

```bash
npm ci
npm run dev          # start with hot reload
npm test             # run tests
npm run check        # tsc + eslint + tests
```
