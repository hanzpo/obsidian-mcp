import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import * as z from "zod/v4";
import type { Services } from "../server.js";

export function registerDeleteNote(server: McpServer, services: Services) {
  server.registerTool(
    "delete_note",
    {
      description: "Delete a note from the vault. Requires explicit confirmation.",
      inputSchema: {
        path: z.string().describe("Relative path to the note to delete"),
        confirm: z
          .boolean()
          .describe("Must be true to confirm deletion"),
      },
      annotations: { destructiveHint: true },
    },
    async ({ path, confirm }) => {
      if (!confirm) {
        return {
          content: [{ type: "text" as const, text: "Error: Must set confirm: true to delete" }],
          isError: true,
        };
      }
      await services.fs.deleteFile(path);
      return {
        content: [{ type: "text" as const, text: `Deleted ${path}` }],
      };
    }
  );
}
