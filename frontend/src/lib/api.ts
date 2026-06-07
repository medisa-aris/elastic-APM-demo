// Calls go to /api/* on the same origin — the Next.js proxy route
// (src/app/api/[...path]/route.ts) forwards them to GATEWAY_URL server-side.
// No NEXT_PUBLIC_GATEWAY_URL needed; works in every deployment without rebuilding.
async function apiFetch<T>(path: string, options?: RequestInit): Promise<T> {
  const res = await fetch(path, {
    headers: { 'Content-Type': 'application/json', ...options?.headers },
    ...options,
  });

  if (!res.ok) {
    const body = await res.json().catch(() => ({}));
    throw Object.assign(new Error(body.error || `HTTP ${res.status}`), { status: res.status, body });
  }

  return res.json();
}

export interface Product {
  sku: string;
  name: string;
  description: string;
  price: number;
  available: number;
}

export interface Order {
  id: string;
  items: string;
  paymentId: string;
  status: string;
  totalAmount: number;
  createdAt: string;
}

export interface PurchaseResult {
  orderId: string;
  paymentId: string;
  status: string;
  totalAmount: number;
}

export const api = {
  getProducts: () => apiFetch<Product[]>('/api/products'),
  getProduct: (sku: string) => apiFetch<Product>(`/api/products/${sku}`),
  getOrders: () => apiFetch<Order[]>('/api/orders'),

  purchase: (items: { sku: string; quantity: number }[], cardNumber: string) =>
    apiFetch<PurchaseResult>('/api/purchase', {
      method: 'POST',
      body: JSON.stringify({ items, payment: { card_number: cardNumber } }),
    }),

  refund: (orderId: string) =>
    apiFetch<{ orderId: string; status: string }>('/api/refund', {
      method: 'POST',
      body: JSON.stringify({ orderId }),
    }),
};
