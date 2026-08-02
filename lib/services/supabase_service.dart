import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config.dart';
import '../models/health_data.dart';

class SupabaseService {
  static const _url = AppConfig.supabaseUrl;
  static const _publishableKey = AppConfig.supabaseAnonKey;

  static Future<void> initialize() async {
    await Supabase.initialize(url: _url, publishableKey: _publishableKey);
  }

  static SupabaseClient get client => Supabase.instance.client;

  static User? get currentUser => client.auth.currentUser;

  // Exposed so the native side (BleConnectionService's SupabaseSyncManager) can be
  // configured to push local Room data directly, independent of the Dart engine.
  static String get url => _url;
  static String get anonKey => _publishableKey;
  static String? get accessToken => client.auth.currentSession?.accessToken;

  static Future<AuthResponse> signUp(String email, String password) {
    return client.auth.signUp(email: email, password: password);
  }

  static Future<AuthResponse> signIn(String email, String password) {
    return client.auth.signInWithPassword(email: email, password: password);
  }

  static Future<void> signOut() => client.auth.signOut();

  /// Sends a password-recovery email for [email] (the recovery code that
  /// appears in the email must be submitted via [verifyRecoveryCode]).
  static Future<void> resetPassword(String email) {
    return client.auth.resetPasswordForEmail(email);
  }

  /// Verifies the 6-digit recovery code from the recovery email. On success
  /// a session is established, so [updatePassword] can be called next.
  static Future<void> verifyRecoveryCode(String email, String code) async {
    await client.auth.verifyOTP(
      email: email,
      token: code,
      type: OtpType.recovery,
    );
  }

  static Future<void> updatePassword(String newPassword) {
    return client.auth.updateUser(
      UserAttributes(password: newPassword),
    );
  }

  static const _bleChannel = MethodChannel('com.medxai.qring/ble');

  /// Signs out and wipes every piece of locally stored personal data:
  ///
  /// * the Supabase session (removed by [client.auth.signOut] itself),
  /// * the native Room database `qring_local.db` — vitals history, fall events,
  ///   emergency contacts, phone-mode sessions — plus the native SharedPreferences
  ///   that mirror the session JWT and measurement/emergency state,
  /// * every Dart-side SharedPreferences key (ring pairing, chat conversation ids,
  ///   fall emergency info, goals, card layout, alert toggles, workouts, units, …),
  /// * all outstanding notifications (fall alerts, anomaly alerts, live updates).
  ///
  /// Runs each step defensively so a failure in one can't prevent the others.
  static Future<void> logoutAndClearLocalData() async {
    try {
      await client.auth.signOut();
    } catch (e) {
      debugPrint('logoutAndClearLocalData: signOut failed: $e');
    }
    try {
      await _bleChannel.invokeMethod('clearPersonalData');
    } catch (e) {
      debugPrint('logoutAndClearLocalData: clearPersonalData failed: $e');
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    } catch (e) {
      debugPrint('logoutAndClearLocalData: prefs.clear failed: $e');
    }
  }

  static Future<void> deleteAccount(String password) async {
    final user = currentUser;
    if (user == null || user.email == null) {
      throw Exception('Not authenticated');
    }
    
    // Verify password by attempting to sign in
    await signIn(user.email!, password);
    
    // Call the RPC to delete the account and all associated data
    await client.rpc('delete_user_account');
    
    // Clear local state
    await logoutAndClearLocalData();
  }

  static Future<Map<String, dynamic>?> getProfile(String userId) async {
    return client.from('user_profiles').select().eq('id', userId).maybeSingle();
  }

