import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'game_world_screen.dart';

class CharacterCreationScreen extends StatefulWidget {
  final String accountId;

  const CharacterCreationScreen({super.key, required this.accountId});

  @override
  State<CharacterCreationScreen> createState() =>
      _CharacterCreationScreenState();
}

class _CharacterCreationScreenState extends State<CharacterCreationScreen> {
  final _nameController = TextEditingController();
  final _apiService = ApiService();
  bool _isLoading = false;

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
      );

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => GameWorldScreen(
            characterId: character['id'] as String,
            characterName: character['name'] as String,
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
              const SizedBox(height: 48),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Character Name',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _createCharacter(),
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

