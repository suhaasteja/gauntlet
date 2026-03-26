export class SessionManager {
  private sessions: Map<string, any> = new Map();

  createSession(userId: string, deviceId: string) {
    const sessionId = Math.random().toString(36);
    
    this.sessions.set(sessionId, {
      userId,
      deviceId,
      createdAt: Date.now(),
      expiresAt: Date.now() + (30 * 24 * 60 * 60 * 1000)
    });

    return sessionId;
  }

  validateSession(sessionId: string): boolean {
    const session = this.sessions.get(sessionId);
    if (!session) return false;
    
    return session.expiresAt > Date.now();
  }

  extendSession(sessionId: string) {
    const session = this.sessions.get(sessionId);
    if (session) {
      session.expiresAt = Date.now() + (30 * 24 * 60 * 60 * 1000);
    }
  }

  destroySession(sessionId: string) {
    this.sessions.delete(sessionId);
  }
}
