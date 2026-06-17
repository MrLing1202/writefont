# ML Kit
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_text.** { *; }
-dontwarn com.google.mlkit.**

# Native Key JNI — keep so R8 doesn't strip the native method
-keep class com.writefont.app.NativeKeyProvider { *; }
