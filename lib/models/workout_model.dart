import 'package:flutter/material.dart';

enum WorkoutMetric { heartRate, steps, distance, calories }

enum WorkoutCategory {
  running,
  cycling,
  swimming,
  outdoorSports,
  gymFitness,
  yoga,
  dance,
  combatSports,
  ballSports,
  waterSports,
  winterSports,
  leisureRecreation,
}

extension WorkoutCategoryX on WorkoutCategory {
  String get label => switch (this) {
        WorkoutCategory.running => 'Running',
        WorkoutCategory.cycling => 'Cycling',
        WorkoutCategory.swimming => 'Swimming',
        WorkoutCategory.outdoorSports => 'Outdoor Sports',
        WorkoutCategory.gymFitness => 'Gym & Fitness',
        WorkoutCategory.yoga => 'Yoga',
        WorkoutCategory.dance => 'Dance',
        WorkoutCategory.combatSports => 'Combat Sports',
        WorkoutCategory.ballSports => 'Ball Sports',
        WorkoutCategory.waterSports => 'Water Sports',
        WorkoutCategory.winterSports => 'Winter Sports',
        WorkoutCategory.leisureRecreation => 'Leisure & Recreation',
      };

  IconData get icon => switch (this) {
        WorkoutCategory.running => Icons.directions_run_rounded,
        WorkoutCategory.cycling => Icons.directions_bike_rounded,
        WorkoutCategory.swimming => Icons.pool_rounded,
        WorkoutCategory.outdoorSports => Icons.terrain_rounded,
        WorkoutCategory.gymFitness => Icons.fitness_center_rounded,
        WorkoutCategory.yoga => Icons.self_improvement_rounded,
        WorkoutCategory.dance => Icons.music_note_rounded,
        WorkoutCategory.combatSports => Icons.sports_mma_rounded,
        WorkoutCategory.ballSports => Icons.sports_basketball_rounded,
        WorkoutCategory.waterSports => Icons.surfing_rounded,
        WorkoutCategory.winterSports => Icons.ac_unit_rounded,
        WorkoutCategory.leisureRecreation => Icons.sports_esports_rounded,
      };

  Set<WorkoutMetric> get metrics => switch (this) {
        WorkoutCategory.running => const {
            WorkoutMetric.heartRate,
            WorkoutMetric.steps,
            WorkoutMetric.distance,
            WorkoutMetric.calories,
          },
        WorkoutCategory.cycling => const {
            WorkoutMetric.heartRate,
            WorkoutMetric.distance,
            WorkoutMetric.calories,
          },
        WorkoutCategory.swimming => const {
            WorkoutMetric.heartRate,
            WorkoutMetric.calories,
          },
        WorkoutCategory.outdoorSports => const {
            WorkoutMetric.heartRate,
            WorkoutMetric.distance,
            WorkoutMetric.calories,
          },
        WorkoutCategory.gymFitness => const {
            WorkoutMetric.heartRate,
            WorkoutMetric.calories,
          },
        WorkoutCategory.yoga => const {
            WorkoutMetric.heartRate,
            WorkoutMetric.calories,
          },
        WorkoutCategory.dance => const {
            WorkoutMetric.heartRate,
            WorkoutMetric.calories,
            WorkoutMetric.steps,
          },
        WorkoutCategory.combatSports => const {
            WorkoutMetric.heartRate,
            WorkoutMetric.calories,
          },
        WorkoutCategory.ballSports => const {
            WorkoutMetric.heartRate,
            WorkoutMetric.calories,
          },
        WorkoutCategory.waterSports => const {
            WorkoutMetric.heartRate,
            WorkoutMetric.calories,
          },
        WorkoutCategory.winterSports => const {
            WorkoutMetric.heartRate,
            WorkoutMetric.calories,
            WorkoutMetric.distance,
          },
        WorkoutCategory.leisureRecreation => const {
            WorkoutMetric.heartRate,
            WorkoutMetric.calories,
          },
      };

