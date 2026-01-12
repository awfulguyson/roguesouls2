import { Express, Request, Response } from 'express';

export function setupRoutes(app: Express) {
  // Health check
  app.get('/health', (req: Request, res: Response) => {
    res.json({ status: 'ok', message: 'RogueSouls server is running' });
  });

  // Login endpoint (simplified for MVP - no password hashing yet)
  app.post('/api/auth/login', async (req: Request, res: Response) => {
    try {
      const { email, password } = req.body;
      
      // TODO: Implement actual authentication with database
      // For MVP testing, accept any email/password
      if (!email) {
        return res.status(400).json({ error: 'Email is required' });
      }

      // Mock user for now
      const mockUser = {
        id: '1',
        email: email,
        name: email.split('@')[0]
      };

      res.json({
        token: 'mock_token_' + Date.now(), // TODO: Generate real JWT
        user: mockUser
      });
    } catch (error) {
      console.error('Login error:', error);
      res.status(500).json({ error: 'Internal server error' });
    }
  });

  // Character creation
  app.post('/api/characters', async (req: Request, res: Response) => {
    try {
      const { accountId, name } = req.body;
      
      if (!name) {
        return res.status(400).json({ error: 'Character name is required' });
      }

      // TODO: Save to database
      const character = {
        id: 'char_' + Date.now(),
        accountId: accountId || '1',
        name: name,
        positionX: 0,
        positionY: 0,
        createdAt: new Date().toISOString()
      };

      res.json(character);
    } catch (error) {
      console.error('Character creation error:', error);
      res.status(500).json({ error: 'Internal server error' });
    }
  });

  // Get characters for account
  app.get('/api/characters', async (req: Request, res: Response) => {
    try {
      const accountId = req.query.accountId as string;
      
      // TODO: Fetch from database
      // For MVP, return empty array
      res.json([]);
    } catch (error) {
      console.error('Get characters error:', error);
      res.status(500).json({ error: 'Internal server error' });
    }
  });
}

