import { Express, Request, Response } from 'express';

// In-memory storage for MVP (TODO: Replace with database)
interface Character {
  id: string;
  accountId: string;
  name: string;
  spriteType: string;
  positionX: number;
  positionY: number;
  createdAt: string;
  isTemporary?: boolean; // Track if character belongs to temporary account
  isDead?: boolean; // Track if character is dead
}

export const charactersStore: Map<string, Character> = new Map();
const temporaryAccounts: Set<string> = new Set(); // Track temporary account IDs

export function setupRoutes(app: Express) {
  // Health check
  app.get('/health', (req: Request, res: Response) => {
    res.json({ status: 'ok', message: 'RogueSouls server is running' });
  });

  // Create temporary account (no email/password required)
  app.post('/api/accounts/temporary', async (req: Request, res: Response) => {
    try {
      // TODO: Save to database
      // For MVP, generate a temporary account ID
      const accountId = 'temp_' + Date.now() + '_' + Math.random().toString(36).substring(7);
      
      // Mark as temporary account
      temporaryAccounts.add(accountId);
      
      const account = {
        id: accountId,
        type: 'temporary',
        createdAt: new Date().toISOString()
      };

      res.status(201).json(account);
    } catch (error) {
      console.error('Temporary account creation error:', error);
      res.status(500).json({ error: 'Internal server error' });
    }
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
      const { accountId, name, spriteType } = req.body;
      
      if (!name) {
        return res.status(400).json({ error: 'Character name is required' });
      }

      if (!accountId) {
        return res.status(400).json({ error: 'Account ID is required' });
      }

      if (!spriteType) {
        return res.status(400).json({ error: 'Sprite type is required' });
      }

      // Check if this is a temporary account
      const isTemporary = temporaryAccounts.has(accountId);
      
      // TODO: Save to database
      const character: Character = {
        id: 'char_' + Date.now() + '_' + Math.random().toString(36).substring(7),
        accountId: accountId,
        name: name,
        spriteType: spriteType,
        positionX: 0,
        positionY: 0,
        createdAt: new Date().toISOString(),
        isTemporary: isTemporary
      };

      // Store in memory (temporary accounts will be cleared on server restart)
      charactersStore.set(character.id, character);

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
      
      if (!accountId) {
        return res.status(400).json({ error: 'Account ID is required' });
      }
      
      // TODO: Fetch from database
      // For MVP, filter from in-memory store
      // Temporary accounts still show characters in memory (they just don't persist across server restarts)
      const accountCharacters = Array.from(charactersStore.values())
        .filter(char => char.accountId === accountId);
      
      res.json(accountCharacters);
    } catch (error) {
      console.error('Get characters error:', error);
      res.status(500).json({ error: 'Internal server error' });
    }
  });

  // Mark character as dead
  app.patch('/api/characters/:characterId/dead', async (req: Request, res: Response) => {
    try {
      const characterId = req.params.characterId as string;
      
      if (!characterId) {
        return res.status(400).json({ error: 'Character ID is required' });
      }

      const character = charactersStore.get(characterId);
      if (!character) {
        return res.status(404).json({ error: 'Character not found' });
      }

      character.isDead = true;
      res.json({ success: true, message: 'Character marked as dead' });
    } catch (error) {
      console.error('Mark character dead error:', error);
      res.status(500).json({ error: 'Internal server error' });
    }
  });

  // Delete character
  app.delete('/api/characters/:characterId', async (req: Request, res: Response) => {
    try {
      const characterId = req.params.characterId as string;
      
      if (!characterId) {
        return res.status(400).json({ error: 'Character ID is required' });
      }

      const character = charactersStore.get(characterId);
      if (!character) {
        return res.status(404).json({ error: 'Character not found' });
      }

      charactersStore.delete(characterId);
      res.json({ success: true, message: 'Character deleted' });
    } catch (error) {
      console.error('Delete character error:', error);
      res.status(500).json({ error: 'Internal server error' });
    }
  });
}

