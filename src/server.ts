import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import type { Config } from "./config.js";
import { FileSystemService } from "./services/filesystem.js";
import { FrontmatterService } from "./services/frontmatter.js";
import { SearchService } from "./services/search.js";
import { WikilinkService } from "./services/wikilinks.js";
import { registerAllResources } from "./resources/index.js";
import { registerAllTools } from "./tools/index.js";

export interface Services {
  fs: FileSystemService;
  frontmatter: FrontmatterService;
  search: SearchService;
  wikilinks: WikilinkService;
}

export function createServices(config: Config): Services {
  return {
    fs: new FileSystemService(config.vaults),
    frontmatter: new FrontmatterService(),
    search: new SearchService(config.vaults),
    wikilinks: new WikilinkService(config.vaults),
  };
}

export function invalidateDerivedCaches(services: Services): void {
  services.search.invalidateCache();
  services.wikilinks.invalidateCache();
}

export function createMcpServer(services: Services): McpServer {
  const server = new McpServer({
    name: "obsidian-mcp",
    version: "0.1.0",
  });

  registerAllResources(server, services);
  registerAllTools(server, services);

  return server;
}
