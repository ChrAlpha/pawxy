package dev.pawxy

import android.app.Service
import android.content.Intent
import android.content.SharedPreferences
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import org.json.JSONObject

class ProxyService : Service() {
    private lateinit var prefs: SharedPreferences
    private lateinit var controlToken: ControlToken
    private lateinit var notificationHelper: NotificationHelper
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onCreate() {
        super.onCreate()
        prefs = getSharedPreferences(ControlToken.PREFS, MODE_PRIVATE)
        controlToken = ControlToken(this)
        notificationHelper = NotificationHelper(this)
        if (prefs.getBoolean(KEY_WAKE_LOCK_ENABLED, false)) {
            setWakeLock(true)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent == null) {
            return restartFromSavedConfig(startId)
        }

        val token = intent.getStringExtra(EXTRA_TOKEN)
        return when (intent.action) {
            ACTION_START -> {
                if (!controlToken.provisionIfNeeded(token)) return rejectUnauthorized(intent.action, startId)
                startFromIntent(intent)
            }
            ACTION_RESTART -> {
                if (!controlToken.validate(token)) return rejectUnauthorized(intent.action, startId)
                PawxyNative.nativeStop()
                startFromIntent(intent)
            }
            ACTION_STOP -> {
                if (!controlToken.validate(token)) return rejectUnauthorized(intent.action, startId)
                stopProxy()
                START_NOT_STICKY
            }
            ACTION_WAKE_ON -> {
                if (!controlToken.validate(token)) return rejectUnauthorized(intent.action, startId)
                setWakeLock(true)
                prefs.edit().putBoolean(KEY_WAKE_LOCK_ENABLED, true).apply()
                refreshForeground()
                START_STICKY
            }
            ACTION_WAKE_OFF -> {
                if (!controlToken.validate(token)) return rejectUnauthorized(intent.action, startId)
                setWakeLock(false)
                prefs.edit().putBoolean(KEY_WAKE_LOCK_ENABLED, false).apply()
                refreshForeground()
                START_STICKY
            }
            else -> {
                Log.w(TAG, "Unknown action: ${intent.action}")
                stopSelf(startId)
                START_NOT_STICKY
            }
        }
    }

    override fun onDestroy() {
        PawxyNative.nativeStop()
        setWakeLock(false)
        super.onDestroy()
    }

    private fun startFromIntent(intent: Intent): Int {
        val config = buildConfigJson(intent)
        val listen = config.getString("listen")
        val lan = intent.getBooleanExtra(EXTRA_LAN, listen.startsWith("0.0.0.0"))
        val authEnabled = config.optBoolean("auth_enabled", false)
        if (isLanListen(listen) && !authEnabled) {
            Log.w(TAG, "Rejected unsafe LAN listen without proxy authentication: $listen")
            stopSelf()
            return START_NOT_STICKY
        }
        prefs.edit()
            .putString(KEY_CONFIG_JSON, config.toString())
            .putString(KEY_LISTEN, listen)
            .putBoolean(KEY_LAN, lan)
            .putBoolean(KEY_AUTH_ENABLED, authEnabled)
            .putBoolean(KEY_SERVICE_STARTED, true)
            .apply()

        startForeground(
            NotificationHelper.NOTIFICATION_ID,
            notificationHelper.build(listen, prefs.getBoolean(KEY_WAKE_LOCK_ENABLED, false))
        )
        val result = PawxyNative.nativeStart(config.toString())
        Log.i(TAG, "nativeStart: $result")
        return START_STICKY
    }

    private fun restartFromSavedConfig(startId: Int): Int {
        val config = prefs.getString(KEY_CONFIG_JSON, null)
        if (config.isNullOrBlank()) {
            stopSelf(startId)
            return START_NOT_STICKY
        }
        refreshForeground()
        val result = PawxyNative.nativeStart(config)
        prefs.edit().putBoolean(KEY_SERVICE_STARTED, true).apply()
        Log.i(TAG, "nativeStart after service restart: $result")
        return START_STICKY
    }

