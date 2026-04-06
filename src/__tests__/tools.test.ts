import { describe, it, expect, beforeEach, afterEach } from "vitest";
import fs from "node:fs/promises";
import path from "node:path";
import os from "node:os";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import type { Config } from "../config.js";
import { createMcpServer, createServices } from "../server.js";

let tmpDir: string;
let desktopWorkDir: string;
let desktopPersonalDir: string;
let server: McpServer;
let client: Client;

beforeEach(async () => {
  tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), "obsidian-mcp-tools-"));
  desktopWorkDir = await fs.mkdtemp(
    path.join(os.tmpdir(), "obsidian-mcp-tools-work-")
  );
  desktopPersonalDir = await fs.mkdtemp(
    path.join(os.tmpdir(), "obsidian-mcp-tools-personal-")
  );

  // Create test vault structure
  await fs.mkdir(path.join(tmpDir, "Notes"), { recursive: true });
  await fs.mkdir(path.join(tmpDir, "Projects"), { recursive: true });
  await fs.writeFile(
    path.join(tmpDir, "Notes/hello.md"),
    `---
title: Hello World
tags:
  - greeting
  - test
---
# Hello World

This is a test note with a [[wikilink]] to another note.`
  );
  await fs.writeFile(
    path.join(tmpDir, "Notes/other.md"),
    "# Other\nAnother note."
  );
  await fs.writeFile(
    path.join(tmpDir, "Projects/alpha.md"),
    `---
status: active
---
# Alpha Project

Working on [[Hello World]] integration.`
  );

  const config: Config = {
    vaults: { mode: "single", rootPath: tmpDir },
    apiKey: "test",
    port: 0,
    host: "127.0.0.1",
  };

  server = createMcpServer(createServices(config));
  client = new Client({ name: "test-client", version: "1.0.0" });

  const [clientTransport, serverTransport] = InMemoryTransport.createLinkedPair();
  await Promise.all([
    server.connect(serverTransport),
    client.connect(clientTransport),
  ]);
});

afterEach(async () => {
  await client.close();
  await server.close();
  await fs.rm(tmpDir, { recursive: true });
  await fs.rm(desktopWorkDir, { recursive: true });
  await fs.rm(desktopPersonalDir, { recursive: true });
});

