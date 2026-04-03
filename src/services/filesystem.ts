import fs from "node:fs/promises";
import path from "node:path";
import { isPathAllowed } from "./path-filter.js";

export class FileSystemService {
  constructor(private vaultPath: string) {}

  resolvePath(relativePath: string): string {
    const resolved = path.resolve(this.vaultPath, relativePath);
    const rel = path.relative(this.vaultPath, resolved);
    if (rel.startsWith("..") || path.isAbsolute(rel)) {
      throw new Error("Path traversal not allowed");
    }
    // Allow vault root (empty relative path)
    if (rel !== "" && !isPathAllowed(rel)) {
      throw new Error(`Access denied: ${rel}`);
    }
    return resolved;
  }

  async readFile(relativePath: string): Promise<string> {
    const full = this.resolvePath(relativePath);
    return fs.readFile(full, "utf-8");
  }

  async writeFile(relativePath: string, content: string): Promise<void> {
    const full = this.resolvePath(relativePath);
    await fs.mkdir(path.dirname(full), { recursive: true });
    await fs.writeFile(full, content, "utf-8");
  }

  async exists(relativePath: string): Promise<boolean> {
    try {
      const full = this.resolvePath(relativePath);
      await fs.access(full);
      return true;
    } catch {
      return false;
    }
  }

  async stat(relativePath: string) {
    const full = this.resolvePath(relativePath);
    return fs.stat(full);
  }

  async deleteFile(relativePath: string): Promise<void> {
    const full = this.resolvePath(relativePath);
    await fs.unlink(full);
  }

  async moveFile(oldPath: string, newPath: string): Promise<void> {
    const fullOld = this.resolvePath(oldPath);
    const fullNew = this.resolvePath(newPath);
    await fs.mkdir(path.dirname(fullNew), { recursive: true });
    await fs.rename(fullOld, fullNew);
  }

  async listDirectory(
    relativePath: string,
    recursive: boolean
  ): Promise<{ name: string; type: "file" | "directory"; path: string }[]> {
    const full = this.resolvePath(relativePath || ".");
    return this.walkDir(full, relativePath || "", recursive);
  }

  private async walkDir(
    absDir: string,
    relDir: string,
    recursive: boolean
  ): Promise<{ name: string; type: "file" | "directory"; path: string }[]> {
    const entries = await fs.readdir(absDir, { withFileTypes: true });
    const results: { name: string; type: "file" | "directory"; path: string }[] = [];

    for (const entry of entries) {
      const entryRel = relDir ? `${relDir}/${entry.name}` : entry.name;
      if (!isPathAllowed(entryRel)) continue;

      if (entry.isDirectory()) {
        results.push({ name: entry.name, type: "directory", path: entryRel });
        if (recursive) {
          const children = await this.walkDir(
            path.join(absDir, entry.name),
            entryRel,
            true
          );
          results.push(...children);
        }
      } else if (entry.isFile()) {
        results.push({ name: entry.name, type: "file", path: entryRel });
      }
    }

    return results;
  }

  async getAllMarkdownFiles(): Promise<string[]> {
    const entries = await this.listDirectory("", true);
    return entries
      .filter((e) => e.type === "file" && e.name.endsWith(".md"))
      .map((e) => e.path);
  }
}
