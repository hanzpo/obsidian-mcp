import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import * as z from "zod/v4";
import type { Services } from "../server.js";

export function registerReadNotes(server: McpServer, services: Services) {
  server.registerTool(
    "read_notes",
    {
      description: "Read multiple notes at once (up to 10). Returns content for each.",
      inputSchema: {
        paths: z
          .array(z.string())
          .max(10)
          .describe("Array of relative paths to notes"),
      },
      annotations: { readOnlyHint: true, openWorldHint: false },
    },
    async ({ paths }) => {
      const results = await Promise.allSettled(
        paths.map(async (p) => {
          const content = await services.fs.readFile(p);
          return { path: p, content };
        })
      );

      const text = results
        .map((r, i) => {
          if (r.status === "fulfilled") {
            return `## ${r.value.path}\n\n${r.value.content}`;
          }
          return `## ${paths[i]}\n\nError: ${(r.reason as Error).message}`;
        })
        .join("\n\n---\n\n");

      return { content: [{ type: "text" as const, text }] };
    }
  );
}