  static Future<void> upsertProfile({
    required String userId,
    required String fullName,
    required int age,
    required String gender,
    required int heightCm,
    required double weightKg,
    String? address,
    String? additionalInstructions,
  }) async {
    await client.from('user_profiles').upsert({
      'id': userId,
      'full_name': fullName,
      'age': age,
      'gender': gender,
      'height_cm': heightCm,
      'weight_kg': weightKg,
      'address': ?address,
      'additional_instructions': ?additionalInstructions,
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
    String userId,
    DateTime date,
  ) async {
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
    String userId,
    DateTime date,
  ) async {
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
    String userId,
    DateTime date,
  ) async {
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
    required List<({DateTime measuredAt, double valueC, String source})>
    readings,
  }) async {
    if (readings.isEmpty) return;
    // Upsert (not insert) — the ring re-sends its whole temperature series on
    // every _syncAuto() call, so a plain insert would duplicate rows for
    // timestamps we already have. user_id+measured_at already has a unique
    // constraint (see SupabaseSyncManager.kt's native upsert to this same
    // table), so this just needs to use it too.
    await client
        .from('user_temp')
        .upsert(
          readings
              .map(
                (r) => {
                  'user_id': userId,
                  'measured_at': r.measuredAt.toUtc().toIso8601String(),
                  'value_c': r.valueC,
                  'source': r.source,
                },
              )
              .toList(),
          onConflict: 'user_id,measured_at',
        );
  }

  static Future<void> insertTemp({
    required String userId,
    required DateTime measuredAt,
    required double valueC,
    String source = 'auto',
  }) async {
    await client.from('user_temp').upsert({
      'user_id': userId,
      'measured_at': measuredAt.toUtc().toIso8601String(),
      'value_c': valueC,
      'source': source,
    }, onConflict: 'user_id,measured_at');
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
    final data = await client
        .from('user_workouts')
        .insert({
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
        })
        .select('id')
        .single();
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

  // ── Sleep ─────────────────────────────────────────────────────────────────

  static Future<void> upsertSleep({
    required String userId,
    required DateTime date,
    required int totalDuration,
    required int deepDuration,
    required int lightDuration,
    required int remDuration,
    required int awakeDuration,
    required int sleepScore,
    int sleepTime = 0,
    int wakeTime = 0,
  }) async {
    final dateStr =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    await client.from('user_sleep').upsert({
      'user_id': userId,
      'date': dateStr,
      'total_duration': totalDuration,
      'deep_duration': deepDuration,
      'light_duration': lightDuration,
      'rem_duration': remDuration,
      'awake_duration': awakeDuration,
      'sleep_score': sleepScore,
      'sleep_time': sleepTime,
      'wake_time': wakeTime,
      'synced_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'user_id,date');
  }

  static Future<Map<String, dynamic>?> getSleepForDate(
    String userId,
    DateTime date,
  ) async {
    final dateStr =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return client
        .from('user_sleep')
        .select()
        .eq('user_id', userId)
        .eq('date', dateStr)
        .maybeSingle();
  }

  static Future<List<Map<String, dynamic>>> getSleepHistory({
    required String userId,
    required DateTime from,
    required DateTime to,
  }) async {
    String fmt(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final data = await client
        .from('user_sleep')
        .select()
        .eq('user_id', userId)
        .gte('date', fmt(from))
        .lte('date', fmt(to))
        .order('date', ascending: true);
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
    String userId,
    DateTime date,
  ) async {
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

  // ── Emergency Contacts (cloud sync — mirrors the local Room table owned by
  // BleProvider/BlePlugin) ────────────────────────────────────────────────────
  //
  // local_id ties each cloud row back to its Room `id` (autogenerated on-device),
  // so a contact edited/deleted locally can be found and updated/removed here
  // too, rather than accumulating duplicates.

  static Future<void> upsertEmergencyContact({
    required String userId,
    required int localId,
    required String name,
    required String phone,
  }) async {
    await client.from('user_emergency_contacts').upsert({
      'user_id': userId,
      'local_id': localId,
      'name': name,
      'phone': phone,
    }, onConflict: 'user_id,local_id');
  }

  static Future<void> deleteEmergencyContactByLocalId({
    required String userId,
    required int localId,
  }) async {
    await client
        .from('user_emergency_contacts')
        .delete()
        .eq('user_id', userId)
        .eq('local_id', localId);
  }

  static Future<List<Map<String, dynamic>>> getEmergencyContactsCloud(
    String userId,
  ) async {
    final data = await client
        .from('user_emergency_contacts')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: true);
    return List<Map<String, dynamic>>.from(data);
  }

  // ── Typed convenience wrappers ──────────────────────────────────────────────

  static Future<UserProfile?> getProfileTyped(String userId) async {
    final m = await getProfile(userId);
    return m != null ? UserProfile.fromMap(m) : null;
  }

  static Future<HrSummary?> getHrForDateTyped(String userId, DateTime date) async {
    final m = await getHrForDate(userId, date);
    return m != null ? HrSummary.fromMap(m, date: date) : null;
  }

  static Future<List<HrSummary>> getHrHistoryTyped({
    required String userId,
    required DateTime from,
    required DateTime to,
  }) async {
    final rows = await getHrHistory(userId: userId, from: from, to: to);
    return rows.map((m) => HrSummary.fromMap(m)).toList();
  }

  static Future<Spo2Summary?> getSpo2ForDateTyped(String userId, DateTime date) async {
    final m = await getSpo2ForDate(userId, date);
    return m != null ? Spo2Summary.fromMap(m, date: date) : null;
  }

  static Future<List<Spo2Summary>> getSpo2HistoryTyped({
    required String userId,
    required DateTime from,
    required DateTime to,
  }) async {
    final rows = await getSpo2History(userId: userId, from: from, to: to);
    return rows.map((m) => Spo2Summary.fromMap(m)).toList();
  }

  static Future<HrvSummary?> getHrvForDateTyped(String userId, DateTime date) async {
    final m = await getHrvForDate(userId, date);
    return m != null ? HrvSummary.fromMap(m, date: date) : null;
  }

  static Future<List<HrvSummary>> getHrvHistoryTyped({
    required String userId,
    required DateTime from,
    required DateTime to,
  }) async {
    final rows = await getHrvHistory(userId: userId, from: from, to: to);
    return rows.map((m) => HrvSummary.fromMap(m)).toList();
  }

  static Future<SleepSummary?> getSleepForDateTyped(String userId, DateTime date) async {
    final m = await getSleepForDate(userId, date);
    return m != null ? SleepSummary.fromMap(m, date: date) : null;
  }

  static Future<List<SleepSummary>> getSleepHistoryTyped({
    required String userId,
    required DateTime from,
    required DateTime to,
  }) async {
    final rows = await getSleepHistory(userId: userId, from: from, to: to);
    return rows.map((m) => SleepSummary.fromMap(m)).toList();
  }

  static Future<List<BpReading>> getBpReadingsTyped({
    required String userId,
    required DateTime from,
    required DateTime to,
  }) async {
    final rows = await getBpReadings(userId: userId, from: from, to: to);
    return rows.map((m) => BpReading.fromMap(m)).toList();
  }

  static Future<List<StressReading>> getStressReadingsTyped({
    required String userId,
    required DateTime from,
    required DateTime to,
  }) async {
    final rows = await getStressReadings(userId: userId, from: from, to: to);
    return rows.map((m) => StressReading.fromMap(m)).toList();
  }

  static Future<List<TempReading>> getTempReadingsTyped({
    required String userId,
    required DateTime from,
    required DateTime to,
  }) async {
    final rows = await getTempReadings(userId: userId, from: from, to: to);
    return rows.map((m) => TempReading.fromMap(m)).toList();
  }

  static Future<List<WorkoutRecord>> getWorkoutHistoryTyped({
    required String userId,
    required DateTime from,
    required DateTime to,
  }) async {
    final rows = await getWorkoutHistory(userId: userId, from: from, to: to);
    return rows.map((m) => WorkoutRecord.fromMap(m)).toList();
  }

  static Future<List<CycleRecord>> getCyclesTyped(String userId) async {
    final rows = await getCycles(userId);
    return rows.map((m) => CycleRecord.fromMap(m)).toList();
  }

  static Future<SymptomRecord?> getSymptomsForDateTyped(String userId, DateTime date) async {
    final m = await getSymptomsForDate(userId, date);
    return m != null ? SymptomRecord.fromMap(m) : null;
  }
}
