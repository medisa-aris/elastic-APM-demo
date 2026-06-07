import axios from 'axios';

const baseURL = process.env.ORDER_SERVICE_URL || 'http://localhost:8080';

const client = axios.create({ baseURL, timeout: 10000 });

export interface OrderItem {
  sku: string;
  quantity: number;
  name?: string;
  price?: number;
}

export interface Order {
  id: string;
  items: string;
  paymentId: string;
  status: string;
  totalAmount: number;
  createdAt: string;
  updatedAt: string;
}

export const orderClient = {
  create: (items: OrderItem[], paymentId: string, totalAmount: number) =>
    client.post<Order>('/orders', { items, paymentId, totalAmount }),
  get: (id: string) => client.get<Order>(`/orders/${id}`),
  list: () => client.get<Order[]>('/orders'),
  refund: (id: string) => client.post<Order>(`/orders/${id}/refund`),
};
