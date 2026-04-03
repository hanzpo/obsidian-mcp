import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import * as z from "zod/v4";
import type { Services } from "../server.js";

export function registerGetFrontmatter(server: McpServer, services: Services) {
  server.registerTool(
    "get_frontmatter",
    {
      description: "Read the YAML frontmatter of a note as JSON.",
      inputSchema: {
        path: z.string().describe("Relative path to the note"),
      },
      annotations: { readOnlyHint: true, openWorldHint: false },
    },
    async ({ path }) => {
      const raw = await services.fs.readFile(path);
      const parsed = services.frontmatter.parse(raw);
      return {
        content: [
          {
            type: "text" as const,
            text: JSON.stringify(parsed.data, null, 2),
          },
        ],
      };
    }
  );
}
