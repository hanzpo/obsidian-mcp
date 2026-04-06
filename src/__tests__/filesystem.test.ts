import { describe, it, expect, beforeEach, afterEach } from "vitest";
import fs from "node:fs/promises";
import path from "node:path";
import os from "node:os";
import { FileSystemService } from "../services/filesystem.js";

let tmpDir: string;
let service: FileSystemService;
let mountADir: string;
let mountBDir: string;

beforeEach(async () => {
  tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), "obsidian-mcp-test-"));
  service = new FileSystemService({ mode: "single", rootPath: tmpDir });
  mountADir = await fs.mkdtemp(path.join(os.tmpdir(), "obsidian-mcp-mount-a-"));
  mountBDir = await fs.mkdtemp(path.join(os.tmpdir(), "obsidian-mcp-mount-b-"));

  // Create test files
  await fs.mkdir(path.join(tmpDir, "Notes"), { recursive: true });
  await fs.writeFile(path.join(tmpDir, "Notes/hello.md"), "# Hello\nWorld");
  await fs.writeFile(path.join(tmpDir, "root.md"), "Root note");

  await fs.mkdir(path.join(mountADir, "Notes"), { recursive: true });
  await fs.mkdir(path.join(mountBDir, "Notes"), { recursive: true });
  await fs.writeFile(path.join(mountADir, "Notes/work.md"), "Work note");
  await fs.writeFile(path.join(mountBDir, "Notes/personal.md"), "Personal note");
});

afterEach(async () => {
  await fs.rm(tmpDir, { recursive: true });
  await fs.rm(mountADir, { recursive: true });
  await fs.rm(mountBDir, { recursive: true });
});

describe("FileSystemService", () => {
  it("reads files", async () => {
    const content = await service.readFile("Notes/hello.md");
    expect(content).toBe("# Hello\nWorld");
  });

  it("rejects path traversal", () => {
    expect(() => service.resolvePath("../../../etc/passwd")).toThrow(
      "Path traversal not allowed"
    );
  });

  it("rejects .obsidian access", () => {
    expect(() => service.resolvePath(".obsidian/config")).toThrow("Access denied");
  });

  it("writes files with auto-created directories", async () => {
    await service.writeFile("Deep/nested/note.md", "content");
    const content = await service.readFile("Deep/nested/note.md");
    expect(content).toBe("content");
  });

  it("checks file existence", async () => {
    expect(await service.exists("Notes/hello.md")).toBe(true);
    expect(await service.exists("nonexistent.md")).toBe(false);
  });

  it("deletes files", async () => {
    await service.deleteFile("root.md");
    expect(await service.exists("root.md")).toBe(false);
  });

  it("moves files", async () => {
    await service.moveFile("root.md", "Archive/root.md");
    expect(await service.exists("root.md")).toBe(false);
    expect(await service.exists("Archive/root.md")).toBe(true);
  });

  it("lists directory", async () => {
    const entries = await service.listDirectory("", false);
    const names = entries.map((e) => e.name);
    expect(names).toContain("Notes");
    expect(names).toContain("root.md");
  });

  it("lists directory recursively", async () => {
    const entries = await service.listDirectory("", true);
    const paths = entries.map((e) => e.path);
    expect(paths).toContain("Notes/hello.md");
  });

  it("gets all markdown files", async () => {
    const files = await service.getAllMarkdownFiles();
    expect(files).toContain("Notes/hello.md");
    expect(files).toContain("root.md");
  });

  it("lists mounted vault roots as top-level directories", async () => {
    const mounted = new FileSystemService({
      mode: "mounted",
      mounts: {
        personal: mountBDir,
        work: mountADir,
      },
    });

    const entries = await mounted.listDirectory("", false);
    expect(entries).toEqual([
      { name: "personal", type: "directory", path: "personal" },
      { name: "work", type: "directory", path: "work" },
    ]);
  });

  it("reads and lists markdown files across mounted vaults", async () => {
    const mounted = new FileSystemService({
      mode: "mounted",
      mounts: {
        work: mountADir,
        personal: mountBDir,
      },
    });

    expect(await mounted.readFile("work/Notes/work.md")).toBe("Work note");
    const files = await mounted.getAllMarkdownFiles();
    expect(files).toContain("work/Notes/work.md");
    expect(files).toContain("personal/Notes/personal.md");
  });

  it("moves files across mounted vaults", async () => {
    const mounted = new FileSystemService({
      mode: "mounted",
      mounts: {
        work: mountADir,
        personal: mountBDir,
      },
    });

    await mounted.moveFile(
      "work/Notes/work.md",
      "personal/Archive/work.md"
    );

    expect(await mounted.exists("work/Notes/work.md")).toBe(false);
    expect(await mounted.exists("personal/Archive/work.md")).toBe(true);
  });
});
