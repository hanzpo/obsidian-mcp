import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import * as z from "zod/v4";
import { invalidateDerivedCaches, type Services } from "../server.js";
import { NOTE_PATH_DESCRIPTION } from "./descriptions.js";

export function registerCreateNote(server: McpServer, services: Services) {
  server.registerTool(
    "create_note",
    {
      description:
        "Create a markdown note and any missing parent folders. Optionally writes YAML frontmatter before the note body.",
      inputSchema: {
        path: z.string().describe(NOTE_PATH_DESCRIPTION),
        content: z.string().describe("Markdown content of the note"),
        frontmatter: z
          .record(z.string(), z.unknown())
          .optional()
          .describe("Optional YAML frontmatter as key-value pairs"),
        overwrite: z
          .boolean()
          .optional()
          .default(false)
          .describe("Set true to replace an existing note at the same path"),
      },
    },
    async ({ path, content, frontmatter, overwrite }) => {
      if (!overwrite && (await services.fs.exists(path))) {
        return {
          content: [{ type: "text" as const, text: `Error: Note already exists at ${path}. Use overwrite: true to replace.` }],
          isError: true,
        };
      }

      let body = content;
      if (frontmatter && Object.keys(frontmatter).length > 0) {
        body = services.frontmatter.stringify(content, frontmatter as Record<string, unknown>);
      }

      await services.fs.writeFile(path, body);
      invalidateDerivedCaches(services);
      return {
        content: [{ type: "text" as const, text: `Created note at ${path}` }],
      };
    }
  );
}
