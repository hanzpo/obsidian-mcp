import { config } from "dotenv";
import fs from "node:fs";
import path from "node:path";

config();

export type VaultConfig =
  | { mode: "single"; rootPath: string }
  | { mode: "mounted"; mounts: Record<string, string> };

export interface Config {
  vaults: VaultConfig;
  apiKey: string;
  port: number;
  host: string;
}

function loadMountedVaults(vaultMapFile: string): Record<string, string> {
  const raw = fs.readFileSync(vaultMapFile, "utf-8");
  const parsed = JSON.parse(raw) as Record<string, unknown>;
  const entries = Object.entries(parsed).map(([name, value]) => {
    if (typeof value !== "string") {
      throw new Error(`Invalid mount path for vault "${name}"`);
    }
    return [name, path.resolve(value)] as const;
  });

  if (entries.length === 0) {
    throw new Error("VAULT_MAP_FILE did not contain any vault mounts");
  }

  return Object.fromEntries(entries);
}

export function loadConfig(): Config {
  let vaults: VaultConfig;

  try {
    const vaultMapFile = process.env.VAULT_MAP_FILE;
    if (vaultMapFile) {
      vaults = {
        mode: "mounted",
        mounts: loadMountedVaults(vaultMapFile),
      };
    } else {
      const vaultPath = process.argv[2] || process.env.VAULT_PATH;
      if (!vaultPath) {
        console.error(
          "VAULT_PATH environment variable or CLI argument required"
        );
        process.exit(1);
      }

      vaults = {
        mode: "single",
        rootPath: path.resolve(vaultPath),
      };
    }
  } catch (error) {
    console.error(
      error instanceof Error ? error.message : "Failed to load vault config"
    );
    process.exit(1);
  }

  const apiKey = process.env.API_KEY;
  if (!apiKey) {
    console.error("API_KEY environment variable required");
    process.exit(1);
  }

  return {
    vaults,
    apiKey,
    port: parseInt(process.env.PORT || "3456", 10),
    host: process.env.HOST || "0.0.0.0",
  };
}
