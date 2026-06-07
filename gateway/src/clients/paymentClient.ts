import axios from 'axios';

const baseURL = process.env.PAYMENT_SERVICE_URL || 'http://localhost:8081';

const client = axios.create({ baseURL, timeout: 10000 });

export interface PaymentResponse {
  payment_id: string;
  status: string;
  amount: number;
  order_ref?: string;
}

export const paymentClient = {
  process: (orderRef: string, amount: number, cardNumber: string) =>
    client.post<PaymentResponse>('/payments', {
      order_ref: orderRef,
      amount,
      card_number: cardNumber,
    }),
  refund: (paymentId: string) =>
    client.post<PaymentResponse>('/payments/refund', { payment_id: paymentId }),
  get: (paymentId: string) => client.get<PaymentResponse>(`/payments/${paymentId}`),
};
