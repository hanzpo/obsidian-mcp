import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import * as z from "zod/v4";
import type { Services } from "../server.js";

export function registerSearchNotes(server: McpServer, services: Services) {
  server.registerTool(
    "search_notes",
    {
      description:
        "Full-text search across all notes in the vault. Returns results ranked by relevance (BM25).",
      inputSchema: {
        query: z.string().describe("Search query (multiple terms use AND logic)"),
        path: z
          .string()
          .optional()
          .describe("Scope search to a subfolder"),
        maxResults: z
          .number()
          .optional()
          .default(20)
          .describe("Maximum results to return (max 50)"),
      },
      annotations: { readOnlyHint: true, openWorldHint: false },
    },
    async ({ query, path, maxResults }) => {
      const results = await services.search.search(query, path, maxResults);
      if (results.length === 0) {
        return {
          content: [{ type: "text" as const, text: "No results found." }],
        };
      }

      const text = results
        .map(
          (r, i) =>
            `${i + 1}. **${r.path}** (score: ${r.score.toFixed(2)})\n   ${r.excerpt}`
        )
        .join("\n\n");

      return {
        content: [{ type: "text" as const, text: `Found ${results.length} results:\n\n${text}` }],
      };
    }
  );
}
