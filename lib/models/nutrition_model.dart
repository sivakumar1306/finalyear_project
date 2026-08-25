class NutritionLog {
  final DateTime date;
  final int calories;
  final int carbs;
  final int protein;
  final int fat;

  const NutritionLog({
    required this.date,
    required this.calories,
    this.carbs = 0,
    this.protein = 0,
    this.fat = 0,
  });

  factory NutritionLog.fromMap(Map<String, dynamic> m) => NutritionLog(
        date: DateTime.tryParse(m['date'] as String? ?? '') ?? DateTime.now(),
        calories: (m['calories'] as num? ?? 0).toInt(),
        carbs: (m['carbs'] as num? ?? 0).toInt(),
        protein: (m['protein'] as num? ?? 0).toInt(),
        fat: (m['fat'] as num? ?? 0).toInt(),
      );

  Map<String, dynamic> toMap(String userId) => {
        'user_id': userId,
        'date': _dateStr(date),
        'calories': calories,
        'carbs': carbs,
        'protein': protein,
        'fat': fat,
      };

  static String _dateStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
