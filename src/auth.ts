import { timingSafeEqual } from "node:crypto";
import type { Request, Response, NextFunction } from "express";

export function createAuthMiddleware(apiKey: string) {
  const expectedBuffer = Buffer.from(apiKey);

  return (req: Request, res: Response, next: NextFunction): void => {
    const header = req.headers.authorization;
    if (!header?.startsWith("Bearer ")) {
      res.status(401).json({ error: "Missing or invalid Authorization header" });
      return;
    }

    const tokenBuffer = Buffer.from(header.slice(7));
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
