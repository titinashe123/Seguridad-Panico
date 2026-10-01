package com.alertaciudadana.alerta_ciudadana

import android.app.KeyguardManager
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.alertaciudadana/hardware_trigger"
    private var methodChannel: MethodChannel? = null
    private var pendingTriggerEmergency: Boolean = false
    private var pendingStopTrackingPin: Boolean = false
    private var pendingSource: String = "power_button_3x"

    companion object {
        const val EXTRA_TRIGGER_EMERGENCY = "EXTRA_TRIGGER_EMERGENCY"
        const val EXTRA_STOP_TRACKING_PIN = "EXTRA_STOP_TRACKING_PIN"
        var instance: MainActivity? = null
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        instance = this
        setupLockScreenFlags()

        // Iniciar el servicio en primer plano persistente para protección continua
        EmergencyForegroundService.startService(applicationContext)

        checkIntentExtras(intent)
    }

    private fun setupLockScreenFlags() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
            val keyguardManager = getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
            keyguardManager?.requestDismissKeyguard(this, null)
        }
        @Suppress("DEPRECATION")
        window.addFlags(
            WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
            WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD or
            WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
            WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
        )
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        setupLockScreenFlags()
        checkIntentExtras(intent)
    }

    private fun checkIntentExtras(intent: Intent?) {
        if (intent == null) return

        // Si se abre por emergencia, cancelar la notificación de alarma
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
        notificationManager?.cancel(EmergencyForegroundService.PANIC_NOTIFICATION_ID)

        if (intent.getBooleanExtra(EXTRA_TRIGGER_EMERGENCY, false)) {
            val src = intent.getStringExtra("source") ?: "power_button_3x"
            if (methodChannel != null) {
                triggerPanicFromNative(src)
            } else {
                pendingTriggerEmergency = true
                pendingSource = src
            }
        }

        if (intent.getBooleanExtra(EXTRA_STOP_TRACKING_PIN, false)) {
            if (methodChannel != null) {
                runOnUiThread {
                    methodChannel?.invokeMethod("onOpenStopTrackingDialog", null)
                }
            } else {
                pendingStopTrackingPin = true
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)

        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "startBackgroundService" -> {
                    EmergencyForegroundService.startService(applicationContext)
                    result.success(true)
                }
                "stopBackgroundService" -> {
                    EmergencyForegroundService.stopService(applicationContext)
                    result.success(true)
                }
                "updateLiveTrackingNotification" -> {
                    val isTracking = call.argument<Boolean>("isTracking") ?: false
                    EmergencyForegroundService.updateTrackingStatus(applicationContext, isTracking)
                    result.success(true)
                }
                "simulatePowerPress3x" -> {
                    triggerPanicFromNative("simulated_power_press_3x")
                    result.success(true)
                }
                "isNativeActive" -> {
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // Si había llamadas pendientes antes de que Flutter terminara de inicializar
        if (pendingTriggerEmergency) {
            pendingTriggerEmergency = false
            triggerPanicFromNative(pendingSource)
        }

        if (pendingStopTrackingPin) {
            pendingStopTrackingPin = false
            runOnUiThread {
                methodChannel?.invokeMethod("onOpenStopTrackingDialog", null)
            }
        }
    }

    private var lastPanicTriggerTime: Long = 0

    fun triggerPanicFromNative(source: String): Boolean {
        if (methodChannel == null) return false
        val now = System.currentTimeMillis()
        if (now - lastPanicTriggerTime < 1200) {
            // Ignorar disparos duplicados dentro de 1.2 segundos
            return true
        }
        lastPanicTriggerTime = now
        runOnUiThread {
            methodChannel?.invokeMethod("onPanicTriggered", mapOf("source" to source))
        }
        return true
    }

    override fun onDestroy() {
        if (instance == this) {
            instance = null
        }
        super.onDestroy()
    }
}
