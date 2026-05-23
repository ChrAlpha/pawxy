package dev.pawxy

import android.content.Context

class ControlToken(context: Context) {
    private val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun provisionIfNeeded(token: String?): Boolean {
        if (token.isNullOrBlank()) return false
        val stored = prefs.getString(KEY_CONTROL_TOKEN, null)
        if (stored == null) {
            prefs.edit().putString(KEY_CONTROL_TOKEN, token).apply()
            return true
        }
        return stored == token
    }

    fun validate(token: String?): Boolean {
        if (token.isNullOrBlank()) return false
        return prefs.getString(KEY_CONTROL_TOKEN, null) == token
    }

    companion object {
        const val PREFS = "pawxy"
        private const val KEY_CONTROL_TOKEN = "control_token"
    }
}
