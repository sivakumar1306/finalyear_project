import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../config.dart';
import 'supabase_service.dart';

class ChatApiService {
  static const _serverUrlKey = 'agent_server_url';
  static String _baseUrl = AppConfig.chatApiBaseUrl;

  static String get baseUrl {
    if (_baseUrl.isEmpty) {
      throw Exception('AI server address not set');
    }
    return _baseUrl;
  }

  static bool get hasServerUrl => _baseUrl.isNotEmpty;

  /// The current address, for pre-filling the edit dialog.
  static String get serverUrl => _baseUrl;

  /// Loads the address saved from the AI Assist server dialog, if any.
  static Future<void> loadServerUrl() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_serverUrlKey) ?? '';
      if (saved.isNotEmpty) _baseUrl = saved;
    } catch (_) {}
  }

  /// Accepts `192.168.1.5`, `192.168.1.5:8000` or a full URL and stores the
  /// normalised `http://host:port/api/v1` form. Empty input clears it.
  static Future<String> setServerUrl(String input) async {
    var url = input.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    if (url.isNotEmpty) {
      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        url = 'http://$url';
      }
      final uri = Uri.parse(url);
      if (!uri.hasPort && uri.scheme == 'http') {
        url = uri.replace(port: 8000).toString();
      }
      if (!url.endsWith('/api/v1')) url = '$url/api/v1';
    }
    _baseUrl = url.isEmpty ? AppConfig.chatApiBaseUrl : url;
    final prefs = await SharedPreferences.getInstance();
    if (url.isEmpty) {
      await prefs.remove(_serverUrlKey);
    } else {
      await prefs.setString(_serverUrlKey, url);
    }
    return _baseUrl;
  }

  // Without a timeout, http.get/post will hang indefinitely if the backend is
  // slow, cold-starting, or unreachable — leaving callers' `await` stuck
  // forever with no exception ever thrown.
  static const _timeout = Duration(seconds: 15);

  // getInsights() does heavier server-side aggregation (7/30/90-day trend
  // computation across several vitals) than the other endpoints, so it needs
  // more headroom.
  static const _insightsTimeout = Duration(seconds: 120);

  // /chat runs an LLM agent that decides which tool(s) to call, waits on
  // those tool results, then generates the final reply — confirmed via
  // backend timing logs to legitimately take 20-30+ seconds on the
  // tool-routing step alone (see graph.py's [TIMING] logs). 15s was too
  // aggressive and was cutting off requests that would have succeeded.
  static const _chatTimeout = Duration(seconds: 60);

  static String? get _userId => SupabaseService.currentUser?.id;

  static Map<String, String> get _authHeaders {
    final token = SupabaseService.accessToken;
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

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
          headers: _authHeaders,
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
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/history/$userId'), headers: _authHeaders)
          .timeout(_timeout);
      return _decodeOrThrow(response);
    } catch (_) {
      return {'conversations': []};
    }
  }

  static Future<Map<String, dynamic>> getMessages(String conversationId) async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/history/messages/$conversationId'),
            headers: _authHeaders,
          )
          .timeout(_timeout);
      return _decodeOrThrow(response);
    } catch (_) {
      return {'messages': []};
    }
  }

  /// Dynamic AI-assist header data: headline, subtext, and key-change cards,
  /// computed server-side from real DB trends over a fixed window (backend
  /// caps at MAX_INSIGHT_DAYS — see health.py). No range param anymore: the
  /// app has no range selector, and the backend reports how many days of
  /// real data it actually used via the `days_used` field in the response.
  static Future<Map<String, dynamic>> getInsights() async {
    final userId = _userId;
    final token = SupabaseService.accessToken;
    if (userId == null || token == null) {
      return {
        'headline_parts': [
          {'text': 'Sign in to see your trends', 'highlight': false},
        ],
        'subtext': '',
        'updates': [],
      };
    }
    // Resilient like getConversations/getMessages: a dead/renamed backend
    // domain (Railway 404 "Application not found") must show the fallback
    // card, not flood app_incidents via the FutureBuilder zone.
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/insights/$userId'), headers: _authHeaders)
          .timeout(_insightsTimeout);
      return _decodeOrThrow(response);
    } catch (e) {
      return {
        'headline_parts': [
          {
            'text': 'Your trends will appear here once we have enough recent readings.',
            'highlight': false
          },
        ],
        'subtext': '',
        'updates': [],
        'error': e.toString(),
      };
    }
  }
}
