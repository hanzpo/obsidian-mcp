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
    Object.assign(data, updates);
    if (removeKeys) {
      for (const key of removeKeys) {
        delete data[key];
      }
    }
    return matter.stringify(content, data);
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
