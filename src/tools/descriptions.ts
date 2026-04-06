export const PATH_MODEL_GUIDANCE =
  "Paths are MCP-relative, not absolute. In single-vault mode, use paths like 'Projects/alpha.md'. In mounted desktop mode, call list_directory with an empty path to see top-level vault aliases, then prefix paths with one of those aliases, for example 'work/Projects/alpha.md'.";

export const NOTE_PATH_DESCRIPTION = `Path to the note. ${PATH_MODEL_GUIDANCE}`;

export const DIRECTORY_PATH_DESCRIPTION =
  "Folder to list. Empty path lists the MCP root: the single vault root in single-vault mode, or the top-level mounted vault aliases in mounted mode. In mounted mode, pass a vault alias like 'work' or a subfolder like 'work/Projects'.";

export const SEARCH_SCOPE_DESCRIPTION =
  "Optional folder scope. In single-vault mode, use a folder like 'Projects'. In mounted mode, use a vault alias like 'work' or a subfolder like 'work/Projects'.";

export const SOURCE_NOTE_PATH_DESCRIPTION = `Current ${NOTE_PATH_DESCRIPTION.toLowerCase()}`;

export const DESTINATION_NOTE_PATH_DESCRIPTION = `Destination ${NOTE_PATH_DESCRIPTION.toLowerCase()}`;
