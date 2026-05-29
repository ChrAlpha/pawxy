package dev.pawxy

import android.content.Context

class ControlToken(context: Context) {
    private val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun provisionIfNeeded(token: String?): Boolean {
        if (!isValidToken(token)) return false
        val stored = prefs.getString(KEY_CONTROL_TOKEN, null)
        if (stored == null) {
            return prefs.edit().putString(KEY_CONTROL_TOKEN, token).commit()
        }
        return stored == token
    }

    fun validate(token: String?): Boolean {
        if (!isValidToken(token)) return false
        return prefs.getString(KEY_CONTROL_TOKEN, null) == token
    }

    fun replace(token: String?): Boolean {
        if (!isValidToken(token)) return false
        return prefs.edit().putString(KEY_CONTROL_TOKEN, token).commit()
    }

    private fun isValidToken(token: String?): Boolean {
        if (token == null || token.length != 64) return false
        return token.all { it in '0'..'9' || it in 'a'..'f' || it in 'A'..'F' }
    }

    companion object {
        const val PREFS = "pawxy"
        private const val KEY_CONTROL_TOKEN = "control_token"
    }
}
