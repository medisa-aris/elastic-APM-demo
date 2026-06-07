'use client';

import { useState, useEffect } from 'react';
import { api, Order } from '@/lib/api';

function statusBadge(status: string) {
  const cls =
    status === 'CONFIRMED' ? 'badge-success' :
    status === 'REFUNDED' ? 'badge-pending' :
    'badge-error';
  return <span className={`badge ${cls}`}>{status}</span>;
}

export default function OrdersPage() {
  const [orders, setOrders] = useState<Order[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [refunding, setRefunding] = useState<string | null>(null);
  const [message, setMessage] = useState('');

  function load() {
    setLoading(true);
    api.getOrders()
      .then(setOrders)
      .catch((e) => setError(e.message))
      .finally(() => setLoading(false));
  }

  useEffect(load, []);

  async function handleRefund(orderId: string) {
    setRefunding(orderId);
    setMessage('');
    setError('');
    try {
      await api.refund(orderId);
      setMessage(`Order ${orderId.slice(0, 8)}... refunded successfully`);
      load();
    } catch (e: unknown) {
      const err = e as { message?: string };
      setError(err.message || 'Refund failed');
    } finally {
      setRefunding(null);
    }
  }

  function parseItems(itemsJson: string): string {
    try {
      const items = JSON.parse(itemsJson);
      return items.map((i: { name?: string; sku: string; quantity: number }) =>
        `${i.name || i.sku} ×${i.quantity}`
      ).join(', ');
    } catch {
      return itemsJson;
    }
  }

  return (
    <div>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '1.5rem' }}>
        <h1 style={{ fontSize: '1.6rem' }}>Orders</h1>
        <button className="btn btn-secondary" onClick={load}>Refresh</button>
      </div>

      {error && <div className="error-msg">{error}</div>}
      {message && <div className="success-msg">{message}</div>}

      {loading && <p>Loading orders...</p>}

      {!loading && orders.length === 0 && (
        <div className="card">
          <p>No orders yet. <a href="/">Place an order</a></p>
        </div>
      )}

      {!loading && orders.length > 0 && (
        <div className="card">
          <table>
            <thead>
              <tr>
                <th>Order ID</th>
                <th>Items</th>
                <th>Total</th>
                <th>Status</th>
                <th>Date</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              {orders.map((order) => (
                <tr key={order.id}>
                  <td><code style={{ fontSize: '0.8rem' }}>{order.id.slice(0, 8)}...</code></td>
                  <td style={{ fontSize: '0.85rem' }}>{parseItems(order.items)}</td>
                  <td>${order.totalAmount?.toFixed(2) || '0.00'}</td>
                  <td>{statusBadge(order.status)}</td>
                  <td style={{ fontSize: '0.8rem', color: '#666' }}>
                    {new Date(order.createdAt).toLocaleString()}
                  </td>
                  <td>
                    {order.status === 'CONFIRMED' && (
                      <button
                        className="btn btn-danger"
                        style={{ fontSize: '0.8rem', padding: '0.3rem 0.8rem' }}
                        disabled={refunding === order.id}
                        onClick={() => handleRefund(order.id)}
                      >
                        {refunding === order.id ? 'Refunding...' : 'Refund'}
                      </button>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
