import { FileSystemService } from "./filesystem.js";

export interface SearchResult {
  path: string;
  score: number;
  excerpt: string;
}

export class SearchService {
  private fs: FileSystemService;

  constructor(vaultPath: string) {
    this.fs = new FileSystemService(vaultPath);
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

    let files = await this.fs.getAllMarkdownFiles();
    if (scopePath) {
      files = files.filter((f) => f.startsWith(scopePath));
    }

    const docs: { path: string; content: string; termFreqs: Map<string, number> }[] = [];
    let totalLength = 0;

    // Document frequencies for each term
    const df = new Map<string, number>();

    for (const filePath of files) {
      try {
        const content = await this.fs.readFile(filePath);
        const lower = content.toLowerCase();
        const words = lower.split(/\W+/).filter((w) => w.length > 0);
        const termFreqs = new Map<string, number>();

        for (const word of words) {
          termFreqs.set(word, (termFreqs.get(word) || 0) + 1);
        }

        // Check all query terms appear in content (AND logic)
        const allMatch = terms.every(
          (t) => lower.includes(t)
        );
        if (!allMatch) continue;

        for (const term of terms) {
          if (termFreqs.has(term)) {
            df.set(term, (df.get(term) || 0) + 1);
          }
        }

        docs.push({ path: filePath, content, termFreqs });
        totalLength += words.length;
      } catch {
        // Skip unreadable files
      }
    }

    if (docs.length === 0) return [];

    const avgDl = totalLength / docs.length;
    const N = docs.length;
    const k1 = 1.2;
    const b = 0.75;

    const scored: SearchResult[] = docs.map((doc) => {
      const dl = Array.from(doc.termFreqs.values()).reduce((a, b) => a + b, 0);
      let score = 0;

      for (const term of terms) {
        const tf = doc.termFreqs.get(term) || 0;
        const docFreq = df.get(term) || 0;
        const idf = Math.log((N - docFreq + 0.5) / (docFreq + 0.5) + 1);
        score += idf * ((tf * (k1 + 1)) / (tf + k1 * (1 - b + b * (dl / avgDl))));
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