describe("tools via MCP protocol", () => {
  it("lists all 13 tools", async () => {
    const result = await client.listTools();
    expect(result.tools.length).toBe(13);
    const names = result.tools.map((t) => t.name).sort();
    expect(names).toContain("read_note");
    expect(names).toContain("search_notes");
    expect(names).toContain("create_note");
  });

  it("read_note returns content and metadata", async () => {
    const result = await client.callTool({
      name: "read_note",
      arguments: { path: "Notes/hello.md" },
    });
    const text = (result.content as Array<{ type: string; text: string }>)
      .map((c) => c.text)
      .join("");
    expect(text).toContain("Hello World");
    expect(text).toContain("wikilink");
    expect(text).toContain("Size:");
  });

  it("read_notes batch reads", async () => {
    const result = await client.callTool({
      name: "read_notes",
      arguments: { paths: ["Notes/hello.md", "Notes/other.md"] },
    });
    const text = (result.content as Array<{ type: string; text: string }>)[0].text;
    expect(text).toContain("Hello World");
    expect(text).toContain("Other");
  });

  it("read_notes handles missing files", async () => {
    const result = await client.callTool({
      name: "read_notes",
      arguments: { paths: ["Notes/hello.md", "nonexistent.md"] },
    });
    const text = (result.content as Array<{ type: string; text: string }>)[0].text;
    expect(text).toContain("Hello World");
    expect(text).toContain("Error:");
  });

  it("create_note creates a new note", async () => {
    await client.callTool({
      name: "create_note",
      arguments: { path: "Notes/new.md", content: "# New\nContent" },
    });
    const content = await fs.readFile(path.join(tmpDir, "Notes/new.md"), "utf-8");
    expect(content).toContain("# New");
  });

  it("create_note refuses overwrite by default", async () => {
    const result = await client.callTool({
      name: "create_note",
      arguments: { path: "Notes/hello.md", content: "overwritten" },
    });
    expect(result.isError).toBe(true);
    // Original should be unchanged
    const content = await fs.readFile(path.join(tmpDir, "Notes/hello.md"), "utf-8");
    expect(content).toContain("Hello World");
  });

  it("create_note with frontmatter", async () => {
    await client.callTool({
      name: "create_note",
      arguments: {
        path: "Notes/with-fm.md",
        content: "Body",
        frontmatter: { title: "Test", tags: ["a", "b"] },
      },
    });
    const content = await fs.readFile(path.join(tmpDir, "Notes/with-fm.md"), "utf-8");
    expect(content).toContain("title: Test");
    expect(content).toContain("Body");
  });

  it("edit_note appends", async () => {
    await client.callTool({
      name: "edit_note",
      arguments: {
        path: "Notes/other.md",
        operation: "append",
        content: "Appended line.",
      },
    });
    const content = await fs.readFile(path.join(tmpDir, "Notes/other.md"), "utf-8");
    expect(content).toContain("Appended line.");
    expect(content).toContain("# Other");
  });

  it("edit_note replaces text", async () => {
    await client.callTool({
      name: "edit_note",
      arguments: {
        path: "Notes/other.md",
        operation: "replace",
        content: "Replaced.",
        oldContent: "Another note.",
      },
    });
    const content = await fs.readFile(path.join(tmpDir, "Notes/other.md"), "utf-8");
    expect(content).toContain("Replaced.");
    expect(content).not.toContain("Another note.");
  });

  it("edit_note replace fails when oldContent not found", async () => {
    const result = await client.callTool({
      name: "edit_note",
      arguments: {
        path: "Notes/other.md",
        operation: "replace",
        content: "new",
        oldContent: "nonexistent text",
      },
    });
    expect(result.isError).toBe(true);
  });

  it("delete_note requires confirmation", async () => {
    const result = await client.callTool({
      name: "delete_note",
      arguments: { path: "Notes/other.md", confirm: false },
    });
    expect(result.isError).toBe(true);
    // File still exists
    const exists = await fs.access(path.join(tmpDir, "Notes/other.md")).then(() => true, () => false);
    expect(exists).toBe(true);
  });

  it("delete_note deletes when confirmed", async () => {
    await client.callTool({
      name: "delete_note",
      arguments: { path: "Notes/other.md", confirm: true },
    });
    const exists = await fs.access(path.join(tmpDir, "Notes/other.md")).then(() => true, () => false);
    expect(exists).toBe(false);
  });

  it("move_note moves a file", async () => {
    await client.callTool({
      name: "move_note",
      arguments: { oldPath: "Notes/other.md", newPath: "Archive/other.md" },
    });
    const oldExists = await fs.access(path.join(tmpDir, "Notes/other.md")).then(() => true, () => false);
    const newExists = await fs.access(path.join(tmpDir, "Archive/other.md")).then(() => true, () => false);
    expect(oldExists).toBe(false);
    expect(newExists).toBe(true);
  });

  it("list_directory lists vault root", async () => {
    const result = await client.callTool({
      name: "list_directory",
      arguments: {},
    });
    const text = (result.content as Array<{ type: string; text: string }>)[0].text;
    expect(text).toContain("Notes");
    expect(text).toContain("Projects");
  });

  it("list_directory recursive", async () => {
    const result = await client.callTool({
      name: "list_directory",
      arguments: { recursive: true },
    });
    const text = (result.content as Array<{ type: string; text: string }>)[0].text;
    expect(text).toContain("Notes/hello.md");
    expect(text).toContain("Projects/alpha.md");
  });

  it("search_notes finds results", async () => {
    const result = await client.callTool({
      name: "search_notes",
      arguments: { query: "alpha project" },
    });
    const text = (result.content as Array<{ type: string; text: string }>)[0].text;
    expect(text).toContain("Projects/alpha.md");
  });

  it("search_notes sees newly created notes immediately after cache priming", async () => {
    await client.callTool({
      name: "search_notes",
      arguments: { query: "alpha" },
    });

    await client.callTool({
      name: "create_note",
      arguments: {
        path: "Notes/fresh.md",
        content: "# Fresh\nContains cachebustterm.",
      },
    });

    const result = await client.callTool({
      name: "search_notes",
      arguments: { query: "cachebustterm" },
    });
    const text = (result.content as Array<{ type: string; text: string }>)[0].text;
    expect(text).toContain("Notes/fresh.md");
  });

  it("search_notes returns no results for gibberish", async () => {
    const result = await client.callTool({
      name: "search_notes",
      arguments: { query: "xyzzyplugh" },
    });
    const text = (result.content as Array<{ type: string; text: string }>)[0].text;
    expect(text).toContain("No results");
  });

  it("get_frontmatter returns parsed data", async () => {
    const result = await client.callTool({
      name: "get_frontmatter",
      arguments: { path: "Notes/hello.md" },
    });
    const text = (result.content as Array<{ type: string; text: string }>)[0].text;
    const data = JSON.parse(text);
    expect(data.title).toBe("Hello World");
    expect(data.tags).toEqual(["greeting", "test"]);
  });

  it("update_frontmatter merges and removes", async () => {
    await client.callTool({
      name: "update_frontmatter",
      arguments: {
        path: "Projects/alpha.md",
        updates: { priority: "high" },
        removeKeys: ["status"],
      },
    });
    const content = await fs.readFile(path.join(tmpDir, "Projects/alpha.md"), "utf-8");
    expect(content).toContain("priority: high");
    expect(content).not.toContain("status: active");
  });

  it("manage_tags lists tags", async () => {
    const result = await client.callTool({
      name: "manage_tags",
      arguments: { path: "Notes/hello.md", action: "list" },
    });
    const text = (result.content as Array<{ type: string; text: string }>)[0].text;
    expect(text).toContain("greeting");
    expect(text).toContain("test");
  });

  it("manage_tags adds tags without duplicates", async () => {
    await client.callTool({
      name: "manage_tags",
      arguments: {
        path: "Notes/hello.md",
        action: "add",
        tags: ["test", "new-tag"],
      },
    });
    const content = await fs.readFile(path.join(tmpDir, "Notes/hello.md"), "utf-8");
    expect(content).toContain("new-tag");
    // "test" should appear only once
    const matches = content.match(/- test/g);
    expect(matches?.length).toBe(1);
  });

  it("manage_tags removes tags", async () => {
    await client.callTool({
      name: "manage_tags",
      arguments: {
        path: "Notes/hello.md",
        action: "remove",
        tags: ["greeting"],
      },
    });
    const content = await fs.readFile(path.join(tmpDir, "Notes/hello.md"), "utf-8");
    expect(content).not.toContain("greeting");
    expect(content).toContain("test");
  });

  it("get_vault_stats returns counts", async () => {
    const result = await client.callTool({
      name: "get_vault_stats",
      arguments: {},
    });
    const text = (result.content as Array<{ type: string; text: string }>)[0].text;
    expect(text).toContain("Notes: 3");
    expect(text).toContain("Folders: 2");
  });

  it("get_links finds outgoing and backlinks", async () => {
    const result = await client.callTool({
      name: "get_links",
      arguments: { path: "Notes/hello.md" },
    });
    const text = (result.content as Array<{ type: string; text: string }>)[0].text;
    expect(text).toContain("Outgoing links:");
    expect(text).toContain("wikilink");
  });

  it("get_links sees newly created targets immediately after cache priming", async () => {
    const initial = await client.callTool({
      name: "get_links",
      arguments: { path: "Notes/hello.md" },
    });
    const initialText = (initial.content as Array<{ type: string; text: string }>)[0].text;
    expect(initialText).toContain("wikilink -> (unresolved)");

    await client.callTool({
      name: "create_note",
      arguments: { path: "Notes/wikilink.md", content: "# Wikilink\nNow exists." },
    });

    const updated = await client.callTool({
      name: "get_links",
      arguments: { path: "Notes/hello.md" },
    });
    const updatedText = (updated.content as Array<{ type: string; text: string }>)[0].text;
    expect(updatedText).toContain("wikilink -> Notes/wikilink.md");
  });

  it("rejects path traversal", async () => {
    const result = await client.callTool({
      name: "read_note",
      arguments: { path: "../../../etc/passwd" },
    });
    expect(result.isError).toBe(true);
    const text = (result.content as Array<{ type: string; text: string }>)[0].text;
    expect(text).toContain("Path traversal");
  });

  it("rejects .obsidian access", async () => {
    await fs.mkdir(path.join(tmpDir, ".obsidian"), { recursive: true });
    await fs.writeFile(path.join(tmpDir, ".obsidian/app.json"), "{}");
    const result = await client.callTool({
      name: "read_note",
      arguments: { path: ".obsidian/app.json" },
    });
    expect(result.isError).toBe(true);
    const text = (result.content as Array<{ type: string; text: string }>)[0].text;
    expect(text).toContain("Access denied");
  });
});

