const EXCLUDED_SEGMENTS = new Set([".obsidian", ".git", ".trash"]);

export function isPathAllowed(relativePath: string): boolean {
  const segments = relativePath.split("/");
  return segments.every(
    (seg) => seg !== "" && !seg.startsWith(".") && !EXCLUDED_SEGMENTS.has(seg)
  );
}
