# obsidian-mcp

Remote MCP server that gives AI agents read/write access to your Obsidian vaults. On personal machines it mounts the real local vault folders used by the Obsidian app; on server-style machines without local desktop vaults it falls back to syncing with [obsidian-headless](https://github.com/obsidianmd/obsidian-headless).

## Fastest Path

If your goal is "get a remote MCP URL working as fast as possible," use quickstart:

```bash
curl -fsSL https://raw.githubusercontent.com/hanzpo/obsidian-mcp/main/install.sh | bash
```

Quickstart does this:

- installs Node.js and `cloudflared`, plus `obsidian-headless` only when this machine does not already have local Obsidian vaults
- downloads the repo even if `git` is not installed
- installs into a dedicated app directory instead of assuming the current working directory is safe
- on laptops and desktops, detects local Obsidian app vaults and uses them directly
- blocks `obsidian-headless` on machines where local Obsidian desktop vaults are detected
- on servers or headless-safe machines, falls back to `obsidian-headless`
- if headless mode is used, walks you through `ob login`
- if headless mode is used, performs the initial sync in `pull-only` mode, then switches to normal bidirectional sync
- starts the MCP server in the background
- starts continuous sync in the background only when headless mode is used
- opens a public HTTPS tunnel and prints ready-to-paste MCP config

No sudo, no Caddy, no system services. The tradeoff is that the public tunnel URL is temporary and changes each time you rerun quickstart.

## Modes

| Mode | Best for | Remote URL | URL stability | Infra burden | Survives reboot by default |
|------|----------|------------|---------------|--------------|----------------------------|
| Quickstart | First success, testing, running on your own machine | Yes | Temporary `trycloudflare.com` URL | Low | No |
| Production | Long-term self-hosting | Yes | Stable domain | Higher | Yes |

### 1. Quickstart

Best for first success and testing with Poke or any remote MCP client.

Architecture:

```text
AI Agent
  --> HTTPS -->
    cloudflared tunnel
      --> local MCP server
            |
            --> desktop vaults on disk
            or
            --> synced vaults on disk via ob sync --continuous
```

Use when you want:

- a remote MCP endpoint now
- minimal setup
- no domain or reverse proxy work

Tradeoffs:

- easiest path from zero to working remote MCP
- works well on a laptop, desktop, or home server
- on personal machines, it uses the Obsidian app's real vault folders directly
- if local Obsidian vaults are detected, it does not let `obsidian-headless` run on that same device
- URL is temporary and usually changes if the tunnel restarts
- depends on this machine staying on and the background processes staying alive
- setup refuses to sync into a non-empty unmanaged vault directory
- first sync is forced to `pull-only` so an empty local folder is not treated as authoritative

Manage quickstart processes:

```bash
npm run setup
npm run status
npm run logs
npm run stop
```

### 2. Production

Best for an always-on self-hosted deployment with a stable domain on a separate server-style machine.

```bash
curl -fsSL https://raw.githubusercontent.com/hanzpo/obsidian-mcp/main/install.sh | sudo bash
```

Production does this:

- installs Node.js, Caddy, and `obsidian-headless`
- syncs one or more vaults
- configures HTTPS with Caddy
- installs system services via systemd or launchd
- prints a stable remote MCP URL

Tradeoffs:

- more moving parts up front
- requires sudo/root
- intentionally refuses to run on machines where local Obsidian desktop vaults are detected
- best if you want a stable endpoint you can leave running for a long time
- better fit for a VPS, Mac mini, or other always-on machine
- setup refuses to install into or sync over unrelated non-empty directories
- first sync is forced to `pull-only` before switching to normal bidirectional sync

Architecture:

```text
AI Agent
  --> HTTPS -->
    Caddy
      --> MCP server
            |
            --> synced vaults on disk
            --> ob sync --continuous
```

## Prerequisites

- a machine that can stay online while you use the MCP server
- for server or headless mode: an [Obsidian Sync](https://obsidian.md/sync) subscription and a machine without local Obsidian desktop vaults
- for desktop-vault quickstart on your own machine: a local Obsidian app install with at least one vault already configured

Production mode also benefits from a server or machine with a reachable public IP. Quickstart works well even when you do not want to manage domains and TLS yourself.

## Manual Setup

If you want to install things yourself instead of using `install.sh`:

1. Clone and enter the repo:

```bash
git clone https://github.com/hanzpo/obsidian-mcp.git
cd obsidian-mcp
```

2. Install dependencies:

Quickstart also needs:

```bash
brew install cloudflared              # macOS
# or install cloudflared another way on Linux
```

Headless/server mode also needs:

```bash
npm install -g obsidian-headless
```

Production also needs:

```bash
# install Caddy
```

3. Run setup:

```bash
npm run setup
```

## Client Config

Both modes print a ready-to-paste MCP config at the end. It looks like this:

```json
{
  "mcpServers": {
    "obsidian": {
      "type": "streamableHttp",
      "url": "https://your-endpoint.example/mcp",
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

## Commands

Start with:

```bash
npm run help
```

Recommended commands:

| Command | What it does |
|---------|-------------|
| `npm run setup` | Interactive setup. Choose quickstart or production |
| `npm run status` | Show status for the active mode |
| `npm run logs` | Tail logs for the active mode |
| `npm run stop` | Stop the active mode |
| `npm run restart` | Restart the active mode |
| `npm run update` | Pull latest changes and rerun setup for the active mode |
| `npm run build` | Compile TypeScript |
| `npm run check` | Type-check, lint, and test |
| `npm run keygen` | Generate or rotate the API key |
| `npm run uninstall` | Safely remove obsidian-mcp setup from this machine |

## Troubleshooting

**Quickstart tunnel did not come up**

```bash
npm run logs
```

Look at `.obsidian-mcp/logs/cloudflared.log`.

**Sync is not working**

```bash
ob sync-list-remote
npm run logs
```

If `ob login` keeps asking for credentials, run it again and rerun setup.

**Production HTTPS/certificate errors**

If using sslip.io, make sure ports 80 and 443 are open. Caddy needs port 80 for the ACME challenge.

```bash
ufw allow 80/tcp
ufw allow 443/tcp
```

**Re-running setup**

`setup.sh` is safe to re-run. In quickstart it restarts the background MCP, sync, and tunnel processes. In production it refreshes services and configuration.

**Start over safely**

```bash
npm run uninstall
```

That removes obsidian-mcp's generated config and services from this machine after an explicit confirmation prompt, but intentionally preserves:

- your real Obsidian desktop vault folders
- synced vault contents under `vaults/`
- `~/.obsidian-headless`
- remote Obsidian Sync state

## Development

```bash
npm ci
npm run dev
npm test
npm run check
```
