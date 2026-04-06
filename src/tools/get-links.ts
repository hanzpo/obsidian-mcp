import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import * as z from "zod/v4";
import type { Services } from "../server.js";
import { NOTE_PATH_DESCRIPTION } from "./descriptions.js";

export function registerGetLinks(server: McpServer, services: Services) {
  server.registerTool(
    "get_links",
    {
      description:
        "Return outgoing [[wikilinks]] from one note plus backlinks from other accessible notes. Link matching is note-based across the accessible vault set and ignores headings and block refs when resolving targets.",
      inputSchema: {
        path: z.string().describe(NOTE_PATH_DESCRIPTION),
      },
      annotations: { readOnlyHint: true, openWorldHint: false },
    },
    async ({ path }) => {
      const content = await services.fs.readFile(path);
      const outgoing = await services.wikilinks.resolveLinks(content, path);
      const backlinks = await services.wikilinks.findBacklinks(path);

      const outText = outgoing.length > 0
        ? outgoing
            .map(
              (l) =>
                `  ${l.target} -> ${l.resolved ? l.resolvedPath : "(unresolved)"}`
            )
            .join("\n")
        : "  (none)";

      const backText = backlinks.length > 0
        ? backlinks
            .map((b) => `  ${b.source}${b.context ? `: ${b.context}` : ""}`)
            .join("\n")
        : "  (none)";

      return {
        content: [
          {
            type: "text" as const,
            text: `Outgoing links:\n${outText}\n\nBacklinks:\n${backText}`,
          },
        ],
      };
    }
  );
}
