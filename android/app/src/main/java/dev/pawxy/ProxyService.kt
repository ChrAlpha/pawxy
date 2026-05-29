package dev.pawxy

import android.app.Service
import android.content.Intent
import android.content.SharedPreferences
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import org.json.JSONObject

class ProxyService : Service() {
    private lateinit var prefs: SharedPreferences
    private lateinit var controlToken: ControlToken
    private lateinit var notificationHelper: NotificationHelper
    private var wakeLock: PowerManager.WakeLock? = null
    private var connectivityManager: ConnectivityManager? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private var foregroundStarted = false

    override fun onCreate() {
        super.onCreate()
        prefs = getSharedPreferences(ControlToken.PREFS, MODE_PRIVATE)
        controlToken = ControlToken(this)
        notificationHelper = NotificationHelper(this)
        registerDefaultNetworkCallback()
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
                startFromIntent(intent, startId, forceRestart = false)
            }
            ACTION_RESTART -> {
                if (!controlToken.validate(token)) return rejectUnauthorized(intent.action, startId)
                startFromIntent(intent, startId, forceRestart = true)
            }
            ACTION_STOP -> {
                if (!controlToken.validate(token)) return rejectUnauthorized(intent.action, startId)
                stopProxy()
                START_NOT_STICKY
            }
            ACTION_RESET_TOKEN -> {
                if (!controlToken.replace(token)) return rejectUnauthorized(intent.action, startId)
                Log.i(TAG, "Control token reset through privileged control surface")
                if (foregroundStarted) {
                    START_STICKY
                } else {
                    stopUnauthorizedStart(startId)
                    START_NOT_STICKY
                }
            }
            ACTION_WAKE_ON -> {
                if (!controlToken.validate(token)) return rejectUnauthorized(intent.action, startId)
                handleWakeAction(true, startId)
            }
            ACTION_WAKE_OFF -> {
                if (!controlToken.validate(token)) return rejectUnauthorized(intent.action, startId)
                handleWakeAction(false, startId)
            }
            else -> {
                rejectUnknownAction(intent.action, startId)
            }
        }
    }

    override fun onDestroy() {
        unregisterNetworkCallback()
        safeNativeStop()
        setWakeLock(false)
        safeStopForeground()
        super.onDestroy()
    }

    private fun startFromIntent(intent: Intent, startId: Int, forceRestart: Boolean): Int {
        val config = buildConfigJson(intent, forceRestart)
        val listen = config.getString("listen")
        val lan = intent.getBooleanExtra(EXTRA_LAN, listen.startsWith("0.0.0.0"))
        val authEnabled = config.optBoolean("auth_enabled", false)
        if (isLanListen(listen) && !authEnabled) {
            return rejectUnsafeLanListen(listen, startId)
        }
        validateConfigBeforeForeground(config)?.let { reason ->
            return rejectInvalidStartConfig(reason, startId)
        }
        if (!startForegroundSafely(listen, prefs.getBoolean(KEY_WAKE_LOCK_ENABLED, false))) {
            return handleForegroundStartFailure(startId)
        }

        val result = safeNativeStart(config.toString())
        Log.i(TAG, "nativeStart: $result")
        if (!nativeStartSucceeded(result)) {
            return handleNativeStartFailure(result, startId)
        }
        if (!persistAcceptedConfig(config, listen, lan, authEnabled)) {
            return handleAcceptedConfigPersistFailure(startId)
        }
        syncWakeLockWithPreference()
        return START_STICKY
    }

    private fun persistedConfigJson(config: JSONObject): String {
        val persisted = JSONObject(config.toString())
        persisted.remove("force_restart")
        return persisted.toString()
    }

    private fun restartFromSavedConfig(startId: Int): Int {
        if (!prefs.getBoolean(KEY_SERVICE_STARTED, false)) {
            setWakeLock(false)
            commitPrefs(
                prefs.edit().putBoolean(KEY_WAKE_LOCK_ENABLED, false),
                "stopped wake-lock state"
            )
            stopSelf(startId)
            return START_NOT_STICKY
        }
        val config = prefs.getString(KEY_CONFIG_JSON, null)
        if (config.isNullOrBlank()) {
            stopSelf(startId)
            return START_NOT_STICKY
        }
        if (!refreshForeground()) {
            return handleForegroundStartFailure(startId)
        }
        val result = safeNativeStart(config)
        Log.i(TAG, "nativeStart after service restart: $result")
        if (!nativeStartSucceeded(result)) {
            return handleNativeStartFailure(result, startId)
        }
        syncWakeLockWithPreference()
        commitPrefs(
            prefs.edit().putBoolean(KEY_SERVICE_STARTED, true),
            "restored service state"
        )
        return START_STICKY
    }

    private fun stopProxy() {
        val result = safeNativeStop()
        Log.i(TAG, "nativeStop: $result")
        setWakeLock(false)
        commitPrefs(
            prefs.edit()
                .putBoolean(KEY_WAKE_LOCK_ENABLED, false)
                .putBoolean(KEY_SERVICE_STARTED, false),
            "stopped proxy state"
        )
        safeStopForeground()
        stopSelf()
    }

    private fun refreshForeground(): Boolean {
        val listen = prefs.getString(KEY_LISTEN, DEFAULT_LISTEN) ?: DEFAULT_LISTEN
        return startForegroundSafely(listen, prefs.getBoolean(KEY_WAKE_LOCK_ENABLED, false))
    }

    private fun startForegroundSafely(listen: String, wakeLockEnabled: Boolean): Boolean {
        return try {
            startForeground(
                NotificationHelper.NOTIFICATION_ID,
                notificationHelper.build(listen, wakeLockEnabled)
            )
            foregroundStarted = true
            true
        } catch (error: Throwable) {
            Log.e(TAG, "Could not enter foreground service", error)
            foregroundStarted = false
            false
        }
    }

    private fun safeStopForeground() {
        if (!foregroundStarted) return
        try {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } catch (error: Throwable) {
            Log.w(TAG, "Could not leave foreground service", error)
        } finally {
            foregroundStarted = false
        }
    }

    private fun syncWakeLockWithPreference() {
        val actual = setWakeLock(prefs.getBoolean(KEY_WAKE_LOCK_ENABLED, false))
        commitPrefs(
            prefs.edit().putBoolean(KEY_WAKE_LOCK_ENABLED, actual),
            "wake-lock state"
        )
    }

    private fun persistAcceptedConfig(config: JSONObject, listen: String, lan: Boolean, authEnabled: Boolean): Boolean {
        return commitPrefs(
            prefs.edit()
                .putString(KEY_CONFIG_JSON, persistedConfigJson(config))
                .putString(KEY_LISTEN, listen)
                .putBoolean(KEY_LAN, lan)
                .putBoolean(KEY_AUTH_ENABLED, authEnabled)
                .putBoolean(KEY_SERVICE_STARTED, true),
            "accepted proxy config"
        )
    }

    private fun commitPrefs(editor: SharedPreferences.Editor, label: String): Boolean {
        val persisted = editor.commit()
        if (!persisted) {
            Log.w(TAG, "Could not persist $label")
        }
        return persisted
    }

    private fun nativeStartSucceeded(result: String): Boolean {
        return try {
            JSONObject(result).optBoolean("running", false)
        } catch (_: Exception) {
            false
        }
    }

    private fun safeNativeStart(config: String): String {
        return try {
            PawxyNative.nativeStart(config)
        } catch (error: Throwable) {
            Log.e(TAG, "Native proxy threw during startup", error)
            JSONObject()
                .put("ok", false)
                .put("error", error.message ?: error.javaClass.name)
                .toString()
        }
    }

    private fun safeNativeStop(): String {
        return try {
            PawxyNative.nativeStop()
        } catch (error: Throwable) {
            Log.e(TAG, "Native proxy threw during stop", error)
            JSONObject()
                .put("ok", false)
                .put("error", error.message ?: error.javaClass.name)
                .toString()
        }
    }

    private fun handleNativeStartFailure(result: String, startId: Int): Int {
        Log.w(TAG, "Native proxy failed to start: $result")
        if (isNativeRunning()) {
            Log.w(TAG, "Keeping existing native proxy after rejected start")
            refreshForeground()
            return START_STICKY
        }
        setWakeLock(false)
        commitPrefs(
            prefs.edit()
                .putBoolean(KEY_WAKE_LOCK_ENABLED, false)
                .putBoolean(KEY_SERVICE_STARTED, false),
            "failed native-start state"
        )
        safeStopForeground()
        stopSelf(startId)
        return START_NOT_STICKY
    }

    private fun handleAcceptedConfigPersistFailure(startId: Int): Int {
        Log.w(TAG, "Accepted proxy config did not persist; stopping native proxy")
        val result = safeNativeStop()
        Log.i(TAG, "nativeStop after persistence failure: $result")
        setWakeLock(false)
        commitPrefs(
            prefs.edit()
                .putBoolean(KEY_WAKE_LOCK_ENABLED, false)
                .putBoolean(KEY_SERVICE_STARTED, false),
            "failed persistence cleanup"
        )
        safeStopForeground()
        stopSelf(startId)
        return START_NOT_STICKY
    }

    private fun handleForegroundStartFailure(startId: Int): Int {
        val result = safeNativeStop()
        Log.i(TAG, "nativeStop after foreground failure: $result")
        setWakeLock(false)
        commitPrefs(
            prefs.edit()
                .putBoolean(KEY_WAKE_LOCK_ENABLED, false)
                .putBoolean(KEY_SERVICE_STARTED, false),
            "failed foreground-start state"
        )
        stopSelf(startId)
        return START_NOT_STICKY
    }

    private fun handleWakeAction(enabled: Boolean, startId: Int): Int {
        if (!isNativeRunning()) {
            Log.w(TAG, "Ignored wake lock change while proxy is not running")
            setWakeLock(false)
            commitPrefs(
                prefs.edit().putBoolean(KEY_WAKE_LOCK_ENABLED, false),
                "ignored wake-lock state"
            )
            safeStopForeground()
            stopSelf(startId)
            return START_NOT_STICKY
        }

        val actual = setWakeLock(enabled)
        commitPrefs(
            prefs.edit().putBoolean(KEY_WAKE_LOCK_ENABLED, actual),
            "wake-lock control state"
        )
        if (!refreshForeground()) {
            return handleForegroundStartFailure(startId)
        }
        return START_STICKY
    }

    private fun isNativeRunning(): Boolean {
        return try {
            JSONObject(PawxyNative.nativeStatus()).optBoolean("running", false)
        } catch (_: Throwable) {
            false
        }
    }

    private fun rejectUnauthorized(action: String?, startId: Int): Int {
        Log.w(TAG, "Rejected unauthorized control action: $action")
        if (foregroundStarted) {
            return START_STICKY
        }
        stopUnauthorizedStart(startId)
        return START_NOT_STICKY
    }

    private fun rejectUnknownAction(action: String?, startId: Int): Int {
        Log.w(TAG, "Unknown action: $action")
        if (foregroundStarted) {
            return START_STICKY
        }
        stopUnauthorizedStart(startId)
        return START_NOT_STICKY
    }

    private fun rejectUnsafeLanListen(listen: String, startId: Int): Int {
        Log.w(TAG, "Rejected unsafe LAN listen without proxy authentication: $listen")
        if (foregroundStarted) {
            return START_STICKY
        }
        stopUnauthorizedStart(startId)
        return START_NOT_STICKY
    }

    private fun rejectInvalidStartConfig(reason: String, startId: Int): Int {
        Log.w(TAG, "Rejected invalid start config before foreground update: $reason")
        if (foregroundStarted) {
            return START_STICKY
        }
        stopUnauthorizedStart(startId)
        return START_NOT_STICKY
    }

    private fun stopUnauthorizedStart(startId: Int) {
        stopSelf(startId)
    }

    private fun buildConfigJson(intent: Intent, forceRestart: Boolean): JSONObject {
        val listen = intent.getStringExtra(EXTRA_LISTEN) ?: DEFAULT_LISTEN
        val authEnabled = intent.getBooleanExtra(EXTRA_AUTH_ENABLED, false)
        val json = JSONObject()
            .put("listen", listen)
            .put("auth_enabled", authEnabled)
            .put("force_restart", forceRestart)
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

    private fun validateConfigBeforeForeground(config: JSONObject): String? {
        val listen = parseListen(config.optString("listen", ""))
            ?: return "invalid listen socket address"
        if (listen.first != "127.0.0.1" && listen.first != "0.0.0.0") {
            return "listen address must be 127.0.0.1 or 0.0.0.0"
        }
        if (listen.second == 0) {
            return "listen port must be explicit"
        }
        if (listen.second < 1024) {
            return "listen port must be at least 1024"
        }
        validatePositiveCappedLong(config, "max_connections", MAX_CONNECTIONS_LIMIT)?.let { return it }
        validatePositiveCappedLong(config, "max_per_source_ip", MAX_PER_SOURCE_IP_LIMIT)?.let { return it }
        validatePositiveCappedLong(config, "handshake_timeout_ms", MAX_HANDSHAKE_TIMEOUT_MS)?.let { return it }
        validatePositiveCappedLong(config, "connect_timeout_ms", MAX_CONNECT_TIMEOUT_MS)?.let { return it }
        validatePositiveCappedLong(config, "idle_timeout_ms", MAX_IDLE_TIMEOUT_MS)?.let { return it }
        if (config.optBoolean("auth_enabled", false)) {
            if (config.optString("username", "").isBlank()) return "auth username is required"
            if (config.optString("password", "").isBlank()) return "auth password is required"
        }
        return null
    }

    private fun parseListen(value: String): Pair<String, Int>? {
        val separator = value.lastIndexOf(':')
        if (separator <= 0 || separator == value.length - 1) return null
        val host = value.substring(0, separator)
        val portText = value.substring(separator + 1)
        if (!portText.all { it in '0'..'9' }) return null
        val port = portText.toIntOrNull() ?: return null
        if (port > 65535) return null
        return Pair(host, port)
    }

    private fun validatePositiveCappedLong(config: JSONObject, key: String, max: Long): String? {
        val value = config.optLong(key, -1L)
        if (value <= 0L) return "$key must be greater than zero"
        if (value > max) return "$key must be at most $max"
        return null
    }

    private fun setWakeLock(enabled: Boolean): Boolean {
        if (enabled) {
            val existing = wakeLock
            if (existing?.isHeld == true) return true
            return try {
                val powerManager = getSystemService(PowerManager::class.java)
                wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Pawxy:proxy")
                    .also { it.acquire() }
                true
            } catch (error: Throwable) {
                Log.w(TAG, "Could not enable wake lock", error)
                wakeLock = null
                false
            }
        } else {
            try {
                wakeLock?.let {
                    if (it.isHeld) it.release()
                }
            } catch (error: Throwable) {
                Log.w(TAG, "Could not disable wake lock", error)
            }
            wakeLock = null
            return false
        }
    }

    private fun isLanListen(listen: String): Boolean {
        return listen.startsWith("0.0.0.0:") || listen.startsWith("[::]:") || listen.startsWith(":::")
    }

    private fun registerDefaultNetworkCallback() {
        val manager = getSystemService(ConnectivityManager::class.java) ?: return
        connectivityManager = manager
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                updateNetworkState(true, manager.getNetworkCapabilities(network))
            }

            override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) {
                updateNetworkState(true, capabilities)
            }

            override fun onLost(network: Network) {
                val activeNetwork = manager.activeNetwork
                val capabilities = activeNetwork?.let { manager.getNetworkCapabilities(it) }
                updateNetworkState(activeNetwork != null, capabilities)
            }
        }

        try {
            manager.registerDefaultNetworkCallback(callback)
            networkCallback = callback
            val activeNetwork = manager.activeNetwork
            val capabilities = activeNetwork?.let { manager.getNetworkCapabilities(it) }
            updateNetworkState(activeNetwork != null, capabilities)
        } catch (error: RuntimeException) {
            Log.w(TAG, "Could not observe default network", error)
        }
    }

    private fun unregisterNetworkCallback() {
        val manager = connectivityManager ?: return
        val callback = networkCallback ?: return
        try {
            manager.unregisterNetworkCallback(callback)
        } catch (error: RuntimeException) {
            Log.w(TAG, "Could not unregister default network callback", error)
        } finally {
            networkCallback = null
        }
    }

    private fun updateNetworkState(available: Boolean, capabilities: NetworkCapabilities?) {
        val transport = networkTransport(capabilities)
        val nextGeneration = prefs.getLong(KEY_NETWORK_GENERATION, 0L) + 1L
        prefs.edit()
            .putBoolean(KEY_NETWORK_AVAILABLE, available)
            .putString(KEY_NETWORK_TRANSPORT, transport)
            .putLong(KEY_NETWORK_GENERATION, nextGeneration)
            .apply()
        Log.i(TAG, "Default network changed: available=$available transport=$transport generation=$nextGeneration")
    }

    private fun networkTransport(capabilities: NetworkCapabilities?): String {
        if (capabilities == null) return "none"
        val transports = mutableListOf<String>()
        if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) transports.add("vpn")
        if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) transports.add("wifi")
        if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)) transports.add("cellular")
        if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)) transports.add("ethernet")
        if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_BLUETOOTH)) transports.add("bluetooth")
        return if (transports.isEmpty()) "other" else transports.joinToString(",")
    }

    companion object {
        private const val TAG = "Pawxy"
        const val ACTION_START = "dev.pawxy.action.START"
        const val ACTION_STOP = "dev.pawxy.action.STOP"
        const val ACTION_RESTART = "dev.pawxy.action.RESTART"
        const val ACTION_RESET_TOKEN = "dev.pawxy.action.RESET_TOKEN"
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
        const val KEY_NETWORK_AVAILABLE = "network_available"
        const val KEY_NETWORK_TRANSPORT = "network_transport"
        const val KEY_NETWORK_GENERATION = "network_generation"
        const val DEFAULT_LISTEN = "127.0.0.1:3218"
        private const val MAX_CONNECTIONS_LIMIT = 4096L
        private const val MAX_PER_SOURCE_IP_LIMIT = 1024L
        private const val MAX_HANDSHAKE_TIMEOUT_MS = 60_000L
        private const val MAX_CONNECT_TIMEOUT_MS = 60_000L
        private const val MAX_IDLE_TIMEOUT_MS = 86_400_000L
    }
}
