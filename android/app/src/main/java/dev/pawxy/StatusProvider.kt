package dev.pawxy

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import org.json.JSONObject

class StatusProvider : ContentProvider() {
    override fun onCreate(): Boolean = true

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?
    ): Cursor {
        val cursor = MatrixCursor(arrayOf("json"))
        val context = context ?: run {
            cursor.addRow(arrayOf("""{"ok":false,"error":"provider context unavailable"}"""))
            return cursor
        }
        val token = uri.pathSegments.getOrNull(1)
        if (uri.pathSegments.getOrNull(0) != "status" || !ControlToken(context).validate(token)) {
            cursor.addRow(arrayOf("""{"ok":false,"error":"unauthorized"}"""))
            return cursor
        }

        val nativeJson = try {
            JSONObject(PawxyNative.nativeStatus())
        } catch (error: Throwable) {
            JSONObject()
                .put("ok", false)
                .put("error", error.message ?: "native status failed")
        }
        val prefs = context.getSharedPreferences(ControlToken.PREFS, android.content.Context.MODE_PRIVATE)
        nativeJson
            .put("wake_lock_enabled", prefs.getBoolean(ProxyService.KEY_WAKE_LOCK_ENABLED, false))
            .put("service_started", prefs.getBoolean(ProxyService.KEY_SERVICE_STARTED, false))
            .put("listen", prefs.getString(ProxyService.KEY_LISTEN, nativeJson.optString("listen")))
            .put("lan", prefs.getBoolean(ProxyService.KEY_LAN, nativeJson.optBoolean("lan", false)))
            .put(
                "auth_enabled",
                prefs.getBoolean(
                    ProxyService.KEY_AUTH_ENABLED,
                    nativeJson.optBoolean("auth_enabled", false)
                )
            )
        cursor.addRow(arrayOf(nativeJson.toString()))
        return cursor
    }

    override fun getType(uri: Uri): String = "application/json"

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null

    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0

    override fun update(
        uri: Uri,
        values: ContentValues?,
        selection: String?,
        selectionArgs: Array<out String>?
    ): Int = 0
}
