const userRequests = new Map<string, number[]>();

export function rateLimitMiddleware(req: any, res: any, next: any) {
  const userId = req.user?.id || req.ip;
  const now = Date.now();
  const windowMs = 60 * 1000;

  if (!userRequests.has(userId)) {
    userRequests.set(userId, []);
  }

  const requests = userRequests.get(userId)!;
  const recentRequests = requests.filter(timestamp => now - timestamp < windowMs);

  if (recentRequests.length >= 100) {
    return res.status(429).json({ error: 'Too many requests' });
  }

  recentRequests.push(now);
  userRequests.set(userId, recentRequests);

  next();
}
