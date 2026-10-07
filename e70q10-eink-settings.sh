#!/system/bin/sh

# SettingsProvider owns these values. Reapply after framework boot so both the
# reference launcher and later Total Launcher use E Ink-safe defaults.
/system/bin/settings put global window_animation_scale 0
/system/bin/settings put global transition_animation_scale 0
/system/bin/settings put global animator_duration_scale 0
/system/bin/settings put system accelerometer_rotation 0
/system/bin/settings put system user_rotation 0
/system/bin/settings put system haptic_feedback_enabled 0
/system/bin/settings put system sound_effects_enabled 0
/system/bin/settings put system lockscreen_sounds_enabled 0
