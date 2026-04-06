import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import * as z from "zod/v4";
import { invalidateDerivedCaches, type Services } from "../server.js";
import { NOTE_PATH_DESCRIPTION } from "./descriptions.js";

export function registerUpdateFrontmatter(server: McpServer, services: Services) {
  server.registerTool(
    "update_frontmatter",
    {
      description:
        "Merge key-value updates into a note's YAML frontmatter and optionally remove keys. Creates or rewrites the frontmatter block as needed.",
      inputSchema: {
        path: z.string().describe(NOTE_PATH_DESCRIPTION),
        updates: z
          .record(z.string(), z.unknown())
          .describe("Key-value pairs to merge into frontmatter"),
        removeKeys: z
          .array(z.string())
          .optional()
          .describe("Frontmatter keys to remove after merging updates"),
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
      invalidateDerivedCaches(services);

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
