import axios from 'axios';

const baseURL = process.env.INVENTORY_SERVICE_URL || 'http://localhost:8082';

const client = axios.create({ baseURL, timeout: 10000 });

export interface InventoryItem {
  sku: string;
  name: string;
  description: string;
  price: number;
  quantity: number;
  reserved: number;
  available: number;
}

export interface ReserveItem {
  sku: string;
  quantity: number;
}

export const inventoryClient = {
  list: () => client.get<InventoryItem[]>('/inventory'),
  get: (sku: string) => client.get<InventoryItem>(`/inventory/${sku}`),
  reserve: (items: ReserveItem[]) => client.post('/inventory/reserve', { items }),
  restock: (items: ReserveItem[]) => client.post('/inventory/restock', { items }),
};