  List<String> get sports => switch (this) {
        WorkoutCategory.running => const [
            'GPS Running',
            'Running',
            'Indoor Running',
            'Treadmill',
            'Indoor Walking',
            'Trail Running',
            'Race Walking',
            'Playground Running',
            'Walking',
            'GPS Walking',
            'Marathon',
          ],
        WorkoutCategory.cycling => const [
            'GPS Cycling',
            'Cycling',
            'Indoor Cycling',
            'Mountain Biking',
            'BMX',
            'Spinning Bike',
            'Hand Bike',
          ],
        WorkoutCategory.swimming => const [
            'Swimming',
            'Pool Swimming',
            'Outdoor Swimming',
            'Fin Swimming',
            'Synchronized Swimming',
          ],
        WorkoutCategory.outdoorSports => const [
            'Outdoor Hiking',
            'Orienteering',
            'Fishing',
            'Hunting',
            'Skateboarding',
            'Parkour',
            'ATV',
            'Motocross',
            'Racing',
            'Obstacle Course',
            'Rock Climbing',
            'Climbing',
            'Kayaking',
          ],
        WorkoutCategory.gymFitness => const [
            'Exercise',
            'Strength Training',
            'Core Training',
            'Cross Training',
            'Indoor Fitness',
            'Fitness',
            'Free Training',
            'Flexibility Training',
            'Stretching',
            'Pilates',
            'Gymnastics',
            'Group Gymnastics',
            'Mixed Aerobics',
            'Aerobics',
            'Balance Training',
            'Step Training',
            'Stepper',
            'Stair Climber',
            'GAP Training',
            'Kickboxing',
            'Battle Rope',
            'Horizontal Bar',
            'Parallel Bars',
            'Elliptical Machine',
            'Rowing Machine',
            'Rope Skipping',
            'Swing',
            'Walking Machine',
          ],
        WorkoutCategory.yoga => const [
            'Yoga',
            'Anusara Yoga',
            'Yin Yoga',
          ],
        WorkoutCategory.dance => const [
            'Dance',
            'Square Dance',
            'Ballroom Dancing',
            'Belly Dance',
            'Ballet',
            'Street Dance',
            'Zumba',
            'Latin Dance',
            'Jazz Dance',
            'Hip-Hop Dance',
            'Pole Dance',
            'Break Dance',
            'Folk Dance',
            'Music Dance',
            'Modern Dance',
            'Disco',
            'Tap Dance',
            'Other Dance',
          ],
        WorkoutCategory.combatSports => const [
            'Boxing',
            'Wrestling',
            'Martial Arts',
            'Tai Chi',
            'Muay Thai',
            'Judo',
            'Taekwondo',
            'Karate',
            'Free Sparring',
            'Swordsmanship',
            'Jiu-Jitsu',
            'Fencing',
            'Kendo',
          ],
        WorkoutCategory.ballSports => const [
            'Badminton',
            'Table Tennis',
            'Tennis',
            'Golf',
            'Basketball',
            'Football',
            'Volleyball',
            'Beach Soccer',
            'Beach Volleyball',
            'Baseball',
            'Softball',
            'Rugby',
            'Hockey',
            'Squash',
            'Gateball',
            'Cricket',
            'Handball',
            'Bowling',
            'Polo',
            'Racquetball',
            'Billiards',
            'Sepak Takraw',
            'Dodgeball',
            'Water Polo',
            'Ice Hockey',
            'Shuttlecock',
            'Indoor Football',
            'Sandbag Ball',
            'Bocce',
            'Jai Alai',
            'Floorball',
            'Australian Rules Football',
            'Pickleball',
          ],
        WorkoutCategory.waterSports => const [
            'Outdoor Rowing',
            'Sailing',
            'Dragon Boat',
            'Surfing',
            'Kite Surfing',
            'Paddling',
            'Paddleboard Surfing',
            'Indoor Surfing',
            'Rafting',
            'Snorkeling',
          ],
        WorkoutCategory.winterSports => const [
            'Skiing',
            'Snowboarding',
            'Alpine Skiing',
            'Cross-Country Skiing',
            'Ski Orienteering',
            'Biathlon',
            'Outdoor Skating',
            'Indoor Skating',
            'Curling',
            'Bobsleigh',
            'Sledding',
            'Snowmobile',
            'Snowshoe Hiking',
          ],
        WorkoutCategory.leisureRecreation => const [
            'Hula Hoop',
            'Frisbee',
            'Darts',
            'Kite Flying',
            'Tug of War',
            'Esports',
            'Shuffleboard',
            'Table Football',
            'Somatosensory Games',
            'Bungee Jumping',
            'Skydiving',
          ],
      };
}

/// Resolves a stored string (sport name, category name, or enum name) back
/// to a WorkoutCategory. Used when reading history from Supabase.
WorkoutCategory? workoutCategoryFromString(String value) {
  final lower = value.toLowerCase();
  for (final cat in WorkoutCategory.values) {
    if (cat.name == value || cat.label.toLowerCase() == lower) return cat;
  }
  for (final cat in WorkoutCategory.values) {
    if (cat.sports.any((s) => s.toLowerCase() == lower)) return cat;
  }
  return null;
}

class WorkoutSession {
  final String id;
  final WorkoutCategory category;
  final String sport;
  final DateTime startTime;
  final DateTime endTime;
  final int durationSeconds;
  final int steps;
  final int calories;
  final double distanceM;
  final int avgHr;

  const WorkoutSession({
    required this.id,
    required this.category,
    required this.sport,
    required this.startTime,
    required this.endTime,
    required this.durationSeconds,
    required this.steps,
    required this.calories,
    required this.distanceM,
    required this.avgHr,
  });
}
