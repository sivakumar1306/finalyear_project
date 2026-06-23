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

  // ── Blood Pressure ─────────────────────────────────────────────────────────

  static Future<void> insertBp({
    required String userId,
    required int systolic,
    required int diastolic,
    required DateTime measuredAt,
    String source = 'manual',
  }) async {
    await client.from('user_bp').insert({
      'user_id': userId,
      'systolic': systolic,
      'diastolic': diastolic,
      'measured_at': measuredAt.toUtc().toIso8601String(),
      'source': source,
    });
  }

  static Future<Map<String, dynamic>?> getLatestBp(String userId) async {
    return client
        .from('user_bp')
        .select()
        .eq('user_id', userId)
        .order('measured_at', ascending: false)
        .limit(1)
        .maybeSingle();
  }

  static Future<List<Map<String, dynamic>>> getBpReadings({
    required String userId,
    required DateTime from,
    required DateTime to,
  }) async {
    final data = await client
        .from('user_bp')
        .select()
        .eq('user_id', userId)
        .gte('measured_at', from.toUtc().toIso8601String())
        .lte('measured_at', to.toUtc().toIso8601String())
        .order('measured_at', ascending: true);
    return List<Map<String, dynamic>>.from(data);
  }

  // ── Stress ─────────────────────────────────────────────────────────────────

  static String _stressLabel(int v) {
    if (v < 40) return 'Relaxed';
    if (v < 60) return 'Normal';
    if (v < 80) return 'Elevated';
    return 'High';
  }

  static Future<void> insertStress({
    required String userId,
    required int stressValue,
    required DateTime measuredAt,
    String source = 'manual',
  }) async {
    await client.from('user_stress').insert({
      'user_id': userId,
      'stress_value': stressValue,
      'label': _stressLabel(stressValue),
      'measured_at': measuredAt.toUtc().toIso8601String(),
      'source': source,
    });
  }

  static Future<Map<String, dynamic>?> getLatestStress(String userId) async {
    return client
        .from('user_stress')
        .select()
        .eq('user_id', userId)
        .order('measured_at', ascending: false)
        .limit(1)
        .maybeSingle();
  }

  static Future<List<Map<String, dynamic>>> getStressReadings({
    required String userId,
    required DateTime from,
    required DateTime to,
  }) async {
    final data = await client
        .from('user_stress')
        .select()
        .eq('user_id', userId)
        .gte('measured_at', from.toUtc().toIso8601String())
        .lte('measured_at', to.toUtc().toIso8601String())
        .order('measured_at', ascending: true);
    return List<Map<String, dynamic>>.from(data);
  }

  // ── HRV ────────────────────────────────────────────────────────────────────

  static Future<void> upsertHrv({
    required String userId,
    required DateTime date,
    required int avgHrv,
    required int minHrv,
    required int maxHrv,
    required int sampleCount,
  }) async {
    final dateStr =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    await client.from('user_hrv').upsert({
      'user_id': userId,
      'date': dateStr,
      'avg_hrv': avgHrv,
      'min_hrv': minHrv,
      'max_hrv': maxHrv,
      'sample_count': sampleCount,
      'synced_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'user_id,date');
  }

  static Future<Map<String, dynamic>?> getHrvForDate(
      String userId, DateTime date) async {
    final dateStr =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return client
        .from('user_hrv')
        .select()
        .eq('user_id', userId)
        .eq('date', dateStr)
        .maybeSingle();
  }

  static Future<List<Map<String, dynamic>>> getHrvHistory({
    required String userId,
    required DateTime from,
    required DateTime to,
  }) async {
    String fmt(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final data = await client
        .from('user_hrv')
        .select()
        .eq('user_id', userId)
        .gte('date', fmt(from))
        .lte('date', fmt(to))
        .order('date', ascending: true);
    return List<Map<String, dynamic>>.from(data);
  }

  // ── Temperature ────────────────────────────────────────────────────────────

  static Future<void> insertTempBatch({
    required String userId,
    required List<({DateTime measuredAt, double valueC, String source})> readings,
  }) async {
    if (readings.isEmpty) return;
    await client.from('user_temp').insert(readings
        .map((r) => {
              'user_id': userId,
              'measured_at': r.measuredAt.toUtc().toIso8601String(),
              'value_c': r.valueC,
              'source': r.source,
            })
        .toList());
  }

  static Future<void> insertTemp({
    required String userId,
    required DateTime measuredAt,
    required double valueC,
    String source = 'auto',
  }) async {
    await client.from('user_temp').insert({
      'user_id': userId,
      'measured_at': measuredAt.toUtc().toIso8601String(),
      'value_c': valueC,
      'source': source,
    });
  }

  static Future<List<Map<String, dynamic>>> getTempReadings({
    required String userId,
    required DateTime from,
    required DateTime to,
  }) async {
    final data = await client
        .from('user_temp')
        .select()
        .eq('user_id', userId)
        .gte('measured_at', from.toUtc().toIso8601String())
        .lte('measured_at', to.toUtc().toIso8601String())
        .order('measured_at', ascending: true);
    return List<Map<String, dynamic>>.from(data);
  }

  static Future<Map<String, dynamic>?> getLatestTemp(String userId) async {
    return client
        .from('user_temp')
        .select()
        .eq('user_id', userId)
        .order('measured_at', ascending: false)
        .limit(1)
        .maybeSingle();
  }

  // ── Workouts ──────────────────────────────────────────────────────────────

  static Future<String?> insertWorkout({
    required String userId,
    required String type,
    required DateTime startedAt,
    required DateTime endedAt,
    required int durationS,
    required int steps,
    required int calories,
    required double distanceM,
    required int avgHr,
    required int avgSpo2,
    required int avgBpSbp,
    required int avgBpDbp,
  }) async {
    final data = await client.from('user_workouts').insert({
      'user_id': userId,
      'workout_type': type,
      'started_at': startedAt.toUtc().toIso8601String(),
      'ended_at': endedAt.toUtc().toIso8601String(),
      'duration_s': durationS,
      'steps': steps,
      'calories': calories,
      'distance_m': distanceM,
      'avg_hr': avgHr,
      'avg_spo2': avgSpo2,
      'avg_bp_sbp': avgBpSbp,
      'avg_bp_dbp': avgBpDbp,
    }).select('id').single();
    return data['id'] as String?;
  }

  static Future<List<Map<String, dynamic>>> getWorkoutHistory({
    required String userId,
    required DateTime from,
    required DateTime to,
  }) async {
    final data = await client
        .from('user_workouts')
        .select()
        .eq('user_id', userId)
        .gte('started_at', from.toUtc().toIso8601String())
        .lte('started_at', to.toUtc().toIso8601String())
        .order('started_at', ascending: false);
    return List<Map<String, dynamic>>.from(data);
  }

  // ── Women's Health — Cycles ────────────────────────────────────────────────

  static String _dateStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static Future<List<Map<String, dynamic>>> getCycles(String userId) async {
    final data = await client
        .from('user_cycles')
        .select()
        .eq('user_id', userId)
        .order('period_start', ascending: false);
    return List<Map<String, dynamic>>.from(data);
  }

  static Future<void> saveCycle({
    required String userId,
    required DateTime periodStart,
    required int cycleLength,
    required int periodLength,
    String? notes,
  }) async {
    await client.from('user_cycles').upsert({
      'user_id': userId,
      'period_start': _dateStr(periodStart),
      'cycle_length': cycleLength,
      'period_length': periodLength,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
    }, onConflict: 'user_id,period_start');
  }

  // ── Women's Health — Symptoms ──────────────────────────────────────────────

  static Future<Map<String, dynamic>?> getSymptomsForDate(
      String userId, DateTime date) async {
    return client
        .from('user_symptoms')
        .select()
        .eq('user_id', userId)
        .eq('logged_date', _dateStr(date))
        .maybeSingle();
  }

  static Future<void> upsertSymptoms({
    required String userId,
    required DateTime date,
    String? mood,
    int? energy,
    bool cramps = false,
    bool headache = false,
    bool bloating = false,
    String? notes,
  }) async {
    await client.from('user_symptoms').upsert({
      'user_id': userId,
      'logged_date': _dateStr(date),
      'mood': mood,
      'energy': energy,
      'cramps': cramps,
      'headache': headache,
      'bloating': bloating,
      'notes': notes,
    }, onConflict: 'user_id,logged_date');
  }
}
