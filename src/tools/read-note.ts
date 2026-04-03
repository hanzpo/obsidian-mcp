import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import * as z from "zod/v4";
import type { Services } from "../server.js";

export function registerReadNote(server: McpServer, services: Services) {
  server.registerTool(
    "read_note",
    {
      description:
        "Read the full content of a note in the vault. Returns the raw markdown including frontmatter.",
      inputSchema: {
        path: z.string().describe("Relative path to the note (e.g. 'Projects/my-project.md')"),
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
