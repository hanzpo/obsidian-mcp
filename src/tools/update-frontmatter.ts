import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import * as z from "zod/v4";
import type { Services } from "../server.js";

export function registerUpdateFrontmatter(server: McpServer, services: Services) {
  server.registerTool(
    "update_frontmatter",
    {
      description:
        "Update YAML frontmatter fields on a note. Merges updates and optionally removes keys.",
      inputSchema: {
        path: z.string().describe("Relative path to the note"),
        updates: z
          .record(z.string(), z.unknown())
          .describe("Key-value pairs to merge into frontmatter"),
        removeKeys: z
          .array(z.string())
          .optional()
          .describe("Keys to remove from frontmatter"),
      },
    },
    async ({ path, updates, removeKeys }) => {
      const raw = await services.fs.readFile(path);
      const updated = services.frontmatter.update(
        raw,
        updates as Record<string, unknown>,
        removeKeys
      );
      await services.fs.writeFile(path, updated);

      const newData = services.frontmatter.parse(updated).data;
      return {
        content: [
          {
            type: "text" as const,
            text: `Updated frontmatter for ${path}:\n${JSON.stringify(newData, null, 2)}`,
          },
        ],
      };
    }
  );
}
