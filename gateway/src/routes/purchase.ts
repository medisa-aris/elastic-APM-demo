import { Router } from 'express';
import { AxiosError } from 'axios';
import { inventoryClient, ReserveItem } from '../clients/inventoryClient';
import { paymentClient } from '../clients/paymentClient';
import { orderClient } from '../clients/orderClient';

const router = Router();

interface CartItem {
  sku: string;
  quantity: number;
}

interface PurchaseRequest {
  items: CartItem[];
  payment: {
    card_number: string;
  };
}

// Flow 1: Browse → Reserve Inventory → Process Payment → Create Order
router.post('/', async (req, res, next) => {
  const { items, payment }: PurchaseRequest = req.body;

  if (!items || !Array.isArray(items) || items.length === 0) {
    res.status(400).json({ error: 'items array is required' });
    return;
  }
  if (!payment?.card_number) {
    res.status(400).json({ error: 'payment.card_number is required' });
    return;
  }

  const reservedItems: ReserveItem[] = [];

  try {
    // Step 1: Verify and enrich each item from inventory
    const enrichedItems = await Promise.all(
      items.map(async (item) => {
        const { data } = await inventoryClient.get(item.sku);
        if (data.available < item.quantity) {
          throw { status: 409, message: `Insufficient stock for ${item.sku}` };
        }
        return { ...item, name: data.name, price: data.price };
      })
    );

    // Step 2: Reserve inventory
    const reserveItems: ReserveItem[] = enrichedItems.map((i) => ({
      sku: i.sku,
      quantity: i.quantity,
    }));
    await inventoryClient.reserve(reserveItems);
    reservedItems.push(...reserveItems);

    // Step 3: Process payment
    const totalAmount = enrichedItems.reduce((sum, i) => sum + i.price * i.quantity, 0);
    const tempOrderRef = `pending-${Date.now()}`;
    let paymentId: string;

    try {
      const { data: paymentData } = await paymentClient.process(
        tempOrderRef,
        totalAmount,
        payment.card_number
      );
      paymentId = paymentData.payment_id;
    } catch (paymentErr) {
      // Payment failed — release reserved inventory
      await inventoryClient.restock(reservedItems).catch(() => {});
      throw paymentErr;
    }

    // Step 4: Create order
    const { data: order } = await orderClient.create(enrichedItems, paymentId, totalAmount);

    res.status(201).json({
      orderId: order.id,
      paymentId,
      status: 'success',
      totalAmount,
      items: enrichedItems,
    });
  } catch (err) {
    if (err instanceof AxiosError && err.response) {
      const status = err.response.status;
      const detail = err.response.data;
      res.status(status).json({
        error: detail?.detail || detail?.error || 'Upstream service error',
        service: err.config?.baseURL,
        upstream_status: status,
      });
      return;
    }
    const typed = err as { status?: number; message?: string };
    if (typed.status) {
      res.status(typed.status).json({ error: typed.message });
      return;
    }
    next(err);
  }
});

export default router;
