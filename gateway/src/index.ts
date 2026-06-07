// tracing MUST be the first import — initializes OTel SDK before any instrumented code loads
import './tracing';

import express from 'express';
import cors from 'cors';

import productsRouter from './routes/products';
import ordersRouter from './routes/orders';
import purchaseRouter from './routes/purchase';
import refundRouter from './routes/refund';
import { errorHandler } from './middleware/errorHandler';

const app = express();

app.use(cors());
app.use(express.json());

app.get('/health', (req, res) => {
  res.json({ status: 'ok', service: 'gateway' });
});

app.use('/api/products', productsRouter);
app.use('/api/orders', ordersRouter);
app.use('/api/purchase', purchaseRouter);
app.use('/api/refund', refundRouter);

app.use(errorHandler);

const port = parseInt(process.env.PORT || '4000', 10);
app.listen(port, () => {
  console.log(`gateway listening on :${port}`);
});
