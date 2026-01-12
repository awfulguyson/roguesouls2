import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'character_creation_screen.dart';
import 'game_world_screen.dart';

class CharacterSelectScreen extends StatefulWidget {
  final String accountId;
  final List<dynamic> characters;
  final bool isTemporary;

  const CharacterSelectScreen({
    super.key,
    required this.accountId,
    required this.characters,
    this.isTemporary = true,
  });

  @override
  State<CharacterSelectScreen> createState() => _CharacterSelectScreenState();
}

class _CharacterSelectScreenState extends State<CharacterSelectScreen> {
  final _apiService = ApiService();
  late List<dynamic> _characters;

  @override
  void initState() {
    super.initState();
    _characters = List.from(widget.characters);
  }

  Future<void> _deleteCharacter(String characterId, String characterName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Character'),
        content: Text('Are you sure you want to delete "$characterName"? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _apiService.deleteCharacter(characterId);
      if (mounted) {
        setState(() {
          _characters.removeWhere((char) => char['id'] == characterId);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Character deleted')),
        );
        
        // If no characters left, show message and let user create new character
        if (_characters.isEmpty) {
          // Show dialog explaining they need to create a character
          WidgetsBinding.instance.addPostFrameCallback((_) {
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (context) => AlertDialog(
                title: const Text('No Characters'),
                content: const Text('You have no characters. Please create one to continue.'),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop(); // Close dialog
                      // Navigate to character creation
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (context) => CharacterCreationScreen(
                            accountId: widget.accountId,
                            isTemporary: widget.isTemporary,
                          ),
                        ),
                      );
                    },
                    child: const Text('Create Character'),
                  ),
                ],
              ),
            );
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete character: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Select Character')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text(
              'Select Your Character',
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
                  'Free Account - Characters are not saved',
                  style: TextStyle(color: Colors.orange, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
            const SizedBox(height: 24),
            if (_characters.isEmpty)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'No characters found',
                        style: TextStyle(fontSize: 18),
                      ),
                      const SizedBox(height: 24),
                      OutlinedButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => CharacterCreationScreen(
                                accountId: widget.accountId,
                                isTemporary: widget.isTemporary,
                              ),
                            ),
                          ).then((_) {
                            _refreshCharacters();
                          });
                        },
                        child: const Text('Create Character'),
                      ),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: 0.75,
                  ),
                  itemCount: _characters.length,
                  itemBuilder: (context, index) {
                    final char = _characters[index];
                    return Card(
                      elevation: 4,
                      child: InkWell(
                        onTap: () {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (context) => GameWorldScreen(
                                characterId: char['id'] as String,
                                characterName: char['name'] as String,
                                spriteType: char['spriteType'] as String? ?? 'char-1',
                                isTemporary: widget.isTemporary,
                              ),
                            ),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // Character name (centered above sprite)
                              Flexible(
                                child: Text(
                                  char['name'] as String,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(height: 8),
                              // Sprite preview (top-left 512x512 only)
                              SizedBox(
                                width: 100,
                                height: 100,
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.grey.shade300),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.asset(
                                      'assets/${char['spriteType'] ?? 'char-1'}.png',
                                      fit: BoxFit.cover,
                                      alignment: Alignment.topLeft,
                                      errorBuilder: (context, error, stackTrace) {
                                        return const Center(child: Icon(Icons.person));
                                      },
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              IconButton(
                                constraints: const BoxConstraints(),
                                padding: EdgeInsets.zero,
                                onPressed: () => _deleteCharacter(
                                  char['id'] as String,
                                  char['name'] as String,
                                ),
                                icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                                tooltip: 'Delete character',
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            if (_characters.isNotEmpty) ...[
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => CharacterCreationScreen(
                        accountId: widget.accountId,
                        isTemporary: widget.isTemporary,
                      ),
                    ),
                  ).then((_) {
                    // Refresh character list when returning from creation
                    _refreshCharacters();
                  });
                },
                child: const Text('Create New Character'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _refreshCharacters() async {
    try {
      final characters = await _apiService.getCharacters(widget.accountId);
      if (mounted) {
        setState(() {
          _characters = characters;
        });
      }
    } catch (e) {
      // Silently fail - user can manually refresh
    }
  }
}

