import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config.dart';
import 'supabase_service.dart';

class ChatApiService {
  static final String baseUrl = AppConfig.chatApiBaseUrl;

  // Without a timeout, http.get/post will hang indefinitely if the backend is
  // slow, cold-starting, or unreachable — leaving callers' `await` stuck
  // forever with no exception ever thrown.
  static const _timeout = Duration(seconds: 15);

  // getInsights() does heavier server-side aggregation (7/30/90-day trend
  // computation across several vitals) than the other endpoints, so it needs
  // more headroom.
  static const _insightsTimeout = Duration(seconds: 20);

  // /chat runs an LLM agent that decides which tool(s) to call, waits on
  // those tool results, then generates the final reply — confirmed via
  // backend timing logs to legitimately take 20-30+ seconds on the
  // tool-routing step alone (see graph.py's [TIMING] logs). 15s was too
  // aggressive and was cutting off requests that would have succeeded.
  static const _chatTimeout = Duration(seconds: 60);

  static String? get _userId => SupabaseService.currentUser?.id;

  static Map<String, dynamic> _decodeOrThrow(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Request failed (${response.statusCode}): ${response.body}',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Unexpected response shape: ${response.body}');
    }
    return decoded;
  }

  static Future<Map<String, dynamic>> chat(
    String message,
    String? conversationId,
  ) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/chat'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'message': message,
            'user_id': _userId ?? 'anonymous',
            'conversation_id': conversationId,
          }),
        )
        .timeout(_chatTimeout);
    return _decodeOrThrow(response);
  }

  static Future<Map<String, dynamic>> getConversations() async {
    final userId = _userId;
    if (userId == null) return {'conversations': []};
    final response = await http
        .get(Uri.parse('$baseUrl/history/$userId'))
        .timeout(_timeout);
    return _decodeOrThrow(response);
  }

  static Future<Map<String, dynamic>> getMessages(String conversationId) async {
    final response = await http
        .get(Uri.parse('$baseUrl/history/messages/$conversationId'))
        .timeout(_timeout);
    return _decodeOrThrow(response);
  }

  /// Dynamic AI-assist header data: headline, subtext, and key-change cards,
  /// computed server-side from real DB trends for the given range.
  static Future<Map<String, dynamic>> getInsights(String range) async {
    final userId = _userId;
    if (userId == null) {
      return {
        'headline_parts': [
          {'text': 'Sign in to see your trends', 'highlight': false},
        ],
        'subtext': '',
        'updates': [],
      };
    }
    final response = await http
        .get(Uri.parse('$baseUrl/insights/$userId?range=$range'))
        .timeout(_insightsTimeout);
    return _decodeOrThrow(response);
  }
}
