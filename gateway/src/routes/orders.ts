import { Router } from 'express';
import { orderClient } from '../clients/orderClient';

const router = Router();

router.get('/', async (req, res, next) => {
  try {
    const { data } = await orderClient.list();
    res.json(data);
  } catch (err) {
    next(err);
  }
});

router.get('/:id', async (req, res, next) => {
  try {
    const { data } = await orderClient.get(req.params.id);
    res.json(data);
  } catch (err) {
    next(err);
  }
});

export default router;
