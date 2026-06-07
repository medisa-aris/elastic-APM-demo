/**
 * Catch-all proxy route: /api/* → GATEWAY_URL/api/*
 *
 * This lets the browser call a same-origin URL (/api/products) instead of
 * a hard-coded gateway address. GATEWAY_URL is a server-side env var so it
 * doesn't need to be baked into the image at build time.
 */
import { NextRequest, NextResponse } from 'next/server';

const GATEWAY_URL = process.env.GATEWAY_URL || 'http://localhost:4000';

async function proxy(request: NextRequest, path: string): Promise<NextResponse> {
  const { search } = new URL(request.url);
  const target = `${GATEWAY_URL}/api/${path}${search}`;

  let body: string | undefined;
  if (request.method !== 'GET' && request.method !== 'HEAD') {
    body = await request.text();
  }

  try {
    const upstream = await fetch(target, {
      method: request.method,
      headers: { 'Content-Type': 'application/json' },
      body,
    });

    const data = await upstream.json().catch(() => ({}));
    return NextResponse.json(data, { status: upstream.status });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err);
    return NextResponse.json(
      { error: `Gateway unreachable: ${message}` },
      { status: 502 }
    );
  }
}

export async function GET(
  request: NextRequest,
  { params }: { params: { path: string[] } }
) {
  return proxy(request, params.path.join('/'));
}

export async function POST(
  request: NextRequest,
  { params }: { params: { path: string[] } }
) {
  return proxy(request, params.path.join('/'));
}
