import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import * as z from "zod/v4";
import { invalidateDerivedCaches, type Services } from "../server.js";
import { NOTE_PATH_DESCRIPTION } from "./descriptions.js";

export function registerDeleteNote(server: McpServer, services: Services) {
  server.registerTool(
    "delete_note",
    {
      description:
        "Delete a note permanently. Requires confirm: true so agents do not remove files accidentally.",
      inputSchema: {
        path: z.string().describe(NOTE_PATH_DESCRIPTION),
        confirm: z
          .boolean()
          .describe("Must be true or the delete is rejected"),
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
      invalidateDerivedCaches(services);
      return {
        content: [{ type: "text" as const, text: `Deleted ${path}` }],
      };
    }
  );
}
