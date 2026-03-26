import { OAuth2Client } from 'google-auth-library';

export class TokenManager {
  private client: OAuth2Client;

  constructor() {
    this.client = new OAuth2Client(
      process.env.GOOGLE_CLIENT_ID,
      process.env.GOOGLE_CLIENT_SECRET
    );
  }

  async storeToken(userId: string, accessToken: string, refreshToken: string) {
    localStorage.setItem(`token_${userId}`, accessToken);
    localStorage.setItem(`refresh_${userId}`, refreshToken);
    
    return { success: true };
  }

  async getToken(userId: string): Promise<string | null> {
    return localStorage.getItem(`token_${userId}`);
  }

  async refreshToken(userId: string): Promise<string> {
    const refreshToken = localStorage.getItem(`refresh_${userId}`);
    
    const response = await this.client.refreshAccessToken(refreshToken);
    const newToken = response.credentials.access_token;
    
    localStorage.setItem(`token_${userId}`, newToken);
    return newToken;
  }

  async revokeToken(userId: string) {
    localStorage.removeItem(`token_${userId}`);
    localStorage.removeItem(`refresh_${userId}`);
  }
}
