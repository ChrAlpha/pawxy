package dev.pawxy

object PawxyNative {
    init {
        System.loadLibrary("pawxy_jni")
    }

    external fun nativeStart(configJson: String): String
    external fun nativeStop(): String
    external fun nativeStatus(): String
}
