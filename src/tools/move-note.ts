import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import * as z from "zod/v4";
import { invalidateDerivedCaches, type Services } from "../server.js";
import {
  DESTINATION_NOTE_PATH_DESCRIPTION,
  SOURCE_NOTE_PATH_DESCRIPTION,
} from "./descriptions.js";

export function registerMoveNote(server: McpServer, services: Services) {
  server.registerTool(
    "move_note",
    {
      description:
        "Move or rename a note. In mounted mode, this can also move a file between vault aliases by copying it to the new location and deleting the original.",
      inputSchema: {
        oldPath: z.string().describe(SOURCE_NOTE_PATH_DESCRIPTION),
        newPath: z.string().describe(DESTINATION_NOTE_PATH_DESCRIPTION),
      },
    },
    async ({ oldPath, newPath }) => {
      await services.fs.moveFile(oldPath, newPath);
      invalidateDerivedCaches(services);
      return {
        content: [{ type: "text" as const, text: `Moved ${oldPath} -> ${newPath}` }],
      };
    }
  );
}
