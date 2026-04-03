import path from "node:path";
import { FileSystemService } from "./filesystem.js";

export interface LinkInfo {
  target: string;
  resolved: boolean;
  resolvedPath?: string;
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

  async resolveLinks(content: string): Promise<LinkInfo[]> {
    const targets = this.parseLinks(content);
    const allFiles = await this.getFiles();

    const basenameMap = new Map<string, string[]>();
    for (const file of allFiles) {
      const base = path.basename(file, ".md").toLowerCase();
      const existing = basenameMap.get(base) || [];
      existing.push(file);
      basenameMap.set(base, existing);
    }

    return targets.map((target) => {
      const normalizedTarget = target.toLowerCase().replace(/\.md$/, "");
      const candidates = basenameMap.get(normalizedTarget);
      if (candidates && candidates.length > 0) {
        return {
          target,
          resolved: true,
          resolvedPath: candidates[0],
        };
      }
      return { target, resolved: false };
    });
  }

  async findBacklinks(notePath: string): Promise<{ source: string; context: string }[]> {
    const allFiles = await this.getFiles();
    const noteName = path.basename(notePath, ".md");
    const backlinks: { source: string; context: string }[] = [];

    for (const file of allFiles) {
      if (file === notePath) continue;
      try {
        const content = await this.fs.readFile(file);
        const targets = this.parseLinks(content);
        if (targets.some((t) => t.toLowerCase() === noteName.toLowerCase())) {
          const lines = content.split("\n");
          const contextLine = lines.find((l) =>
            l.toLowerCase().includes(`[[${noteName.toLowerCase()}`)
          );
          backlinks.push({
            source: file,
            context: contextLine?.trim() || "",
          });
        }
      } catch {
        // Skip unreadable files
      }
    }

    return backlinks;
  }
}
