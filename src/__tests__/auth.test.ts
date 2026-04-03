import { describe, it, expect, vi } from "vitest";
import type { Request, Response, NextFunction } from "express";
import { createAuthMiddleware } from "../auth.js";

function mockReqRes(authHeader?: string) {
  const req = {
    headers: { authorization: authHeader },
  } as unknown as Request;
  const res = {
    status: vi.fn().mockReturnThis(),
    json: vi.fn().mockReturnThis(),
  } as unknown as Response;
  const next = vi.fn() as NextFunction;
  return { req, res, next };
}

describe("createAuthMiddleware", () => {
  const middleware = createAuthMiddleware("test-secret-key");

  it("passes valid bearer token", () => {
    const { req, res, next } = mockReqRes("Bearer test-secret-key");
    middleware(req, res, next);
    expect(next).toHaveBeenCalled();
  });

  it("rejects missing authorization header", () => {
    const { req, res, next } = mockReqRes();
    middleware(req, res, next);
    expect(res.status).toHaveBeenCalledWith(401);
    expect(next).not.toHaveBeenCalled();
  });

  it("rejects non-bearer auth", () => {
    const { req, res, next } = mockReqRes("Basic dXNlcjpwYXNz");
    middleware(req, res, next);
    expect(res.status).toHaveBeenCalledWith(401);
    expect(next).not.toHaveBeenCalled();
  });

  it("rejects wrong key", () => {
    const { req, res, next } = mockReqRes("Bearer wrong-key");
    middleware(req, res, next);
    expect(res.status).toHaveBeenCalledWith(401);
    expect(next).not.toHaveBeenCalled();
  });

  it("rejects empty bearer token", () => {
    const { req, res, next } = mockReqRes("Bearer ");
    middleware(req, res, next);
    expect(res.status).toHaveBeenCalledWith(401);
    expect(next).not.toHaveBeenCalled();
  });

  it("rejects key with extra characters", () => {
    const { req, res, next } = mockReqRes("Bearer test-secret-key-extra");
    middleware(req, res, next);
    expect(res.status).toHaveBeenCalledWith(401);
    expect(next).not.toHaveBeenCalled();
  });
});
