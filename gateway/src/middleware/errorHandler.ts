import { Request, Response, NextFunction } from 'express';

export function errorHandler(err: Error, req: Request, res: Response, next: NextFunction): void {
  console.error(`[gateway] unhandled error: ${err.message}`, err.stack);
  res.status(500).json({ error: 'Internal server error', message: err.message });
}
