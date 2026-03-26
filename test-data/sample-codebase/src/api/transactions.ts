import { db } from '../utils/database';

export async function getTransactions(req: any, res: any) {
  const { userId } = req.user;
  const { startDate, endDate, status } = req.query;

  let query: any = { userId };

  if (startDate || endDate) {
    query.createdAt = {};
    if (startDate) query.createdAt.$gte = new Date(startDate);
    if (endDate) query.createdAt.$lte = new Date(endDate);
  }

  if (status) {
    query.status = status;
  }

  const transactions = await db.transactions.find(query).sort({ createdAt: -1 });

  res.json({ transactions });
}

export async function exportTransactions(req: any, res: any) {
  const { userId } = req.user;

  const transactions = await db.transactions.find({ userId });

  const csv = transactions.map(t => 
    `${t.id},${t.amount},${t.currency},${t.status},${t.createdAt}`
  ).join('\n');

  res.setHeader('Content-Type', 'text/csv');
  res.setHeader('Content-Disposition', 'attachment; filename=transactions.csv');
  res.send(csv);
}
