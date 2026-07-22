import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'supabase_service.dart';

class ChatApiService {
  static final String baseUrl =
      'https://vtialringbackendversion1-production.up.railway.app/api/v1';

  static String? get _userId => SupabaseService.currentUser?.id;

  static Future<Map<String, dynamic>> chat(
    String message,
    String? conversationId,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/chat'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'message': message,
        'user_id': _userId ?? 'anonymous',
        'conversation_id': conversationId,
      }),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> getConversations() async {
    final userId = _userId;
    if (userId == null) return {'conversations': []};
    final response = await http.get(Uri.parse('$baseUrl/history/$userId'));
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> getMessages(String conversationId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/history/messages/$conversationId'),
    );
    return jsonDecode(response.body);
  }
}
