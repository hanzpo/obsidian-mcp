# obsidian-mcp

Remote MCP server that gives AI agents read/write access to your Obsidian vault. Runs on a VPS alongside [obsidian-headless](https://github.com/obsidianmd/obsidian-headless) to keep the vault in sync via Obsidian Sync.

## Architecture

```
AI Agent (Claude, Cursor, etc.)
  -- Streamable HTTP (HTTPS) -->
    Caddy (auto-TLS) -> MCP Server (Node.js)
                            |
                        vault files on disk
                            |
                        ob sync --continuous  (systemd)
                            |
                        Obsidian Sync <-> your devices
```

## Prerequisites

- A server (e.g. Hetzner VPS)
- An [Obsidian Sync](https://obsidian.md/sync) subscription

That's it. No domain needed -- the installer auto-configures one via [sslip.io](https://sslip.io). Docker, Node.js, and everything else is handled automatically.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/hanzpo/obsidian-mcp/main/install.sh | sudo bash
```

The script installs dependencies, walks you through Obsidian login and vault selection, and starts all services. At the end it prints the MCP client config to paste into Claude Desktop, Claude Code, Cursor, etc.

## Manual Setup

If you prefer to set things up yourself:

1. Install obsidian-headless and log in:

```bash
npm install -g obsidian-headless
ob login
```

2. Create the vault directory and sync:

```bash
mkdir -p vault
ob sync-list-remote                          # find your vault name
ob sync-setup --vault "My Vault" --path ./vault
ob sync --path ./vault                       # initial pull
```

3. Generate API key and configure:

```bash
make keygen       # creates .env with a random API key
```

Edit `.env` to set your domain:

```
DOMAIN=obsidian.example.com
API_KEY=<generated>
```

4. Install and start:

```bash
make install      # generates systemd units from templates, enables services
make start
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
| `make start` | Start sync + MCP server + Caddy |
| `make stop` | Stop everything |
| `make restart` | Restart everything |
| `make status` | Check service status |
| `make logs` | Tail all logs |
| `make logs-sync` | Tail sync logs |
| `make logs-mcp` | Tail MCP server logs |
| `make logs-caddy` | Tail Caddy logs |
| `make keygen` | Generate/rotate API key |
| `make update` | Pull latest, reinstall units, and restart |

## Development

```bash
npm ci
npm run dev          # start with hot reload
npm test             # run tests
npm run check        # tsc + eslint + tests
```
