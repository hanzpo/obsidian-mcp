import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import * as z from "zod/v4";
import { invalidateDerivedCaches, type Services } from "../server.js";

export function registerManageTags(server: McpServer, services: Services) {
  server.registerTool(
    "manage_tags",
    {
      description:
        "Add, remove, or list tags on a note. Tags are stored in YAML frontmatter.",
      inputSchema: {
        path: z.string().describe("Relative path to the note"),
        action: z
          .enum(["add", "remove", "list"])
          .describe("Tag operation to perform"),
        tags: z
          .array(z.string())
          .optional()
          .describe("Tags to add or remove (not needed for list)"),
      },
    },
    async ({ path, action, tags: inputTags }) => {
      const raw = await services.fs.readFile(path);
      const currentTags = services.frontmatter.getTags(raw);

      if (action === "list") {
        return {
          content: [
            {
              type: "text" as const,
              text: currentTags.length > 0
                ? `Tags: ${currentTags.join(", ")}`
                : "No tags",
            },
          ],
        };
      }

      const normalizedInput = (inputTags || []).map((t) =>
        t.startsWith("#") ? t.slice(1) : t
      );

      let newTags: string[];
      if (action === "add") {
        const tagSet = new Set(currentTags);
        for (const t of normalizedInput) tagSet.add(t);
        newTags = Array.from(tagSet);
      } else {
        const removeSet = new Set(normalizedInput);
        newTags = currentTags.filter((t) => !removeSet.has(t));
      }

      const updated = services.frontmatter.setTags(raw, newTags);
      await services.fs.writeFile(path, updated);
      invalidateDerivedCaches(services);

      return {
        content: [
          {
            type: "text" as const,
            text: `Tags updated: ${newTags.join(", ") || "(none)"}`,
          },
        ],
      };
    }
  );
}
