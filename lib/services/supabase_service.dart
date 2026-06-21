import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static const _url = 'https://eixcdjvfbwrziudieodr.supabase.co';
  static const _anonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVpeGNkanZmYndyeml1ZGllb2RyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODAzMTUzOTcsImV4cCI6MjA5NTg5MTM5N30.7rxoCLO39zQv1ExFL3IXp0JWySt-_p1iq7CEScufdXA';

  static Future<void> initialize() async {
    await Supabase.initialize(url: _url, anonKey: _anonKey);
  }

  static SupabaseClient get client => Supabase.instance.client;

  static User? get currentUser => client.auth.currentUser;

  static Future<AuthResponse> signUp(String email, String password) {
    return client.auth.signUp(email: email, password: password);
  }

  static Future<AuthResponse> signIn(String email, String password) {
    return client.auth.signInWithPassword(email: email, password: password);
  }

  static Future<void> signOut() => client.auth.signOut();

  static Future<Map<String, dynamic>?> getProfile(String userId) async {
    return client
        .from('user_profiles')
        .select()
        .eq('id', userId)
        .maybeSingle();
  }

  static Future<void> upsertProfile({
    required String userId,
    required String fullName,
    required int age,
    required String gender,
    required int heightCm,
    required double weightKg,
  }) async {
    await client.from('user_profiles').upsert({
      'id': userId,
      'full_name': fullName,
      'age': age,
      'gender': gender,
      'height_cm': heightCm,
      'weight_kg': weightKg,
    });
  }

  static bool get isLoggedIn => currentUser != null;

  static Future<void> upsertSteps({
    required String userId,
    required DateTime date,
    required int steps,
    required int calories,
    required double distanceM,
  }) async {
    final dateStr =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    await client.from('user_steps').upsert({
      'user_id': userId,
      'date': dateStr,
      'steps': steps,
      'calories': calories,
      'distance_m': distanceM,
      'synced_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'user_id,date');
  }

  static Future<List<Map<String, dynamic>>> getStepsHistory({
    required String userId,
    required DateTime from,
    required DateTime to,
  }) async {
    String fmt(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final data = await client
        .from('user_steps')
        .select()
        .eq('user_id', userId)
        .gte('date', fmt(from))
        .lte('date', fmt(to))
        .order('date', ascending: true);
    return List<Map<String, dynamic>>.from(data);
  }

  static Future<void> upsertHr({
    required String userId,
    required DateTime date,
    required int avgHr,
    required int minHr,
    required int maxHr,
    required int sampleCount,
  }) async {
    final dateStr =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    await client.from('user_hr').upsert({
      'user_id': userId,
      'date': dateStr,
      'avg_hr': avgHr,
      'min_hr': minHr,
      'max_hr': maxHr,
      'sample_count': sampleCount,
      'synced_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'user_id,date');
  }

  static Future<Map<String, dynamic>?> getTodayHr(String userId) async {
    final now = DateTime.now();
    final dateStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    return client
        .from('user_hr')
        .select()
        .eq('user_id', userId)
        .eq('date', dateStr)
        .maybeSingle();
  }

  static Future<Map<String, dynamic>?> getHrForDate(
      String userId, DateTime date) async {
    final dateStr =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return client
        .from('user_hr')
        .select()
        .eq('user_id', userId)
        .eq('date', dateStr)
        .maybeSingle();
  }

  static Future<List<Map<String, dynamic>>> getHrHistory({
    required String userId,
    required DateTime from,
    required DateTime to,
  }) async {
    String fmt(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final data = await client
        .from('user_hr')
        .select()
        .eq('user_id', userId)
        .gte('date', fmt(from))
        .lte('date', fmt(to))
        .order('date', ascending: true);
    return List<Map<String, dynamic>>.from(data);
  }

  // ── SpO2 ──────────────────────────────────────────────────────────────────

  static Future<void> upsertSpo2({
    required String userId,
    required DateTime date,
    required int avgSpo2,
    required int minSpo2,
    required int maxSpo2,
    required int sampleCount,
  }) async {
    final dateStr =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    await client.from('user_spo2').upsert({
      'user_id': userId,
      'date': dateStr,
      'avg_spo2': avgSpo2,
      'min_spo2': minSpo2,
      'max_spo2': maxSpo2,
      'sample_count': sampleCount,
      'synced_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'user_id,date');
  }

  static Future<Map<String, dynamic>?> getTodaySpo2(String userId) async {
    final now = DateTime.now();
    final dateStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    return client
        .from('user_spo2')
        .select()
        .eq('user_id', userId)
        .eq('date', dateStr)
        .maybeSingle();
  }

  static Future<Map<String, dynamic>?> getSpo2ForDate(
      String userId, DateTime date) async {
    final dateStr =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return client
        .from('user_spo2')
        .select()
        .eq('user_id', userId)
        .eq('date', dateStr)
        .maybeSingle();
  }

  static Future<List<Map<String, dynamic>>> getSpo2History({
    required String userId,
    required DateTime from,
    required DateTime to,
  }) async {
    String fmt(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final data = await client
        .from('user_spo2')
        .select()
        .eq('user_id', userId)
        .gte('date', fmt(from))
        .lte('date', fmt(to))
        .order('date', ascending: true);
    return List<Map<String, dynamic>>.from(data);
  }
}
