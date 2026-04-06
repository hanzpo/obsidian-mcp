import fs from "node:fs/promises";
import path from "node:path";
import type { VaultConfig } from "../config.js";
import { isPathAllowed } from "./path-filter.js";

interface ResolvedTarget {
  fullPath: string;
  rootPath: string;
}

export interface DirectoryEntry {
  name: string;
  type: "file" | "directory";
  path: string;
}

export class FileSystemService {
  constructor(private vaults: VaultConfig) {}

  private normalizePath(relativePath: string): string {
    if (!relativePath || relativePath === ".") return "";
    return relativePath.replace(/\\/g, "/").replace(/^\/+/, "").replace(/\/+$/, "");
  }

  resolvePath(relativePath: string): string {
    return this.resolveTarget(relativePath).fullPath;
  }

  private resolveSinglePath(
    rootPath: string,
    relativePath: string
  ): ResolvedTarget {
    const normalized = this.normalizePath(relativePath);
    const resolved = path.resolve(rootPath, normalized || ".");
    const rel = path.relative(rootPath, resolved);
    if (rel.startsWith("..") || path.isAbsolute(rel)) {
      throw new Error("Path traversal not allowed");
    }
    if (rel !== "" && !isPathAllowed(rel)) {
      throw new Error(`Access denied: ${rel}`);
    }
    return { fullPath: resolved, rootPath };
  }

  private getMountRoot(relativePath: string): { mountName: string; mountPath: string; innerPath: string } {
    const normalized = this.normalizePath(relativePath);
    if (!normalized) {
      throw new Error("Path must include a vault name");
    }

    const [mountName, ...rest] = normalized.split("/");
    const mountPath = this.vaults.mode === "mounted" ? this.vaults.mounts[mountName] : undefined;
    if (!mountPath) {
      throw new Error(`Unknown vault: ${mountName}`);
    }

    return {
      mountName,
      mountPath,
      innerPath: rest.join("/"),
    };
  }

  private resolveTarget(relativePath: string): ResolvedTarget {
    if (this.vaults.mode === "single") {
      return this.resolveSinglePath(this.vaults.rootPath, relativePath);
    }

    const { mountPath, innerPath } = this.getMountRoot(relativePath);
    return this.resolveSinglePath(mountPath, innerPath);
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
    const source = this.resolveTarget(oldPath);
    const destination = this.resolveTarget(newPath);
    await fs.mkdir(path.dirname(destination.fullPath), { recursive: true });

    if (source.rootPath === destination.rootPath) {
      await fs.rename(source.fullPath, destination.fullPath);
      return;
    }

    await fs.copyFile(source.fullPath, destination.fullPath);
    await fs.unlink(source.fullPath);
  }

  async listDirectory(
    relativePath: string,
    recursive: boolean
  ): Promise<DirectoryEntry[]> {
    if (this.vaults.mode === "single") {
      const normalized = this.normalizePath(relativePath);
      const full = this.resolvePath(normalized || ".");
      return this.walkDir(full, normalized, recursive, this.vaults.rootPath);
    }

    const normalized = this.normalizePath(relativePath);
    if (!normalized) {
      const mounts: DirectoryEntry[] = Object.keys(this.vaults.mounts)
        .sort()
        .map((mountName) => ({
          name: mountName,
          type: "directory" as const,
          path: mountName,
        }));

      if (!recursive) {
        return mounts;
      }

      const nestedEntries = await Promise.all(
        Object.entries(this.vaults.mounts).map(async ([mountName, mountPath]) =>
          this.walkDir(mountPath, mountName, true, mountPath)
        )
      );

      return mounts.concat(nestedEntries.flat());
    }

    const { mountName, mountPath, innerPath } = this.getMountRoot(normalized);
    const full = this.resolvePath(normalized);
    const displayPrefix = innerPath ? normalized : mountName;
    return this.walkDir(full, displayPrefix, recursive, mountPath);
  }

  private async walkDir(
    absDir: string,
    relDir: string,
    recursive: boolean,
    rootPath: string
  ): Promise<DirectoryEntry[]> {
    const entries = await fs.readdir(absDir, { withFileTypes: true });
    const results: DirectoryEntry[] = [];

    for (const entry of entries) {
      const entryRel = relDir ? `${relDir}/${entry.name}` : entry.name;
      const actualRel = path.relative(rootPath, path.join(absDir, entry.name));
      if (!isPathAllowed(actualRel.replace(/\\/g, "/"))) continue;

      if (entry.isDirectory()) {
        results.push({ name: entry.name, type: "directory", path: entryRel });
        if (recursive) {
          const children = await this.walkDir(
            path.join(absDir, entry.name),
            entryRel,
            true,
            rootPath
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
