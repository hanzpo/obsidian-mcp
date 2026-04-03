export function isPathAllowed(relativePath: string): boolean {
  const segments = relativePath.split("/");
  return segments.every((seg) => seg !== "" && !seg.startsWith("."));
}
