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
                        ob sync --continuous
                            |
                        Obsidian Sync <-> your devices
```

## Setup

### Prerequisites

- A server (e.g. Hetzner VPS) with Docker installed
- An [Obsidian Sync](https://obsidian.md/sync) subscription
- Node.js 22+ (for initial obsidian-headless setup)
- A domain pointed at your server (e.g. `obsidian.hanzpo.com`)

### 1. Clone and build

```bash
git clone https://github.com/hanzpo/obsidian-mcp.git
cd obsidian-mcp
npm ci && npm run build
```

### 2. Set up Obsidian Sync

Install `obsidian-headless` and log in:

```bash
npm install -g obsidian-headless
ob login
```

Create a directory for your vault and set up sync:

```bash
mkdir -p vault
cd vault
ob sync-list-remote          # find your vault name
ob sync-setup --vault "My Vault"
ob sync                      # do an initial sync to pull files
cd ..
```

### 3. Generate API key and configure

```bash
./keygen.sh
```

This creates a `.env` file with a random API key and prints the client config you'll need later. Edit `.env` to set your vault path and domain:

```bash
vim .env
```

```
DOMAIN=obsidian.hanzpo.com
VAULT_PATH=/absolute/path/to/vault
API_KEY=<generated>
```

### 4. Start everything

```bash
docker compose up -d
```

This starts three services:

| Service | What it does |
|---------|-------------|
| `sync` | Runs `ob sync --continuous` to keep the vault in sync |
| `mcp` | The MCP server (port 3456, internal only) |
| `caddy` | Reverse proxy with automatic HTTPS |

### 5. Configure your AI client

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

The `keygen.sh` script prints this config with your actual key.

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

**Rotate API key:**

```bash
./keygen.sh
docker compose restart mcp
```

**Change domain:**

Edit `DOMAIN` in `.env`, then:

```bash
docker compose restart caddy
```

**View logs:**

```bash
docker compose logs -f        # all services
docker compose logs -f sync   # just sync
docker compose logs -f mcp    # just MCP server
```

**Update:**

```bash
git pull
npm ci && npm run build
docker compose up -d --build
```

## Development

```bash
npm run dev          # start with hot reload
npm test             # run tests
npm run build        # compile TypeScript
```
