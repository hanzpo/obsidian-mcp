import { describe, it, expect, beforeEach, afterEach } from "vitest";
import fs from "node:fs/promises";
import path from "node:path";
import os from "node:os";
import { SearchService } from "../services/search.js";

let tmpDir: string;
let service: SearchService;

beforeEach(async () => {
  tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), "obsidian-mcp-search-"));
  service = new SearchService({ mode: "single", rootPath: tmpDir });

  await fs.mkdir(path.join(tmpDir, "Projects"), { recursive: true });
  await fs.writeFile(
    path.join(tmpDir, "Projects/alpha.md"),
    "# Alpha Project\nThis is the alpha project about machine learning."
  );
  await fs.writeFile(
    path.join(tmpDir, "Projects/beta.md"),
    "# Beta Project\nThis project is about web development and APIs."
  );
  await fs.writeFile(
    path.join(tmpDir, "daily.md"),
    "# Daily Note\nToday I worked on the alpha project."
  );
});

afterEach(async () => {
  await fs.rm(tmpDir, { recursive: true });
});

describe("SearchService", () => {
  it("finds matching notes", async () => {
    const results = await service.search("alpha");
    expect(results.length).toBeGreaterThan(0);
    const paths = results.map((r) => r.path);
    expect(paths).toContain("Projects/alpha.md");
    expect(paths).toContain("daily.md");
  });

  it("ranks results by relevance", async () => {
    const results = await service.search("alpha project");
    expect(results[0].path).toBe("Projects/alpha.md");
  });

  it("returns empty for no matches", async () => {
    const results = await service.search("nonexistent xyz");
    expect(results).toEqual([]);
  });

  it("scopes search to path", async () => {
    const results = await service.search("project", "Projects");
    for (const r of results) {
      expect(r.path.startsWith("Projects")).toBe(true);
    }
  });

  it("includes excerpts", async () => {
    const results = await service.search("machine learning");
    expect(results.length).toBeGreaterThan(0);
    expect(results[0].excerpt).toContain("machine learning");
  });
});
