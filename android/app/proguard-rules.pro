# Flutter's own rules cover the engine; these cover what R8 cannot see.

# ExoPlayer/Media3 behind video_player is reached reflectively.
-keep class androidx.media3.** { *; }
-dontwarn androidx.media3.**

# Keep the platform channel entry point.
-keep class com.edadras.lan_cast.MainActivity { *; }
