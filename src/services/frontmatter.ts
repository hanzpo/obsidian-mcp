import matter from "gray-matter";

export interface ParsedNote {
  data: Record<string, unknown>;
  content: string;
}

export class FrontmatterService {
  parse(raw: string): ParsedNote {
    const { data, content } = matter(raw);
    return { data, content };
  }

  stringify(content: string, data: Record<string, unknown>): string {
    return matter.stringify(content, data);
  }

  update(
    raw: string,
    updates: Record<string, unknown>,
    removeKeys?: string[]
  ): string {
    const { data, content } = matter(raw);
    const merged = { ...data, ...updates };
    const removeSet = new Set(removeKeys);
    const filtered = Object.fromEntries(
      Object.entries(merged).filter(([k]) => !removeSet.has(k))
    );
    return matter.stringify(content, filtered);
  }

  getTags(raw: string): string[] {
    const { data } = matter(raw);
    const tags = data.tags;
    if (Array.isArray(tags)) return tags.map((t: unknown) => String(t));
    if (typeof tags === "string") return [tags];
    return [];
  }

  setTags(raw: string, tags: string[]): string {
    return this.update(raw, { tags });
  }
}
