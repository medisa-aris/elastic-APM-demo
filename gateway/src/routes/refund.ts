import { Router } from 'express';
import { AxiosError } from 'axios';
import { orderClient } from '../clients/orderClient';
import { paymentClient } from '../clients/paymentClient';
import { inventoryClient, ReserveItem } from '../clients/inventoryClient';

const router = Router();

// Flow 2: Find Order → Refund Payment → Restock Inventory → Mark Order Refunded
router.post('/', async (req, res, next) => {
  const { orderId } = req.body;

  if (!orderId) {
    res.status(400).json({ error: 'orderId is required' });
    return;
  }

  try {
    // Step 1: Fetch the order
    const { data: order } = await orderClient.get(orderId);

    if (order.status === 'REFUNDED') {
      res.status(409).json({ error: 'Order already refunded' });
      return;
    }

    // Step 2: Refund the payment
    await paymentClient.refund(order.paymentId);

    // Step 3: Restock inventory
    let items: ReserveItem[] = [];
    try {
      const parsed = JSON.parse(order.items);
      items = parsed.map((i: { sku: string; quantity: number }) => ({
        sku: i.sku,
        quantity: i.quantity,
      }));
    } catch {
      // items parse failed — continue without restock
    }

    if (items.length > 0) {
      await inventoryClient.restock(items).catch(() => {});
    }

    // Step 4: Mark order as refunded
    const { data: updatedOrder } = await orderClient.refund(orderId);

    res.json({
      orderId: updatedOrder.id,
      status: 'refunded',
      paymentId: order.paymentId,
    });
  } catch (err) {
    if (err instanceof AxiosError && err.response) {
      const status = err.response.status;
      const detail = err.response.data;
      res.status(status).json({
        error: detail?.detail || detail?.error || 'Upstream service error',
        upstream_status: status,
      });
      return;
    }
    next(err);
  }
});

export default router;
