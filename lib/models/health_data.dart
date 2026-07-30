class HrSummary {
  final DateTime date;
  final int avg;
  final int min;
  final int max;
  final int sampleCount;

  const HrSummary({
    required this.date,
    required this.avg,
    required this.min,
    required this.max,
    required this.sampleCount,
  });

  factory HrSummary.fromMap(Map<String, dynamic> m, {DateTime? date}) {
    final d = date ??
        DateTime.tryParse(m['date'] as String? ?? '') ?? DateTime.now();
    return HrSummary(
      date: d,
      avg: (m['avg_hr'] as num? ?? 0).toInt(),
      min: (m['min_hr'] as num? ?? 0).toInt(),
      max: (m['max_hr'] as num? ?? 0).toInt(),
      sampleCount: (m['sample_count'] as num? ?? 0).toInt(),
    );
  }

  Map<String, dynamic> toMap(String userId) => {
        'user_id': userId,
        'date': _dateStr(date),
        'avg_hr': avg,
        'min_hr': min,
        'max_hr': max,
        'sample_count': sampleCount,
        'synced_at': DateTime.now().toUtc().toIso8601String(),
      };

  static String _dateStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

class Spo2Summary {
  final DateTime date;
  final int avg;
  final int min;
  final int max;
  final int sampleCount;

  const Spo2Summary({
    required this.date,
    required this.avg,
    required this.min,
    required this.max,
    required this.sampleCount,
  });

  factory Spo2Summary.fromMap(Map<String, dynamic> m, {DateTime? date}) {
    final d = date ??
        DateTime.tryParse(m['date'] as String? ?? '') ?? DateTime.now();
    return Spo2Summary(
      date: d,
      avg: (m['avg_spo2'] as num? ?? 0).toInt(),
      min: (m['min_spo2'] as num? ?? 0).toInt(),
      max: (m['max_spo2'] as num? ?? 0).toInt(),
      sampleCount: (m['sample_count'] as num? ?? 0).toInt(),
    );
  }

  Map<String, dynamic> toMap(String userId) => {
        'user_id': userId,
        'date': _dateStr(date),
        'avg_spo2': avg,
        'min_spo2': min,
        'max_spo2': max,
        'sample_count': sampleCount,
        'synced_at': DateTime.now().toUtc().toIso8601String(),
      };

  static String _dateStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

class StepsSummary {
  final DateTime date;
  final int steps;
  final int calories;
  final double distanceM;

  const StepsSummary({
    required this.date,
    required this.steps,
    required this.calories,
    required this.distanceM,
  });

  factory StepsSummary.fromMap(Map<String, dynamic> m, {DateTime? date}) {
    final d = date ??
        DateTime.tryParse(m['date'] as String? ?? '') ?? DateTime.now();
    return StepsSummary(
      date: d,
      steps: (m['steps'] as num? ?? 0).toInt(),
      calories: (m['calories'] as num? ?? 0).toInt(),
      distanceM: (m['distance_m'] as num? ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toMap(String userId) => {
        'user_id': userId,
        'date': _dateStr(date),
        'steps': steps,
        'calories': calories,
        'distance_m': distanceM,
        'synced_at': DateTime.now().toUtc().toIso8601String(),
      };

  static String _dateStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

class BpReading {
  final int systolic;
  final int diastolic;
  final DateTime measuredAt;
  final String source;

  const BpReading({
    required this.systolic,
    required this.diastolic,
    required this.measuredAt,
    this.source = 'manual',
  });

  factory BpReading.fromMap(Map<String, dynamic> m) => BpReading(
        systolic: (m['systolic'] as num? ?? 0).toInt(),
        diastolic: (m['diastolic'] as num? ?? 0).toInt(),
        measuredAt: DateTime.tryParse(m['measured_at'] as String? ?? '') ??
            DateTime.now(),
        source: m['source'] as String? ?? 'manual',
      );

  Map<String, dynamic> toMap(String userId) => {
        'user_id': userId,
        'systolic': systolic,
        'diastolic': diastolic,
        'measured_at': measuredAt.toUtc().toIso8601String(),
        'source': source,
      };
}

class StressReading {
  final int value;
  final String label;
  final DateTime measuredAt;
  final String source;

  const StressReading({
    required this.value,
    required this.label,
    required this.measuredAt,
    this.source = 'manual',
  });

  factory StressReading.fromMap(Map<String, dynamic> m) {
    final v = (m['stress_value'] as num? ?? 0).toInt();
    return StressReading(
      value: v,
      label: m['label'] as String? ?? _labelFor(v),
      measuredAt:
          DateTime.tryParse(m['measured_at'] as String? ?? '') ?? DateTime.now(),
      source: m['source'] as String? ?? 'manual',
    );
  }

  static String _labelFor(int v) {
    if (v < 40) return 'Relaxed';
    if (v < 60) return 'Normal';
    if (v < 80) return 'Elevated';
    return 'High';
  }

  Map<String, dynamic> toMap(String userId) => {
        'user_id': userId,
        'stress_value': value,
        'label': label,
        'measured_at': measuredAt.toUtc().toIso8601String(),
        'source': source,
      };
}

class HrvSummary {
  final DateTime date;
  final int avg;
  final int min;
  final int max;
  final int sampleCount;

  const HrvSummary({
    required this.date,
    required this.avg,
    required this.min,
    required this.max,
    required this.sampleCount,
  });

  factory HrvSummary.fromMap(Map<String, dynamic> m, {DateTime? date}) {
    final d = date ??
        DateTime.tryParse(m['date'] as String? ?? '') ?? DateTime.now();
    return HrvSummary(
      date: d,
      avg: (m['avg_hrv'] as num? ?? 0).toInt(),
      min: (m['min_hrv'] as num? ?? 0).toInt(),
      max: (m['max_hrv'] as num? ?? 0).toInt(),
      sampleCount: (m['sample_count'] as num? ?? 0).toInt(),
    );
  }

  Map<String, dynamic> toMap(String userId) => {
        'user_id': userId,
        'date': _dateStr(date),
        'avg_hrv': avg,
        'min_hrv': min,
        'max_hrv': max,
        'sample_count': sampleCount,
        'synced_at': DateTime.now().toUtc().toIso8601String(),
      };

  static String _dateStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

class TempReading {
  final double valueC;
  final DateTime measuredAt;
  final String source;

  const TempReading({
    required this.valueC,
    required this.measuredAt,
    this.source = 'auto',
  });

  factory TempReading.fromMap(Map<String, dynamic> m) => TempReading(
        valueC: (m['value_c'] as num? ?? 0).toDouble(),
        measuredAt:
            DateTime.tryParse(m['measured_at'] as String? ?? '') ?? DateTime.now(),
        source: m['source'] as String? ?? 'auto',
      );

  Map<String, dynamic> toMap(String userId) => {
        'user_id': userId,
        'measured_at': measuredAt.toUtc().toIso8601String(),
        'value_c': valueC,
        'source': source,
      };
}

class SleepSummary {
  final DateTime date;
  final int totalDuration;
  final int deepDuration;
  final int lightDuration;
  final int remDuration;
  final int awakeDuration;
  final int sleepScore;
  final int sleepTime;
  final int wakeTime;

  const SleepSummary({
    required this.date,
    required this.totalDuration,
    required this.deepDuration,
    required this.lightDuration,
    required this.remDuration,
    required this.awakeDuration,
    required this.sleepScore,
    this.sleepTime = 0,
    this.wakeTime = 0,
  });

  factory SleepSummary.fromMap(Map<String, dynamic> m, {DateTime? date}) {
    final d = date ??
        DateTime.tryParse(m['date'] as String? ?? '') ?? DateTime.now();
    return SleepSummary(
      date: d,
      totalDuration: (m['total_duration'] as num? ?? 0).toInt(),
      deepDuration: (m['deep_duration'] as num? ?? 0).toInt(),
      lightDuration: (m['light_duration'] as num? ?? 0).toInt(),
      remDuration: (m['rem_duration'] as num? ?? 0).toInt(),
      awakeDuration: (m['awake_duration'] as num? ?? 0).toInt(),
      sleepScore: (m['sleep_score'] as num? ?? 0).toInt(),
      sleepTime: (m['sleep_time'] as num? ?? 0).toInt(),
      wakeTime: (m['wake_time'] as num? ?? 0).toInt(),
    );
  }

  Map<String, dynamic> toMap(String userId) => {
        'user_id': userId,
        'date': _dateStr(date),
        'total_duration': totalDuration,
        'deep_duration': deepDuration,
        'light_duration': lightDuration,
        'rem_duration': remDuration,
        'awake_duration': awakeDuration,
        'sleep_score': sleepScore,
        'sleep_time': sleepTime,
        'wake_time': wakeTime,
        'synced_at': DateTime.now().toUtc().toIso8601String(),
      };

  static String _dateStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

class WorkoutRecord {
  final String? id;
  final String type;
  final DateTime startedAt;
  final DateTime endedAt;
  final int durationS;
  final int steps;
  final int calories;
  final double distanceM;
  final int avgHr;
  final int avgSpo2;
  final int avgBpSbp;
  final int avgBpDbp;

  const WorkoutRecord({
    this.id,
    required this.type,
    required this.startedAt,
    required this.endedAt,
    required this.durationS,
    required this.steps,
    required this.calories,
    required this.distanceM,
    required this.avgHr,
    required this.avgSpo2,
    required this.avgBpSbp,
    required this.avgBpDbp,
  });

  factory WorkoutRecord.fromMap(Map<String, dynamic> m) => WorkoutRecord(
        id: m['id'] as String?,
        type: m['workout_type'] as String? ?? '',
        startedAt:
            DateTime.tryParse(m['started_at'] as String? ?? '') ?? DateTime.now(),
        endedAt:
            DateTime.tryParse(m['ended_at'] as String? ?? '') ?? DateTime.now(),
        durationS: (m['duration_s'] as num? ?? 0).toInt(),
        steps: (m['steps'] as num? ?? 0).toInt(),
        calories: (m['calories'] as num? ?? 0).toInt(),
        distanceM: (m['distance_m'] as num? ?? 0).toDouble(),
        avgHr: (m['avg_hr'] as num? ?? 0).toInt(),
        avgSpo2: (m['avg_spo2'] as num? ?? 0).toInt(),
        avgBpSbp: (m['avg_bp_sbp'] as num? ?? 0).toInt(),
        avgBpDbp: (m['avg_bp_dbp'] as num? ?? 0).toInt(),
      );

  Map<String, dynamic> toMap(String userId) => {
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
      };
}

class UserProfile {
  final String id;
  final String fullName;
  final int age;
  final String gender;
  final int heightCm;
  final double weightKg;
  final String? address;
  final String? additionalInstructions;

  const UserProfile({
    required this.id,
    required this.fullName,
    required this.age,
    required this.gender,
    required this.heightCm,
    required this.weightKg,
    this.address,
    this.additionalInstructions,
  });

  factory UserProfile.fromMap(Map<String, dynamic> m) => UserProfile(
        id: m['id'] as String? ?? '',
        fullName: m['full_name'] as String? ?? '',
        age: (m['age'] as num? ?? 0).toInt(),
        gender: m['gender'] as String? ?? '',
        heightCm: (m['height_cm'] as num? ?? 0).toInt(),
        weightKg: (m['weight_kg'] as num? ?? 0).toDouble(),
        address: m['address'] as String?,
        additionalInstructions: m['additional_instructions'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'full_name': fullName,
        'age': age,
        'gender': gender,
        'height_cm': heightCm,
        'weight_kg': weightKg,
        if (address != null) 'address': address,
        if (additionalInstructions != null)
          'additional_instructions': additionalInstructions,
      };
}

class EmergencyContact {
  final int localId;
  final String name;
  final String phone;

  const EmergencyContact({
    required this.localId,
    required this.name,
    required this.phone,
  });

  factory EmergencyContact.fromMap(Map<String, dynamic> m) => EmergencyContact(
        localId: (m['local_id'] as num? ?? 0).toInt(),
        name: m['name'] as String? ?? '',
        phone: m['phone'] as String? ?? '',
      );

  Map<String, dynamic> toMap(String userId) => {
        'user_id': userId,
        'local_id': localId,
        'name': name,
        'phone': phone,
      };
}

class CycleRecord {
  final DateTime periodStart;
  final int cycleLength;
  final int periodLength;
  final String? notes;

  const CycleRecord({
    required this.periodStart,
    required this.cycleLength,
    required this.periodLength,
    this.notes,
  });

  factory CycleRecord.fromMap(Map<String, dynamic> m) => CycleRecord(
        periodStart:
            DateTime.tryParse(m['period_start'] as String? ?? '') ?? DateTime.now(),
        cycleLength: (m['cycle_length'] as num? ?? 28).toInt(),
        periodLength: (m['period_length'] as num? ?? 5).toInt(),
        notes: m['notes'] as String?,
      );

  Map<String, dynamic> toMap(String userId) => {
        'user_id': userId,
        'period_start': _dateStr(periodStart),
        'cycle_length': cycleLength,
        'period_length': periodLength,
        if (notes != null && notes!.isNotEmpty) 'notes': notes,
      };

  static String _dateStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

class SymptomRecord {
  final DateTime date;
  final String? mood;
  final int? energy;
  final bool cramps;
  final bool headache;
  final bool bloating;
  final String? notes;

  const SymptomRecord({
    required this.date,
    this.mood,
    this.energy,
    this.cramps = false,
    this.headache = false,
    this.bloating = false,
    this.notes,
  });

  factory SymptomRecord.fromMap(Map<String, dynamic> m) => SymptomRecord(
        date: DateTime.tryParse(m['logged_date'] as String? ?? '') ??
            DateTime.now(),
        mood: m['mood'] as String?,
        energy: m['energy'] as int?,
        cramps: m['cramps'] as bool? ?? false,
        headache: m['headache'] as bool? ?? false,
        bloating: m['bloating'] as bool? ?? false,
        notes: m['notes'] as String?,
      );

  Map<String, dynamic> toMap(String userId) => {
        'user_id': userId,
        'logged_date': _dateStr(date),
        'mood': mood,
        'energy': energy,
        'cramps': cramps,
        'headache': headache,
        'bloating': bloating,
        'notes': notes,
      };

  static String _dateStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
