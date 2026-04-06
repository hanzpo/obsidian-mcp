import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import * as z from "zod/v4";
import { invalidateDerivedCaches, type Services } from "../server.js";

export function registerEditNote(server: McpServer, services: Services) {
  server.registerTool(
    "edit_note",
    {
      description:
        "Edit an existing note. Supports append, prepend, or find-and-replace operations.",
      inputSchema: {
        path: z.string().describe("Relative path to the note"),
        operation: z
          .enum(["append", "prepend", "replace"])
          .describe("Type of edit operation"),
        content: z.string().describe("Content to insert or replace with"),
        oldContent: z
          .string()
          .optional()
          .describe("Text to find (required for replace operation)"),
      },
    },
    async ({ path, operation, content, oldContent }) => {
      const existing = await services.fs.readFile(path);

      let updated: string;
      switch (operation) {
        case "append":
          updated = existing + "\n" + content;
          break;
        case "prepend": {
          const parsed = services.frontmatter.parse(existing);
          if (Object.keys(parsed.data).length > 0) {
            updated = services.frontmatter.stringify(
              content + "\n" + parsed.content,
              parsed.data
            );
          } else {
            updated = content + "\n" + existing;
          }
          break;
        }
        case "replace":
          if (!oldContent) {
            return {
              content: [{ type: "text" as const, text: "Error: oldContent is required for replace operation" }],
              isError: true,
            };
          }
          if (!existing.includes(oldContent)) {
            return {
              content: [{ type: "text" as const, text: "Error: oldContent not found in note" }],
              isError: true,
            };
          }
          updated = existing.replace(oldContent, content);
          break;
      }

      await services.fs.writeFile(path, updated);
      invalidateDerivedCaches(services);
      return {
        content: [{ type: "text" as const, text: `Updated ${path} (${operation})` }],
      };
    }
  );
}
