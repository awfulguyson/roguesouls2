import 'package:flutter/material.dart';
import 'game_world_screen.dart';

class CharacterSelectScreen extends StatelessWidget {
  final String accountId;
  final List<dynamic> characters;

  const CharacterSelectScreen({
    super.key,
    required this.accountId,
    required this.characters,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Select Character')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Select Your Character',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 48),
              if (characters.isEmpty)
                const Text('No characters found')
              else
                ...characters.map((char) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (context) => GameWorldScreen(
                              characterId: char['id'] as String,
                              characterName: char['name'] as String,
                            ),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 48,
                          vertical: 16,
                        ),
                      ),
                      child: Text(char['name'] as String),
                    ),
                  );
                }).toList(),
            ],
          ),
        ),
      ),
    );
  }
}

