import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

class ApiService {
  static String get baseUrl => AppConfig.apiBaseUrl;

  Future<Map<String, dynamic>> createTemporaryAccount() async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/accounts/temporary'),
      headers: {'Content-Type': 'application/json'},
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to create temporary account: ${response.body}');
    }
  }

  Future<Map<String, dynamic>> login(String email, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Login failed: ${response.body}');
    }
  }

  Future<Map<String, dynamic>> createCharacter(String accountId, String name, String spriteType) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/characters'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'accountId': accountId, 'name': name, 'spriteType': spriteType}),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Character creation failed: ${response.body}');
    }
  }

  Future<void> markCharacterDead(String characterId) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/api/characters/$characterId/dead'),
      headers: {'Content-Type': 'application/json'},
    );

    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception('Failed to mark character as dead: ${response.body}');
    }
  }

  Future<void> deleteCharacter(String characterId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/api/characters/$characterId'),
      headers: {'Content-Type': 'application/json'},
    );

    if (response.statusCode != 200) {
      throw Exception('Character deletion failed: ${response.body}');
    }
  }

  Future<List<dynamic>> getCharacters(String accountId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/characters?accountId=$accountId'),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to get characters: ${response.body}');
    }
  }
}

