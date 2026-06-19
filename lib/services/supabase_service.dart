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
}
