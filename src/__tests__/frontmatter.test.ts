import { describe, it, expect } from "vitest";
import { FrontmatterService } from "../services/frontmatter.js";

const service = new FrontmatterService();

describe("FrontmatterService", () => {
  it("parses frontmatter", () => {
    const raw = `---
title: Hello
tags:
  - test
---
Content here`;
    const parsed = service.parse(raw);
    expect(parsed.data.title).toBe("Hello");
    expect(parsed.data.tags).toEqual(["test"]);
    expect(parsed.content.trim()).toBe("Content here");
  });

  it("handles notes without frontmatter", () => {
    const parsed = service.parse("Just content");
    expect(parsed.data).toEqual({});
    expect(parsed.content.trim()).toBe("Just content");
  });

  it("stringifies content with frontmatter", () => {
    const result = service.stringify("Content", { title: "Test" });
    expect(result).toContain("title: Test");
    expect(result).toContain("Content");
  });

  it("updates frontmatter fields", () => {
    const raw = `---
title: Old
status: draft
---
Content`;
    const updated = service.update(raw, { title: "New" }, ["status"]);
    const parsed = service.parse(updated);
    expect(parsed.data.title).toBe("New");
    expect(parsed.data.status).toBeUndefined();
  });

  it("gets tags", () => {
    const raw = `---
tags:
  - foo
  - bar
---
Content`;
    expect(service.getTags(raw)).toEqual(["foo", "bar"]);
  });

  it("returns empty tags for notes without tags", () => {
    expect(service.getTags("No frontmatter")).toEqual([]);
  });
});
