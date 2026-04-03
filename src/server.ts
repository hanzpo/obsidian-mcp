import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import type { Config } from "./config.js";
import { FileSystemService } from "./services/filesystem.js";
import { FrontmatterService } from "./services/frontmatter.js";
import { SearchService } from "./services/search.js";
import { WikilinkService } from "./services/wikilinks.js";
import { registerAllTools } from "./tools/index.js";

export interface Services {
  fs: FileSystemService;
  frontmatter: FrontmatterService;
  search: SearchService;
  wikilinks: WikilinkService;
}

export function createMcpServer(config: Config): McpServer {
  const server = new McpServer({
    name: "obsidian-mcp",
    version: "0.1.0",
  });

  const services: Services = {
    fs: new FileSystemService(config.vaultPath),
    frontmatter: new FrontmatterService(),
    search: new SearchService(config.vaultPath),
    wikilinks: new WikilinkService(config.vaultPath),
  };

  registerAllTools(server, services);

  return server;
}
