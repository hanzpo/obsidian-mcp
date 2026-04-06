import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import type { Services } from "../server.js";

export function registerGetVaultStats(server: McpServer, services: Services) {
  server.registerTool(
    "get_vault_stats",
    {
      description:
        "Summarize accessible markdown notes and folders, including total note count, folder count, total markdown size, and the 10 most recently modified markdown files. In mounted mode, stats span all mounted vault aliases.",
      inputSchema: {},
      annotations: { readOnlyHint: true, openWorldHint: false },
    },
    async () => {
      const entries = await services.fs.listDirectory("", true);
      const files = entries.filter((e) => e.type === "file" && e.name.endsWith(".md"));
      const folders = entries.filter((e) => e.type === "directory");

      const statsPromises = files.map(async (f) => {
        const stat = await services.fs.stat(f.path);
        return { path: f.path, size: stat.size, mtime: stat.mtime };
      });
      const stats = await Promise.all(statsPromises);

      const totalSize = stats.reduce((sum, s) => sum + s.size, 0);
      const recent = stats
        .sort((a, b) => b.mtime.getTime() - a.mtime.getTime())
        .slice(0, 10);

      const text = [
        `Notes: ${files.length}`,
        `Folders: ${folders.length}`,
        `Total size: ${(totalSize / 1024).toFixed(1)} KB`,
        "",
        "Recently modified:",
        ...recent.map(
          (r) => `  ${r.path} (${r.mtime.toISOString().split("T")[0]})`
        ),
      ].join("\n");

      return { content: [{ type: "text" as const, text }] };
    }
  );
}
