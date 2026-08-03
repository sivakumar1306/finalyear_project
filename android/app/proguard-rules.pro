# Room entities in data/ are Gson-serialized directly (via reflection) for the
# getReadings/getLatestReading/getMeasurementCycleHistory MethodChannel responses.
# Without this, R8 renames their fields to single letters (a, b, c, ...) and can
# strip the @SerializedName annotations meant to guard against exactly that,
# silently breaking every screen that reads raw local-DB readings.
-keep class com.medxai.sundr.data.** { *; }
-keepattributes Signature
-keepattributes *Annotation*

# Gson uses reflection extensively; without these, TypeAdapter generation for
# arbitrary classes can break under R8 in ways that are hard to notice locally.
-keepattributes EnclosingMethod
-keepattributes InnerClasses
-dontwarn sun.misc.**
-keep class com.google.gson.** { *; }
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
