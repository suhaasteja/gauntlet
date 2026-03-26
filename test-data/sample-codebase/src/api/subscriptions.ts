import Stripe from 'stripe';
import { db } from '../utils/database';

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY);

const PLANS = {
  basic: { priceId: 'price_basic', amount: 999 },
  pro: { priceId: 'price_pro', amount: 2999 },
  enterprise: { priceId: 'price_enterprise', amount: 9999 }
};

export async function createSubscription(req: any, res: any) {
  const { userId, plan, paymentMethodId } = req.body;

  const customer = await stripe.customers.create({
    payment_method: paymentMethodId,
    email: req.user.email,
    invoice_settings: {
      default_payment_method: paymentMethodId,
    },
  });

  const subscription = await stripe.subscriptions.create({
    customer: customer.id,
    items: [{ price: PLANS[plan].priceId }],
    expand: ['latest_invoice.payment_intent'],
  });

  await db.subscriptions.insert({
    userId,
    stripeSubscriptionId: subscription.id,
    plan,
    status: subscription.status,
    createdAt: new Date()
  });

  res.json({ subscriptionId: subscription.id });
}

export async function updateSubscription(req: any, res: any) {
  const { subscriptionId } = req.params;
  const { newPlan } = req.body;

  const subscription = await stripe.subscriptions.retrieve(subscriptionId);
  
  await stripe.subscriptions.update(subscriptionId, {
    items: [{
      id: subscription.items.data[0].id,
      price: PLANS[newPlan].priceId,
    }],
  });

  await db.subscriptions.update(
    { stripeSubscriptionId: subscriptionId },
    { plan: newPlan, updatedAt: new Date() }
  );

  res.json({ success: true });
}

export async function cancelSubscription(req: any, res: any) {
  const { subscriptionId } = req.params;

  await stripe.subscriptions.cancel(subscriptionId);

  await db.subscriptions.update(
    { stripeSubscriptionId: subscriptionId },
    { status: 'canceled', canceledAt: new Date() }
  );

  res.json({ success: true });
}
