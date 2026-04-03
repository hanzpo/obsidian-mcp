# obsidian-mcp

Remote MCP server that gives AI agents read/write access to your Obsidian vault. Runs on a VPS alongside [obsidian-headless](https://github.com/obsidianmd/obsidian-headless) to keep the vault in sync via Obsidian Sync.

## Architecture

```
AI Agent (Claude, Cursor, etc.)
  ── Streamable HTTP (HTTPS) ──>
    Caddy (auto-TLS) -> MCP Server (Node.js)
                            |
                        vault files on disk
                            |
                        ob sync --continuous  (systemd)
                            |
                        Obsidian Sync <-> your devices
```

## Setup

### Prerequisites

- A server (e.g. Hetzner VPS) with Docker installed
- An [Obsidian Sync](https://obsidian.md/sync) subscription
- Node.js 22+ (for obsidian-headless)
- A domain pointed at your server (A record, DNS only / grey cloud if Cloudflare)

### 1. Clone

```bash
git clone https://github.com/hanzpo/obsidian-mcp.git /opt/obsidian-mcp
cd /opt/obsidian-mcp
```

### 2. Set up Obsidian Sync

Install `obsidian-headless` and log in:

```bash
npm install -g obsidian-headless
ob login
```

Create the vault directory and set up sync:

```bash
mkdir -p vault
cd vault
ob sync-list-remote          # find your vault name
ob sync-setup --vault "My Vault"
ob sync                      # initial sync to pull files
cd ..
```

### 3. Generate API key and configure

```bash
make keygen
```

This creates `.env` with a random API key and prints the client config. Edit `.env` to set your vault path and domain:

```
DOMAIN=obsidian.hanzpo.com
VAULT_PATH=/opt/obsidian-mcp/vault
API_KEY=<generated>
```

### 4. Install and start

```bash
make install
make start
```

This starts two services via one command:

| Unit | What it does |
|------|-------------|
| `obsidian-sync.service` | Runs `ob sync --continuous` on the host |
| `obsidian-mcp.service` | Runs `docker compose up` (MCP server + Caddy) |

Both are grouped under `obsidian-mcp.target`. Starting/stopping the target controls everything.

### 6. Configure your AI client

Add to your MCP client config (Claude Desktop, Claude Code, Cursor, etc.):

```json
{
  "mcpServers": {
    "obsidian": {
      "type": "streamableHttp",
      "url": "https://obsidian.hanzpo.com/mcp",
      "headers": {
        "Authorization": "Bearer <your-api-key>"
      }
    }
  }
}
```

The `keygen.sh` script prints this with your actual key.

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
| `make update` | Pull latest and restart |

## Development

```bash
npm ci
npm run dev          # start with hot reload
npm test             # run tests
npm run check        # tsc + eslint + tests
```
