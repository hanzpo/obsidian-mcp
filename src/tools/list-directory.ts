import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import * as z from "zod/v4";
import type { Services } from "../server.js";
import { DIRECTORY_PATH_DESCRIPTION } from "./descriptions.js";

export function registerListDirectory(server: McpServer, services: Services) {
  server.registerTool(
    "list_directory",
    {
      description:
        "List files and folders reachable through this MCP server. Empty path means the MCP root: the single vault root in single-vault mode, or the top-level mounted vault aliases in desktop-mounted mode.",
      inputSchema: {
        path: z
          .string()
          .optional()
          .default("")
          .describe(DIRECTORY_PATH_DESCRIPTION),
        recursive: z
          .boolean()
          .optional()
          .default(false)
          .describe("Set true to walk subdirectories recursively"),
      },
      annotations: { readOnlyHint: true, openWorldHint: false },
    },
    async ({ path, recursive }) => {
      const entries = await services.fs.listDirectory(path, recursive);
      const text = entries
        .map((e) => `[${e.type === "directory" ? "dir" : "file"}] ${e.path}`)
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
