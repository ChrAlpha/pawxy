package dev.pawxy

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.util.Log

class ControlActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val action = intent?.action
        if (action == ProxyService.ACTION_START || action == ProxyService.ACTION_RESTART) {
            val serviceIntent = Intent(this, ProxyService::class.java).setAction(action)
            intent?.extras?.let { serviceIntent.putExtras(it) }
            try {
                startForegroundService(serviceIntent)
            } catch (error: Throwable) {
                Log.e(TAG, "Could not bridge foreground service start", error)
            }
        } else {
            Log.w(TAG, "Ignoring unsupported control activity action: $action")
        }
        finishAndRemoveTask()
    }

    companion object {
        private const val TAG = "Pawxy"
    }
}
