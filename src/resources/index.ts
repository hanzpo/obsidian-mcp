import { McpServer, ResourceTemplate } from "@modelcontextprotocol/sdk/server/mcp.js";
import type { Services } from "../server.js";

export function registerAllResources(server: McpServer, services: Services) {
  server.registerResource(
    "note",
    new ResourceTemplate("obsidian://note/{+path}", {
      list: async () => {
        const files = await services.fs.getAllMarkdownFiles();
        return {
          resources: files.map((f) => ({
            uri: `obsidian://note/${f}`,
            name: f,
            mimeType: "text/markdown",
          })),
        };
      },
    }),
    {
      description: "A markdown note in the Obsidian vault",
      mimeType: "text/markdown",
    },
    async (uri, variables) => {
      const path = variables.path as string;
      const content = await services.fs.readFile(path);
      return {
        contents: [
          {
            uri: uri.href,
            mimeType: "text/markdown",
            text: content,
          },
        ],
      };
    }
  );
}
