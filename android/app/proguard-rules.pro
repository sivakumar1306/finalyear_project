# Room entities in data/ are Gson-serialized directly (via reflection) for the
# getReadings/getLatestReading/getMeasurementCycleHistory MethodChannel responses.
# Without this, R8 renames their fields to single letters (a, b, c, ...) and can
# strip the @SerializedName annotations meant to guard against exactly that,
# silently breaking every screen that reads raw local-DB readings.
-keep class com.sundr.myapp.data.** { *; }

# Attributes required by Gson reflection (runtime annotations like @SerializedName,
# generic signatures for TypeToken subclasses, anonymous/local class info).
-keepattributes Signature,EnclosingMethod,InnerClasses
-keepattributes AnnotationDefault
-keepattributes RuntimeVisibleAnnotations,RuntimeVisibleParameterAnnotations,RuntimeVisibleTypeAnnotations

# Gson 2.10.x ships its own consumer R8 rules, so no blanket -keep on gson.**
# (that would block R8 from stripping unused Gson internals). Only TypeToken
# subclasses created reflectively need explicit keeping here.
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-dontwarn sun.misc.**

# Vendor QRing / Oudmon BLE SDK (AAR) — R8 must not strip reflection/JNI entry points.
-keep class com.oudmon.** { *; }
-keep class com.realsil.** { *; }
-keep class com.jieli.** { *; }
-keepclassmembers class * {
    native <methods>;
}
-dontwarn com.oudmon.**
-dontwarn com.realsil.**
-dontwarn com.jieli.**
