'use client';

import { useState, useEffect } from 'react';
import { api, Product } from '@/lib/api';

interface CartItem {
  sku: string;
  name: string;
  price: number;
  quantity: number;
}

export default function ProductsPage() {
  const [products, setProducts] = useState<Product[]>([]);
  const [cart, setCart] = useState<CartItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  useEffect(() => {
    api.getProducts()
      .then(setProducts)
      .catch((e) => setError(e.message))
      .finally(() => setLoading(false));
  }, []);

  function addToCart(product: Product) {
    setCart((prev) => {
      const existing = prev.find((i) => i.sku === product.sku);
      if (existing) {
        return prev.map((i) => i.sku === product.sku ? { ...i, quantity: i.quantity + 1 } : i);
      }
      return [...prev, { sku: product.sku, name: product.name, price: product.price, quantity: 1 }];
    });
  }

  function removeFromCart(sku: string) {
    setCart((prev) => prev.filter((i) => i.sku !== sku));
  }

  const cartTotal = cart.reduce((sum, i) => sum + i.price * i.quantity, 0);

  if (loading) return <p>Loading products...</p>;

  return (
    <div>
      <h1 style={{ marginBottom: '1.5rem', fontSize: '1.6rem' }}>Products</h1>

      {error && <div className="error-msg">{error}</div>}

      <div style={{ display: 'flex', gap: '2rem', alignItems: 'flex-start' }}>
        <div className="grid" style={{ flex: 1 }}>
          {products.map((p) => (
            <div key={p.sku} className="card">
              <div style={{ fontWeight: 700, marginBottom: '0.3rem' }}>{p.name}</div>
              <div style={{ fontSize: '0.85rem', color: '#666', marginBottom: '0.75rem' }}>{p.description}</div>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                <span style={{ fontWeight: 700, color: '#0077cc', fontSize: '1.1rem' }}>${p.price.toFixed(2)}</span>
                <span style={{ fontSize: '0.8rem', color: p.available > 0 ? '#276749' : '#9b2c2c' }}>
                  {p.available > 0 ? `${p.available} in stock` : 'Out of stock'}
                </span>
              </div>
              <button
                className="btn btn-primary"
                style={{ marginTop: '1rem', width: '100%' }}
                disabled={p.available === 0}
                onClick={() => addToCart(p)}
              >
                Add to Cart
              </button>
            </div>
          ))}
        </div>

        {cart.length > 0 && (
          <div className="card" style={{ minWidth: '280px' }}>
            <h2 style={{ marginBottom: '1rem', fontSize: '1.1rem' }}>Cart</h2>
            {cart.map((item) => (
              <div key={item.sku} style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '0.5rem', fontSize: '0.9rem' }}>
                <span>{item.name} × {item.quantity}</span>
                <div style={{ display: 'flex', gap: '0.5rem', alignItems: 'center' }}>
                  <span>${(item.price * item.quantity).toFixed(2)}</span>
                  <button onClick={() => removeFromCart(item.sku)} style={{ background: 'none', border: 'none', cursor: 'pointer', color: '#e53e3e', fontSize: '1.1rem' }}>×</button>
                </div>
              </div>
            ))}
            <hr style={{ margin: '0.75rem 0', borderColor: '#e2e8f0' }} />
            <div style={{ display: 'flex', justifyContent: 'space-between', fontWeight: 700, marginBottom: '1rem' }}>
              <span>Total</span>
              <span>${cartTotal.toFixed(2)}</span>
            </div>
            <a href={`/checkout?cart=${encodeURIComponent(JSON.stringify(cart))}`}>
              <button className="btn btn-primary" style={{ width: '100%' }}>Checkout</button>
            </a>
          </div>
        )}
      </div>
    </div>
  );
}
