import { Router } from 'express';
import { inventoryClient } from '../clients/inventoryClient';

const router = Router();

router.get('/', async (req, res, next) => {
  try {
    const { data } = await inventoryClient.list();
    res.json(data);
  } catch (err) {
    next(err);
  }
});

router.get('/:sku', async (req, res, next) => {
  try {
    const { data } = await inventoryClient.get(req.params.sku);
    res.json(data);
  } catch (err) {
    next(err);
  }
});

export default router;
