# ── R8 full-mode optimization flags ──────────────────────────────────────────
-allowaccessmodification
-repackageclasses ''
-optimizations !code/simplification/variable,!code/simplification/arithmetic,!field/*,!class/merging/*
-optimizationpasses 5

# ── Room ──────────────────────────────────────────────────────────────────────
# Room uses reflection to instantiate DAOs and the Database class.
# Entities are accessed via Room's generated code but also serialized via
# Gson with @SerializedName — keep entity field names for both paths.
-keep class * extends androidx.room.RoomDatabase { *; }
-keep class * extends androidx.room.dao.Dao { *; }
-keep class com.sundr.myapp.data.QRingDatabase { *; }
-keep class com.sundr.myapp.data.MeasurementCycleEntity { *; }
-keep class com.sundr.myapp.data.MeasurementAttemptEntity { *; }
-keep class com.sundr.myapp.data.HeartRateReadingEntity { *; }
-keep class com.sundr.myapp.data.Spo2ReadingEntity { *; }
-keep class com.sundr.myapp.data.StressReadingEntity { *; }
-keep class com.sundr.myapp.data.BloodPressureReadingEntity { *; }
-keep class com.sundr.myapp.data.HrvReadingEntity { *; }
-keep class com.sundr.myapp.data.TemperatureReadingEntity { *; }
-keep class com.sundr.myapp.data.StepsSnapshotEntity { *; }
-keep class com.sundr.myapp.data.FallRiskLogEntity { *; }
-keep class com.sundr.myapp.data.FallEventEntity { *; }
-keep class com.sundr.myapp.data.EmergencyContactEntity { *; }
-keep class com.sundr.myapp.data.PhoneModeSessionEntity { *; }
-keep class com.sundr.myapp.data.DailyVitalSummaryEntity { *; }

# ── Gson ──────────────────────────────────────────────────────────────────────
# Attributes required by Gson reflection (runtime annotations like @SerializedName,
# generic signatures for TypeToken subclasses, anonymous/local class info).
-keepattributes Signature,EnclosingMethod,InnerClasses
-keepattributes AnnotationDefault
-keepattributes RuntimeVisibleAnnotations,RuntimeVisibleParameterAnnotations,RuntimeVisibleTypeAnnotations

# Gson 2.10.x ships its own consumer R8 rules, so no blanket -keep on gson.**
# Only TypeToken subclasses created reflectively need explicit keeping here.
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-dontwarn sun.misc.**

# ── Vendor QRing / Oudmon BLE SDK (AAR) ──────────────────────────────────────
# R8 must not strip reflection/JNI entry points.
-keep class com.oudmon.** { *; }
-keep class com.realsil.** { *; }
-keep class com.jieli.** { *; }
-keepclassmembers class * {
    native <methods>;
}
-dontwarn com.oudmon.**
-dontwarn com.realsil.**
-dontwarn com.jieli.**

# ── EventBus ──────────────────────────────────────────────────────────────────
-keepattributes *Annotation*
-keepclassmembers class * {
    @org.greenrobot.eventbus.Subscribe <methods>;
}
-keep enum org.greenrobot.eventbus.ThreadMode { *; }

# ── OkHttp ────────────────────────────────────────────────────────────────────
-dontwarn okhttp3.**
-dontwarn okio.**
