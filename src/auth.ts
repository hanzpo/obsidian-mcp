import { timingSafeEqual } from "node:crypto";
import type { Request, Response, NextFunction } from "express";

function readToken(req: Request): string | undefined {
  const header = req.headers.authorization;
  if (header?.startsWith("Bearer ")) {
    return header.slice(7);
  }

  const xApiKey = req.headers["x-api-key"];
  if (typeof xApiKey === "string" && xApiKey.length > 0) {
    return xApiKey;
  }

  const queryToken = req.query.api_key ?? req.query.token;
  if (typeof queryToken === "string" && queryToken.length > 0) {
    return queryToken;
  }

  return undefined;
}

export function createAuthMiddleware(apiKey: string) {
  const expectedBuffer = Buffer.from(apiKey);

  return (req: Request, res: Response, next: NextFunction): void => {
    const token = readToken(req);
    if (!token) {
      res.status(401).json({
        error:
          "Missing API key. Use Authorization: Bearer <key>, X-API-Key, or ?api_key=<key>.",
      });
      return;
    }

    const tokenBuffer = Buffer.from(token);
    if (
      tokenBuffer.length !== expectedBuffer.length ||
      !timingSafeEqual(tokenBuffer, expectedBuffer)
    ) {
      res.status(401).json({ error: "Invalid API key" });
      return;
    }

    next();
  };
}
