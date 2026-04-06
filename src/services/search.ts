import { FileSystemService } from "./filesystem.js";

export interface SearchResult {
  path: string;
  score: number;
  excerpt: string;
}

interface CachedDoc {
  path: string;
  content: string;
  lower: string;
  words: string[];
  termFreqs: Map<string, number>;
}

const CACHE_TTL_MS = 30_000;

export class SearchService {
  private fs: FileSystemService;
  private cache: CachedDoc[] | null = null;
  private cacheTime = 0;

  constructor(vaultPath: string) {
    this.fs = new FileSystemService(vaultPath);
  }

  invalidateCache(): void {
    this.cache = null;
    this.cacheTime = 0;
  }

  private async loadDocs(): Promise<CachedDoc[]> {
    const now = Date.now();
    if (this.cache && now - this.cacheTime < CACHE_TTL_MS) {
      return this.cache;
    }

    const files = await this.fs.getAllMarkdownFiles();
    const docs: CachedDoc[] = [];

    for (const filePath of files) {
      try {
        const content = await this.fs.readFile(filePath);
        const lower = content.toLowerCase();
        const words = lower.split(/\W+/).filter((w) => w.length > 0);
        const termFreqs = new Map<string, number>();
        for (const word of words) {
          termFreqs.set(word, (termFreqs.get(word) || 0) + 1);
        }
        docs.push({ path: filePath, content, lower, words, termFreqs });
      } catch {
        // Skip unreadable files
      }
    }

    this.cache = docs;
    this.cacheTime = now;
    return docs;
  }

  async search(
    query: string,
    scopePath?: string,
    maxResults = 20
  ): Promise<SearchResult[]> {
    const terms = query
      .toLowerCase()
      .split(/\s+/)
      .filter((t) => t.length > 0);
    if (terms.length === 0) return [];

    let docs = await this.loadDocs();
    if (scopePath) {
      docs = docs.filter((d) => d.path.startsWith(scopePath));
    }

    const df = new Map<string, number>();
    const matched: CachedDoc[] = [];

    for (const doc of docs) {
      if (!terms.every((t) => doc.lower.includes(t))) continue;

      for (const term of terms) {
        if (doc.termFreqs.has(term)) {
          df.set(term, (df.get(term) || 0) + 1);
        }
      }
      matched.push(doc);
    }

    if (matched.length === 0) return [];

    const avgDl =
      matched.reduce((sum, d) => sum + d.words.length, 0) / matched.length;
    const N = matched.length;
    const k1 = 1.2;
    const b = 0.75;

    const scored: SearchResult[] = matched.map((doc) => {
      const dl = doc.words.length;
      let score = 0;

      for (const term of terms) {
        const tf = doc.termFreqs.get(term) || 0;
        const docFreq = df.get(term) || 0;
        const idf = Math.log((N - docFreq + 0.5) / (docFreq + 0.5) + 1);
        score +=
          idf * ((tf * (k1 + 1)) / (tf + k1 * (1 - b + b * (dl / avgDl))));
      }

      const excerpt = this.extractExcerpt(doc.content, terms[0]);

      return { path: doc.path, score, excerpt };
    });

    scored.sort((a, b) => b.score - a.score);
    return scored.slice(0, Math.min(maxResults, 50));
  }

  private extractExcerpt(content: string, term: string): string {
    const idx = content.toLowerCase().indexOf(term);
    if (idx === -1) return content.slice(0, 200);
    const start = Math.max(0, idx - 100);
    const end = Math.min(content.length, idx + 100);
    let excerpt = content.slice(start, end);
    if (start > 0) excerpt = "..." + excerpt;
    if (end < content.length) excerpt = excerpt + "...";
    return excerpt;
  }
}
