import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import * as z from "zod/v4";
import type { Services } from "../server.js";
import { SEARCH_SCOPE_DESCRIPTION } from "./descriptions.js";

export function registerSearchNotes(server: McpServer, services: Services) {
  server.registerTool(
    "search_notes",
    {
      description:
        "Full-text search across accessible markdown notes using AND term matching and BM25-style ranking.",
      inputSchema: {
        query: z
          .string()
          .describe("Search terms. All terms must appear somewhere in the note."),
        path: z
          .string()
          .optional()
          .describe(SEARCH_SCOPE_DESCRIPTION),
        maxResults: z
          .number()
          .optional()
          .default(20)
          .describe("Maximum results to return. Values above 50 are capped at 50."),
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