    private fun stopProxy() {
        val result = PawxyNative.nativeStop()
        Log.i(TAG, "nativeStop: $result")
        setWakeLock(false)
        prefs.edit()
            .putBoolean(KEY_WAKE_LOCK_ENABLED, false)
            .putBoolean(KEY_SERVICE_STARTED, false)
            .apply()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun refreshForeground() {
        val listen = prefs.getString(KEY_LISTEN, DEFAULT_LISTEN) ?: DEFAULT_LISTEN
        startForeground(
            NotificationHelper.NOTIFICATION_ID,
            notificationHelper.build(listen, prefs.getBoolean(KEY_WAKE_LOCK_ENABLED, false))
        )
    }

    private fun rejectUnauthorized(action: String?, startId: Int): Int {
        Log.w(TAG, "Rejected unauthorized control action: $action")
        stopSelf(startId)
        return START_NOT_STICKY
    }

    private fun buildConfigJson(intent: Intent): JSONObject {
        val listen = intent.getStringExtra(EXTRA_LISTEN) ?: DEFAULT_LISTEN
        val authEnabled = intent.getBooleanExtra(EXTRA_AUTH_ENABLED, false)
        val json = JSONObject()
            .put("listen", listen)
            .put("auth_enabled", authEnabled)
            .put("max_connections", intent.getIntExtra(EXTRA_MAX_CONNECTIONS, 256))
            .put("max_per_source_ip", intent.getIntExtra(EXTRA_MAX_PER_SOURCE_IP, 64))
            .put("handshake_timeout_ms", intent.getLongExtra(EXTRA_HANDSHAKE_TIMEOUT_MS, 5000L))
            .put("connect_timeout_ms", intent.getLongExtra(EXTRA_CONNECT_TIMEOUT_MS, 10000L))
            .put("idle_timeout_ms", intent.getLongExtra(EXTRA_IDLE_TIMEOUT_MS, 1800000L))
            .put("tcp_nodelay", true)
            .put("tcp_keepalive", true)
        if (authEnabled) {
            json.put("username", intent.getStringExtra(EXTRA_USERNAME) ?: "pawxy")
            json.put("password", intent.getStringExtra(EXTRA_PASSWORD) ?: "")
        }
        return json
    }

    private fun setWakeLock(enabled: Boolean) {
        if (enabled) {
            val existing = wakeLock
            if (existing?.isHeld == true) return
            val powerManager = getSystemService(PowerManager::class.java)
            wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Pawxy:proxy")
                .also { it.acquire() }
        } else {
            wakeLock?.let {
                if (it.isHeld) it.release()
            }
            wakeLock = null
        }
    }

    private fun isLanListen(listen: String): Boolean {
        return listen.startsWith("0.0.0.0:") || listen.startsWith("[::]:") || listen.startsWith(":::")
    }

    companion object {
        private const val TAG = "Pawxy"
        const val ACTION_START = "dev.pawxy.action.START"
        const val ACTION_STOP = "dev.pawxy.action.STOP"
        const val ACTION_RESTART = "dev.pawxy.action.RESTART"
        const val ACTION_WAKE_ON = "dev.pawxy.action.WAKE_ON"
        const val ACTION_WAKE_OFF = "dev.pawxy.action.WAKE_OFF"

        const val EXTRA_TOKEN = "token"
        const val EXTRA_LISTEN = "listen"
        const val EXTRA_LAN = "lan"
        const val EXTRA_AUTH_ENABLED = "auth_enabled"
        const val EXTRA_USERNAME = "username"
        const val EXTRA_PASSWORD = "password"
        const val EXTRA_MAX_CONNECTIONS = "max_connections"
        const val EXTRA_MAX_PER_SOURCE_IP = "max_per_source_ip"
        const val EXTRA_HANDSHAKE_TIMEOUT_MS = "handshake_timeout_ms"
        const val EXTRA_CONNECT_TIMEOUT_MS = "connect_timeout_ms"
        const val EXTRA_IDLE_TIMEOUT_MS = "idle_timeout_ms"

        const val KEY_CONFIG_JSON = "config_json"
        const val KEY_LISTEN = "listen"
        const val KEY_LAN = "lan"
        const val KEY_AUTH_ENABLED = "auth_enabled"
        const val KEY_WAKE_LOCK_ENABLED = "wake_lock_enabled"
        const val KEY_SERVICE_STARTED = "service_started"
        const val DEFAULT_LISTEN = "127.0.0.1:7890"
    }
}
