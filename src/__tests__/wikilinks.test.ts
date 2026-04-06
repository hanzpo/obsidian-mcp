import { describe, it, expect, beforeEach, afterEach } from "vitest";
import fs from "node:fs/promises";
import path from "node:path";
import os from "node:os";
import { WikilinkService } from "../services/wikilinks.js";

let tmpDir: string;
let service: WikilinkService;

beforeEach(async () => {
  tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), "obsidian-mcp-links-"));
  service = new WikilinkService({ mode: "single", rootPath: tmpDir });

  await fs.mkdir(path.join(tmpDir, "Projects"), { recursive: true });
  await fs.mkdir(path.join(tmpDir, "People"), { recursive: true });
  await fs.writeFile(
    path.join(tmpDir, "note-a.md"),
    "Link to [[note-b]] and [[note-c|display text]]"
  );
  await fs.writeFile(
    path.join(tmpDir, "note-b.md"),
    "This links back to [[note-a]]"
  );
  await fs.writeFile(path.join(tmpDir, "note-c.md"), "No links here");
  await fs.writeFile(
    path.join(tmpDir, "Projects/shared.md"),
    "Project-scoped shared note"
  );
  await fs.writeFile(
    path.join(tmpDir, "People/shared.md"),
    "People-scoped shared note"
  );
  await fs.writeFile(
    path.join(tmpDir, "Projects/source.md"),
    "Links to [[shared]] and [[People/shared]]."
  );
  await fs.writeFile(
    path.join(tmpDir, "People/source.md"),
    "Links back to [[shared]]."
  );
});

afterEach(async () => {
  await fs.rm(tmpDir, { recursive: true });
});

describe("WikilinkService", () => {
  it("parses wikilinks", () => {
    const links = service.parseLinks("See [[foo]] and [[bar|baz]]");
    expect(links).toEqual(["foo", "bar"]);
  });

  it("resolves links to existing files", async () => {
    const content = "Link to [[note-b]]";
    const links = await service.resolveLinks(content);
    expect(links[0].resolved).toBe(true);
    expect(links[0].resolvedPath).toBe("note-b.md");
  });

  it("marks unresolved links", async () => {
    const content = "Link to [[nonexistent]]";
    const links = await service.resolveLinks(content);
    expect(links[0].resolved).toBe(false);
  });

  it("finds backlinks", async () => {
    const backlinks = await service.findBacklinks("note-b.md");
    expect(backlinks.length).toBe(1);
    expect(backlinks[0].source).toBe("note-a.md");
  });

  it("resolves duplicate basenames relative to the source note", async () => {
    const content = "Links to [[shared]] and [[People/shared]].";
    const links = await service.resolveLinks(content, "Projects/source.md");
    expect(links).toEqual([
      { target: "shared", resolved: true, resolvedPath: "Projects/shared.md" },
      { target: "People/shared", resolved: true, resolvedPath: "People/shared.md" },
    ]);
  });

  it("finds backlinks using resolved note paths instead of basenames", async () => {
    const backlinks = await service.findBacklinks("People/shared.md");
    expect(backlinks).toHaveLength(2);
    expect(backlinks).toEqual(
      expect.arrayContaining([
        {
          source: "Projects/source.md",
          context: "Links to [[shared]] and [[People/shared]].",
        },
        {
          source: "People/source.md",
          context: "Links back to [[shared]].",
        },
      ])
    );
  });
});
