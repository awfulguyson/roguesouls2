import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'game_world_screen.dart';

class CharacterCreationScreen extends StatefulWidget {
  final String accountId;
  final bool isTemporary;

  const CharacterCreationScreen({
    super.key,
    required this.accountId,
    this.isTemporary = true,
  });

  @override
  State<CharacterCreationScreen> createState() =>
      _CharacterCreationScreenState();
}

class _CharacterCreationScreenState extends State<CharacterCreationScreen> {
  final _nameController = TextEditingController();
  final _apiService = ApiService();
  bool _isLoading = false;
  String _selectedSpriteType = 'char-1';

  Future<void> _createCharacter() async {
    if (_nameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a character name')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final character = await _apiService.createCharacter(
        widget.accountId,
        _nameController.text,
        _selectedSpriteType,
      );

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => GameWorldScreen(
            characterId: character['id'] as String,
            characterName: character['name'] as String,
            spriteType: character['spriteType'] as String? ?? 'char-1',
            isTemporary: widget.isTemporary,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Character creation failed: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Character')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Create Your Character',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
              ),
              if (widget.isTemporary) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange),
                  ),
                  child: const Text(
                    'Free Account - Limited features (no grouping, trading, etc.)',
                    style: TextStyle(color: Colors.orange, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
              const SizedBox(height: 48),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Character Name',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _createCharacter(),
              ),
              const SizedBox(height: 32),
              const Text(
                'Choose Character Sprite',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedSpriteType = 'char-1';
                      });
                    },
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: _selectedSpriteType == 'char-1' 
                              ? Colors.blue 
                              : Colors.grey,
                          width: _selectedSpriteType == 'char-1' ? 3 : 1,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.asset(
                          'assets/char-1.png',
                          fit: BoxFit.cover,
                          width: 120,
                          height: 120,
                          errorBuilder: (context, error, stackTrace) {
                            return const Center(child: Text('char-1'));
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 24),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedSpriteType = 'char-2';
                      });
                    },
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: _selectedSpriteType == 'char-2' 
                              ? Colors.blue 
                              : Colors.grey,
                          width: _selectedSpriteType == 'char-2' ? 3 : 1,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.asset(
                          'assets/char-2.png',
                          fit: BoxFit.cover,
                          width: 120,
                          height: 120,
                          errorBuilder: (context, error, stackTrace) {
                            return const Center(child: Text('char-2'));
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isLoading ? null : _createCharacter,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 48,
                    vertical: 16,
                  ),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator()
                    : const Text('Create Character'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }
}

