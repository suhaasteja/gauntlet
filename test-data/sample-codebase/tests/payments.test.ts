import { createPaymentIntent, confirmPayment } from '../src/api/payments';

describe('Payment API', () => {
  it('should create a payment intent', async () => {
    const req = {
      body: {
        amount: 1000,
        currency: 'usd',
        userId: 'user_123'
      }
    };
    const res = {
      json: jest.fn()
    };

    await createPaymentIntent(req, res);

    expect(res.json).toHaveBeenCalled();
  });

  it('should confirm a payment', async () => {
    const req = {
      body: {
        paymentIntentId: 'pi_123'
      }
    };
    const res = {
      json: jest.fn()
    };

    await confirmPayment(req, res);

    expect(res.json).toHaveBeenCalled();
  });
});
