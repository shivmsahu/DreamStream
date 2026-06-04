# ML Kit / Mobile Scanner
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_barcode.** { *; }
-keep class com.google.android.gms.vision.** { *; }
-keep class com.google.android.odml.** { *; }

# Prevent compilation failures from missing SplitCompat classes (Flutter R8 bug)
-dontwarn com.google.android.play.core.**
-dontwarn io.flutter.embedding.**
-dontwarn android.window.**
