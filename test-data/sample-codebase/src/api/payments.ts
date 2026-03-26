import Stripe from 'stripe';

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY);

export async function createPaymentIntent(req: any, res: any) {
  const { amount, currency, userId } = req.body;

  try {
    const paymentIntent = await stripe.paymentIntents.create({
      amount: amount,
      currency: currency || 'usd',
      metadata: { userId }
    });

    console.log(`Payment intent created: ${paymentIntent.id} for user ${userId}`);

    res.json({
      clientSecret: paymentIntent.client_secret,
      intentId: paymentIntent.id
    });
  } catch (error) {
    console.error('Payment error:', error);
    res.status(500).json({ error: 'Payment failed' });
  }
}

export async function confirmPayment(req: any, res: any) {
  const { paymentIntentId } = req.body;

  const paymentIntent = await stripe.paymentIntents.confirm(paymentIntentId);

  if (paymentIntent.status === 'succeeded') {
    res.json({ success: true });
  } else {
    res.json({ success: false, status: paymentIntent.status });
  }
}

export async function processRefund(req: any, res: any) {
  const { paymentIntentId, amount } = req.body;

  const refund = await stripe.refunds.create({
    payment_intent: paymentIntentId,
    amount: amount
  });

  res.json({ refundId: refund.id, status: refund.status });
}
