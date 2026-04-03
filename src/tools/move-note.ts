import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import * as z from "zod/v4";
import type { Services } from "../server.js";

export function registerMoveNote(server: McpServer, services: Services) {
  server.registerTool(
    "move_note",
    {
      description: "Move or rename a note within the vault.",
      inputSchema: {
        oldPath: z.string().describe("Current relative path of the note"),
        newPath: z.string().describe("New relative path for the note"),
      },
    },
    async ({ oldPath, newPath }) => {
      await services.fs.moveFile(oldPath, newPath);
      return {
        content: [{ type: "text" as const, text: `Moved ${oldPath} -> ${newPath}` }],
      };
    }
  );
}
