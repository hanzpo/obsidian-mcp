import path from "node:path";
import { FileSystemService } from "./filesystem.js";

export interface LinkInfo {
  target: string;
  resolved: boolean;
  resolvedPath?: string;
}

interface FileIndex {
  byBasename: Map<string, string[]>;
  byNormalizedPath: Map<string, string>;
}

const WIKILINK_RE = /\[\[([^\]|]+)(?:\|[^\]]+)?\]\]/g;
const CACHE_TTL_MS = 30_000;

export class WikilinkService {
  private fs: FileSystemService;
  private fileCache: string[] | null = null;
  private cacheTime = 0;

  constructor(vaultPath: string) {
    this.fs = new FileSystemService(vaultPath);
  }

  invalidateCache(): void {
    this.fileCache = null;
    this.cacheTime = 0;
  }

  private async getFiles(): Promise<string[]> {
    const now = Date.now();
    if (this.fileCache && now - this.cacheTime < CACHE_TTL_MS) {
      return this.fileCache;
    }
    this.fileCache = await this.fs.getAllMarkdownFiles();
    this.cacheTime = now;
    return this.fileCache;
  }

  parseLinks(content: string): string[] {
    const targets: string[] = [];
    let match: RegExpExecArray | null;
    const re = new RegExp(WIKILINK_RE.source, WIKILINK_RE.flags);
    while ((match = re.exec(content)) !== null) {
      targets.push(match[1].trim());
    }
    return targets;
  }

  async resolveLinks(content: string, sourcePath?: string): Promise<LinkInfo[]> {
    const targets = this.parseLinks(content);
    const allFiles = await this.getFiles();
    const index = this.buildIndex(allFiles);

    return targets.map((target) => {
      const resolvedPath = this.resolveTarget(target, sourcePath, index);
      if (resolvedPath) {
        return {
          target,
          resolved: true,
          resolvedPath,
        };
      }
      return { target, resolved: false };
    });
  }

  async findBacklinks(notePath: string): Promise<{ source: string; context: string }[]> {
    const allFiles = await this.getFiles();
    const index = this.buildIndex(allFiles);
    const normalizedNotePath = this.normalizeNotePath(notePath);
    const backlinks: { source: string; context: string }[] = [];

    for (const file of allFiles) {
      if (file === notePath) continue;
      try {
        const content = await this.fs.readFile(file);
        const lines = content.split("\n");
        const contextLine = lines.find((line) =>
          this.parseLinks(line).some(
            (target) =>
              this.normalizeResolvedPath(this.resolveTarget(target, file, index)) ===
              normalizedNotePath
          )
        );

        if (contextLine) {
          backlinks.push({
            source: file,
            context: contextLine.trim(),
          });
        }
      } catch {
        // Skip unreadable files
      }
    }

    return backlinks;
  }

  private buildIndex(files: string[]): FileIndex {
    const byBasename = new Map<string, string[]>();
    const byNormalizedPath = new Map<string, string>();

    for (const file of files) {
      const normalizedPath = this.normalizeNotePath(file);
      const basename = path.posix.basename(normalizedPath);
      const existing = byBasename.get(basename) || [];
      existing.push(file);
      byBasename.set(basename, existing);
      byNormalizedPath.set(normalizedPath, file);
    }

    return { byBasename, byNormalizedPath };
  }

  private resolveTarget(
    target: string,
    sourcePath: string | undefined,
    index: FileIndex
  ): string | undefined {
    const normalizedTarget = this.normalizeTarget(target);
    if (!normalizedTarget) return undefined;

    if (normalizedTarget.includes("/")) {
      return index.byNormalizedPath.get(normalizedTarget);
    }

    const basename = path.posix.basename(normalizedTarget);
    const candidates = index.byBasename.get(basename);
    if (!candidates || candidates.length === 0) {
      return undefined;
    }

    if (candidates.length === 1) {
      return candidates[0];
    }

    if (!sourcePath) {
      return undefined;
    }

    const sourceDir = path.posix.dirname(this.toPosixPath(sourcePath));
    return candidates.find((candidate) => path.posix.dirname(candidate) === sourceDir);
  }

  private normalizeTarget(target: string): string {
    const withoutHeading = target.split("#", 1)[0];
    const withoutBlock = withoutHeading.split("^", 1)[0];
    const posixPath = this.toPosixPath(withoutBlock)
      .replace(/^\/+/, "")
      .replace(/\.md$/i, "");
    return posixPath.toLowerCase();
  }

  private normalizeNotePath(notePath: string): string {
    return this.toPosixPath(notePath).replace(/\.md$/i, "").toLowerCase();
  }

  private normalizeResolvedPath(notePath: string | undefined): string | undefined {
    return notePath ? this.normalizeNotePath(notePath) : undefined;
  }

  private toPosixPath(notePath: string): string {
    return notePath.replace(/\\/g, "/");
  }
}
