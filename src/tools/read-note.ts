import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import * as z from "zod/v4";
import type { Services } from "../server.js";
import { NOTE_PATH_DESCRIPTION } from "./descriptions.js";

export function registerReadNote(server: McpServer, services: Services) {
  server.registerTool(
    "read_note",
    {
      description:
        "Read one note and return its raw markdown, including frontmatter, followed by size and modified time metadata.",
      inputSchema: {
        path: z.string().describe(NOTE_PATH_DESCRIPTION),
      },
      annotations: { readOnlyHint: true, openWorldHint: false },
    },
    async ({ path }) => {
      const content = await services.fs.readFile(path);
      const stat = await services.fs.stat(path);
      return {
        content: [
          {
            type: "text" as const,
            text: content,
          },
          {
            type: "text" as const,
            text: `\n---\nSize: ${stat.size} bytes | Modified: ${stat.mtime.toISOString()}`,
          },
        ],
      };
    }
  );
}