describe("tools via MCP protocol with mounted desktop vaults", () => {
  beforeEach(async () => {
    await fs.mkdir(path.join(desktopWorkDir, "Projects"), { recursive: true });
    await fs.mkdir(path.join(desktopPersonalDir, "Journal"), {
      recursive: true,
    });
    await fs.writeFile(
      path.join(desktopWorkDir, "Projects/roadmap.md"),
      "# Roadmap\nShared launch plan."
    );
    await fs.writeFile(
      path.join(desktopPersonalDir, "Journal/today.md"),
      "Thinking about [[roadmap]]."
    );
  });

  it("surfaces mounted vault aliases at the root", async () => {
    const mountedConfig: Config = {
      vaults: {
        mode: "mounted",
        mounts: {
          personal: desktopPersonalDir,
          work: desktopWorkDir,
        },
      },
      apiKey: "test",
      port: 0,
      host: "127.0.0.1",
    };

    const mountedServer = createMcpServer(createServices(mountedConfig));
    const mountedClient = new Client({
      name: "mounted-test-client",
      version: "1.0.0",
    });
    const [clientTransport, serverTransport] =
      InMemoryTransport.createLinkedPair();

    await Promise.all([
      mountedServer.connect(serverTransport),
      mountedClient.connect(clientTransport),
    ]);

    try {
      const listResult = await mountedClient.callTool({
        name: "list_directory",
        arguments: {},
      });
      const listText = (
        listResult.content as Array<{ type: string; text: string }>
      )[0].text;
      expect(listText).toContain("personal");
      expect(listText).toContain("work");

      const readResult = await mountedClient.callTool({
        name: "read_note",
        arguments: { path: "work/Projects/roadmap.md" },
      });
      const readText = (
        readResult.content as Array<{ type: string; text: string }>
      )[0].text;
      expect(readText).toContain("Shared launch plan.");

      const linksResult = await mountedClient.callTool({
        name: "get_links",
        arguments: { path: "personal/Journal/today.md" },
      });
      const linksText = (
        linksResult.content as Array<{ type: string; text: string }>
      )[0].text;
      expect(linksText).toContain("roadmap -> work/Projects/roadmap.md");
    } finally {
      await mountedClient.close();
      await mountedServer.close();
    }
  });
});
