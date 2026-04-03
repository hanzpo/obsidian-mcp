import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import type { Services } from "../server.js";
import { registerReadNote } from "./read-note.js";
import { registerReadNotes } from "./read-notes.js";
import { registerCreateNote } from "./create-note.js";
import { registerEditNote } from "./edit-note.js";
import { registerDeleteNote } from "./delete-note.js";
import { registerMoveNote } from "./move-note.js";
import { registerListDirectory } from "./list-directory.js";
import { registerSearchNotes } from "./search-notes.js";
import { registerGetFrontmatter } from "./get-frontmatter.js";
import { registerUpdateFrontmatter } from "./update-frontmatter.js";
import { registerManageTags } from "./manage-tags.js";
import { registerGetVaultStats } from "./get-vault-stats.js";
import { registerGetLinks } from "./get-links.js";

export function registerAllTools(server: McpServer, services: Services) {
  registerReadNote(server, services);
  registerReadNotes(server, services);
  registerCreateNote(server, services);
  registerEditNote(server, services);
  registerDeleteNote(server, services);
  registerMoveNote(server, services);
  registerListDirectory(server, services);
  registerSearchNotes(server, services);
  registerGetFrontmatter(server, services);
  registerUpdateFrontmatter(server, services);
  registerManageTags(server, services);
  registerGetVaultStats(server, services);
  registerGetLinks(server, services);
}
