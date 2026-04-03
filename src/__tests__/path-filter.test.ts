import { describe, it, expect } from "vitest";
import { isPathAllowed } from "../services/path-filter.js";

describe("isPathAllowed", () => {
  it("allows normal paths", () => {
    expect(isPathAllowed("Notes/hello.md")).toBe(true);
    expect(isPathAllowed("Projects/my-project/readme.md")).toBe(true);
    expect(isPathAllowed("daily.md")).toBe(true);
  });

  it("rejects .obsidian", () => {
    expect(isPathAllowed(".obsidian/plugins.json")).toBe(false);
  });

  it("rejects .git", () => {
    expect(isPathAllowed(".git/config")).toBe(false);
  });

  it("rejects .trash", () => {
    expect(isPathAllowed(".trash/deleted.md")).toBe(false);
  });

  it("rejects dotfiles", () => {
    expect(isPathAllowed(".hidden")).toBe(false);
    expect(isPathAllowed("Notes/.secret")).toBe(false);
  });
});
