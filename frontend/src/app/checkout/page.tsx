'use client';

import { useState, useEffect, Suspense } from 'react';
import { useSearchParams } from 'next/navigation';
import { api } from '@/lib/api';

interface CartItem {
  sku: string;
  name: string;
  price: number;
  quantity: number;
}

function CheckoutForm() {
  const searchParams = useSearchParams();
  const [cart, setCart] = useState<CartItem[]>([]);
  const [cardNumber, setCardNumber] = useState('4111111111111111');
  const [submitting, setSubmitting] = useState(false);
  const [result, setResult] = useState<{ orderId: string; totalAmount: number } | null>(null);
  const [error, setError] = useState('');

  useEffect(() => {
    const cartParam = searchParams.get('cart');
    if (cartParam) {
      try {
        setCart(JSON.parse(decodeURIComponent(cartParam)));
      } catch {}
    }
  }, [searchParams]);

  const total = cart.reduce((sum, i) => sum + i.price * i.quantity, 0);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError('');
    setSubmitting(true);

    try {
      const items = cart.map((i) => ({ sku: i.sku, quantity: i.quantity }));
      const res = await api.purchase(items, cardNumber);
      setResult({ orderId: res.orderId, totalAmount: res.totalAmount });
    } catch (err: unknown) {
      const e = err as { message?: string; body?: { error?: string } };
      const msg = e.body?.error || e.message || 'Purchase failed';
      setError(msg);
    } finally {
      setSubmitting(false);
    }
  }

  if (result) {
    return (
      <div className="card" style={{ maxWidth: 500 }}>
        <div className="success-msg">
          <strong>Order placed successfully!</strong>
        </div>
        <p>Order ID: <code>{result.orderId}</code></p>
        <p>Total charged: <strong>${result.totalAmount.toFixed(2)}</strong></p>
        <div style={{ marginTop: '1rem', display: 'flex', gap: '1rem' }}>
          <a href="/"><button className="btn btn-secondary">Continue Shopping</button></a>
          <a href="/orders"><button className="btn btn-primary">View Orders</button></a>
        </div>
      </div>
    );
  }

  return (
    <div style={{ maxWidth: 500 }}>
      <h1 style={{ marginBottom: '1.5rem', fontSize: '1.6rem' }}>Checkout</h1>

      {cart.length === 0 && (
        <div className="card">
          <p>Your cart is empty. <a href="/">Browse products</a></p>
        </div>
      )}

      {cart.length > 0 && (
        <>
          <div className="card">
            <h2 style={{ marginBottom: '1rem', fontSize: '1rem' }}>Order Summary</h2>
            <table>
              <tbody>
                {cart.map((item) => (
                  <tr key={item.sku}>
                    <td>{item.name}</td>
                    <td>× {item.quantity}</td>
                    <td style={{ textAlign: 'right' }}>${(item.price * item.quantity).toFixed(2)}</td>
                  </tr>
                ))}
                <tr>
                  <td colSpan={2}><strong>Total</strong></td>
                  <td style={{ textAlign: 'right' }}><strong>${total.toFixed(2)}</strong></td>
                </tr>
              </tbody>
            </table>
          </div>

          <div className="card">
            <h2 style={{ marginBottom: '1rem', fontSize: '1rem' }}>Payment</h2>
            {error && <div className="error-msg">{error}</div>}
            <form onSubmit={handleSubmit}>
              <label>Card Number</label>
              <input
                type="text"
                value={cardNumber}
                onChange={(e) => setCardNumber(e.target.value)}
                placeholder="4111111111111111"
                maxLength={16}
                required
              />
              <p style={{ fontSize: '0.8rem', color: '#888', marginBottom: '1rem' }}>
                Use any 16-digit number. Set PAYMENT_FAILURE_RATE=100 to demo a declined payment.
              </p>
              <button className="btn btn-primary" type="submit" disabled={submitting} style={{ width: '100%' }}>
                {submitting ? 'Processing...' : `Pay $${total.toFixed(2)}`}
              </button>
            </form>
          </div>
        </>
      )}
    </div>
  );
}

export default function CheckoutPage() {
  return (
    <Suspense fallback={<p>Loading...</p>}>
      <CheckoutForm />
    </Suspense>
  );
}
