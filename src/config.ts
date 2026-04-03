import { config } from "dotenv";
import path from "node:path";

config();

export interface Config {
  vaultPath: string;
  apiKey: string;
  port: number;
  host: string;
}

export function loadConfig(): Config {
  const vaultPath = process.argv[2] || process.env.VAULT_PATH;
  if (!vaultPath) {
    console.error("VAULT_PATH environment variable or CLI argument required");
    process.exit(1);
  }

  const apiKey = process.env.API_KEY;
  if (!apiKey) {
    console.error("API_KEY environment variable required");
    process.exit(1);
  }

  return {
    vaultPath: path.resolve(vaultPath),
    apiKey,
    port: parseInt(process.env.PORT || "3456", 10),
    host: process.env.HOST || "0.0.0.0",
  };
}
