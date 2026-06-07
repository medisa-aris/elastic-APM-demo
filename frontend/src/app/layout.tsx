'use client';

import { useEffect } from 'react';
import { getApm } from '@/instrumentation/rum';

export default function RootLayout({ children }: { children: React.ReactNode }) {
  useEffect(() => {
    // Initialize Elastic RUM on first client render
    getApm();
  }, []);

  return (
    <html lang="en">
      <head>
        <meta charSet="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>Elastic APM Demo Shop</title>
        <style>{`
          * { box-sizing: border-box; margin: 0; padding: 0; }
          body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; background: #f5f5f5; color: #333; }
          nav { background: #0077cc; color: white; padding: 1rem 2rem; display: flex; gap: 2rem; align-items: center; }
          nav a { color: white; text-decoration: none; font-weight: 500; }
          nav a:hover { text-decoration: underline; }
          main { max-width: 1100px; margin: 2rem auto; padding: 0 1rem; }
          .card { background: white; border-radius: 8px; padding: 1.5rem; box-shadow: 0 1px 4px rgba(0,0,0,0.1); margin-bottom: 1rem; }
          .btn { display: inline-block; padding: 0.5rem 1.2rem; border-radius: 6px; border: none; cursor: pointer; font-size: 0.95rem; font-weight: 500; }
          .btn-primary { background: #0077cc; color: white; }
          .btn-primary:hover { background: #005fa3; }
          .btn-danger { background: #e53e3e; color: white; }
          .btn-danger:hover { background: #c53030; }
          .btn-secondary { background: #e2e8f0; color: #333; }
          .badge { display: inline-block; padding: 0.2rem 0.6rem; border-radius: 4px; font-size: 0.8rem; font-weight: 600; }
          .badge-success { background: #c6f6d5; color: #276749; }
          .badge-error { background: #fed7d7; color: #9b2c2c; }
          .badge-pending { background: #fefcbf; color: #744210; }
          .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(250px, 1fr)); gap: 1rem; }
          .error-msg { background: #fed7d7; color: #9b2c2c; padding: 1rem; border-radius: 6px; margin-bottom: 1rem; }
          .success-msg { background: #c6f6d5; color: #276749; padding: 1rem; border-radius: 6px; margin-bottom: 1rem; }
          input, select { width: 100%; padding: 0.5rem; border: 1px solid #cbd5e0; border-radius: 4px; font-size: 0.95rem; margin-bottom: 0.75rem; }
          label { display: block; font-size: 0.85rem; font-weight: 600; margin-bottom: 0.25rem; color: #555; }
          table { width: 100%; border-collapse: collapse; }
          th, td { text-align: left; padding: 0.75rem; border-bottom: 1px solid #e2e8f0; }
          th { font-size: 0.85rem; color: #666; text-transform: uppercase; letter-spacing: 0.05em; }
        `}</style>
      </head>
      <body>
        <nav>
          <strong>Elastic APM Demo Shop</strong>
          <a href="/">Products</a>
          <a href="/orders">Orders</a>
        </nav>
        <main>{children}</main>
      </body>
    </html>
  );
}
