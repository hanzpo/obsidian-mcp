import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import * as z from "zod/v4";
import type { Services } from "../server.js";
import { NOTE_PATH_DESCRIPTION } from "./descriptions.js";

export function registerGetFrontmatter(server: McpServer, services: Services) {
  server.registerTool(
    "get_frontmatter",
    {
      description:
        "Parse a note's YAML frontmatter and return it as pretty-printed JSON. Returns {} when no frontmatter is present.",
      inputSchema: {
        path: z.string().describe(NOTE_PATH_DESCRIPTION),
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
