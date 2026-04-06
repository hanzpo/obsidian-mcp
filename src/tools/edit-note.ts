import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import * as z from "zod/v4";
import { invalidateDerivedCaches, type Services } from "../server.js";
import { NOTE_PATH_DESCRIPTION } from "./descriptions.js";

export function registerEditNote(server: McpServer, services: Services) {
  server.registerTool(
    "edit_note",
    {
      description:
        "Edit an existing note. append adds a newline plus content at the end, prepend inserts content before the body but after frontmatter, and replace swaps the first occurrence of oldContent.",
      inputSchema: {
        path: z.string().describe(NOTE_PATH_DESCRIPTION),
        operation: z
          .enum(["append", "prepend", "replace"])
          .describe("Type of edit operation"),
        content: z.string().describe("Content to insert or replace with"),
        oldContent: z
          .string()
          .optional()
          .describe("Exact text to find for replace; required only when operation is replace"),
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
