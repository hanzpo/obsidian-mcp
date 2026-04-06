# obsidian-mcp

Remote MCP server that gives AI agents read/write access to your Obsidian vaults. On personal machines it mounts the real local vault folders used by the Obsidian app; on server-style machines without local desktop vaults it falls back to syncing with [obsidian-headless](https://github.com/obsidianmd/obsidian-headless).

## Fastest Path

```bash
curl -fsSL https://raw.githubusercontent.com/hanzpo/obsidian-mcp/main/install.sh | bash
```

That installs the app, runs interactive setup, and prints a remote MCP config. On personal machines it uses your real desktop vaults directly and lets you choose either a temporary Cloudflare URL or a persistent Cloudflare Tunnel hostname.

## Which Mode Should I Use?

- Laptop or desktop with the Obsidian app already installed: use local.
- VPS, home server, or separate always-on machine: use production.
- If local desktop vaults are detected, `obsidian-headless` is blocked on that machine to avoid sync conflicts.

## Modes

| Mode | Best for | Remote URL | URL stability | Infra burden | Survives reboot by default |
|------|----------|------------|---------------|--------------|----------------------------|
| Local | Running on your own machine with the Obsidian app | Yes | Temporary or stable, depending on tunnel choice | Medium | No |
| Production | Long-term self-hosting | Yes | Stable domain | Higher | Yes |

### 1. Local

- Uses local desktop vaults directly.
- Lets you choose a temporary `trycloudflare.com` URL or a persistent Cloudflare Tunnel hostname.
- Persistent local mode requires a Cloudflare-managed domain.
- Best for running on your own machine without `obsidian-headless`.

Manage local-mode processes:

```bash
npm run setup
npm run status
npm run logs
npm run stop
```

### 2. Production

```bash
curl -fsSL https://raw.githubusercontent.com/hanzpo/obsidian-mcp/main/install.sh | sudo bash
```

- Uses `obsidian-headless`, Caddy, and system services.
- Refuses to run on machines with local desktop vaults.
- Best for a stable endpoint on a separate always-on machine.
- If you use your own domain, point its `A` record or `AAAA` record at the server's public IP.
- If you use `sslip.io`, no DNS changes are needed. The setup flow prefers an IPv4-based hostname when available because it is more widely reachable from clients.

## Prerequisites

- a machine that can stay online while you use the MCP server
- for server or headless mode: an [Obsidian Sync](https://obsidian.md/sync) subscription and a machine without local Obsidian desktop vaults
- for local mode on your own machine: the Obsidian app installed with at least one local vault configured
- for persistent local mode: a Cloudflare-managed domain

## Where Files Live

- Install directory:
  - user install default: `~/.local/share/obsidian-mcp`
  - production install default: `/opt/obsidian-mcp`
- Local generated config for this install: `.env`
- Local runtime state for this install: `.obsidian-mcp/`
  - PID files
  - logs
  - active mode marker
  - mounted desktop-vault map
- Headless sync mirrors: `vaults/`
  - only used when the machine is running `obsidian-headless`
- Real desktop vault folders:
  - not copied into this repo
  - not owned by this app
  - mounted directly from the paths already managed by the Obsidian app
- `~/.obsidian-headless`
  - owned by `obsidian-headless`
  - stores its auth/local sync state
  - not removed by `npm run uninstall`
- Cloudflare Tunnel resources for local mode
  - named tunnel and DNS route live in your Cloudflare account
  - not removed by `npm run uninstall`

## Manual Setup

If you want to install things yourself instead of using `install.sh`:

1. Clone and enter the repo:

```bash
git clone https://github.com/hanzpo/obsidian-mcp.git
cd obsidian-mcp
```

2. Install dependencies:

Local mode also needs:

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
| `npm run setup` | Interactive setup. Choose local or production |
| `npm run status` | Show status for the active mode |
| `npm run logs` | Tail logs for the active mode |
| `npm run stop` | Stop the active mode |
| `npm run restart` | Restart the active mode |
| `npm run update` | Refresh repo files and rerun setup for the active mode |
| `npm run build` | Compile TypeScript |
| `npm run check` | Type-check, lint, and test |
| `npm run keygen` | Generate or rotate the API key |
| `npm run uninstall` | Safely remove obsidian-mcp setup from this machine |

## Active Mode

- `npm run setup` is the only setup entrypoint.
- During setup, you choose local or production.
- That choice is remembered in `.obsidian-mcp/mode`.
- After that, `npm run status`, `logs`, `stop`, `restart`, and `update` act on the active mode automatically.
- If no active mode is detected, those commands tell you to run `npm run setup` first.

## Auth Notes

- The printed client config uses `Authorization: Bearer <api-key>`, which is the preferred option.
- For compatibility with some clients and transports, the server also accepts `X-API-Key`, `?api_key=...`, and `?token=...`.
- Temporary local mode uses `trycloudflare.com`, so the URL can change on restart.
- Persistent local mode uses a named Cloudflare Tunnel hostname, so the URL stays the same, but the machine and tunnel still need to be running.

## Troubleshooting

**Local tunnel did not come up**

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

`setup.sh` is safe to re-run. In local mode it restarts the background MCP and tunnel processes. In production it refreshes services and configuration.

**What `npm run update` does**

- refreshes the repo files
- uses `git pull` for git checkouts
- falls back to downloading the latest repo archive for installer-style checkouts
- reruns setup for the active mode
- local stays local, production stays production

**Start over safely**

```bash
npm run uninstall
```

That removes obsidian-mcp's generated config and services from this machine after an explicit confirmation prompt, but intentionally preserves:

- your real Obsidian desktop vault folders
- synced vault contents under `vaults/`
- `~/.obsidian-headless`
- Cloudflare Tunnel resources such as named tunnels and DNS routes
- remote Obsidian Sync state

## Uninstall vs Purge

- `npm run uninstall` is a safe uninstall.
- It removes this app's generated config, runtime files, and installed services from this machine.
- It does not delete your notes, your desktop vault folders, your headless state, your Cloudflare Tunnel resources, or your remote Obsidian Sync state.
- If you want a real purge of synced mirrors, `~/.obsidian-headless`, or Cloudflare tunnel resources, do that manually after uninstall.

## Recovery

- If something looks broken, start with `npm run status` and `npm run logs`.
- If you changed configuration or updated the repo, run `npm run update`.
- If you want to choose the mode again or rebuild local state, rerun `npm run setup`.
- If you want to remove the app cleanly without touching note state, run `npm run uninstall`.

## Development

```bash
npm ci
npm run dev
npm test
npm run check
```
