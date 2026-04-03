import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import * as z from "zod/v4";
import type { Services } from "../server.js";

export function registerListDirectory(server: McpServer, services: Services) {
  server.registerTool(
    "list_directory",
    {
      description:
        "List files and folders in the vault. Defaults to vault root.",
      inputSchema: {
        path: z
          .string()
          .optional()
          .default("")
          .describe("Relative path to list (empty for vault root)"),
        recursive: z
          .boolean()
          .optional()
          .default(false)
          .describe("Include subdirectories recursively"),
      },
      annotations: { readOnlyHint: true, openWorldHint: false },
    },
    async ({ path, recursive }) => {
      const entries = await services.fs.listDirectory(path, recursive);
      const text = entries
        .map((e) => `${e.type === "directory" ? "📁" : "📄"} ${e.path}`)
        .join("\n");
      return {
        content: [
          {
            type: "text" as const,
            text: text || "(empty directory)",
          },
        ],
      };
    }
  );
}
