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
    private var pendingAlertType: String = "ROBO"

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
            val alertType = intent.getStringExtra("alert_type") ?: "ROBO"
            pendingTriggerEmergency = true
            pendingSource = src
            pendingAlertType = alertType
            triggerPanicFromNative(src, alertType)
        }

        if (intent.getBooleanExtra(EXTRA_STOP_TRACKING_PIN, false)) {
            pendingStopTrackingPin = true
            runOnUiThread {
                methodChannel?.invokeMethod("onOpenStopTrackingDialog", null)
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
                    triggerPanicFromNative("simulated_power_press_3x", "ROBO")
                    result.success(true)
                }
                "checkPendingTrigger" -> {
                    val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                    val isDispatched = prefs.getBoolean("flutter.pending_emergency_dispatched", false) || EmergencyForegroundService.isEmergencyDispatched
                    val nativeSuccess = prefs.getBoolean("flutter.native_dispatched_success", false)
                    val isActive = prefs.getBoolean("flutter.pending_emergency_active", false) || EmergencyForegroundService.isEmergencyActive
                    val source = prefs.getString("flutter.pending_emergency_source", pendingSource) ?: pendingSource
                    val alertType = prefs.getString("flutter.pending_emergency_alert_type", pendingAlertType) ?: pendingAlertType

                    if (isDispatched) {
                        prefs.edit()
                            .putBoolean("flutter.pending_emergency_dispatched", false)
                            .putBoolean("flutter.pending_emergency_active", false)
                            .putBoolean("flutter.native_dispatched_success", false)
                            .apply()
                        EmergencyForegroundService.isEmergencyDispatched = false
                        EmergencyForegroundService.isEmergencyActive = false
                        pendingTriggerEmergency = false

                        result.success(mapOf(
                            "hasPending" to true,
                            "isDispatched" to true,
                            "nativeSuccess" to nativeSuccess,
                            "source" to source,
                            "alertType" to alertType
                        ))
                    } else if (isActive || pendingTriggerEmergency) {
                        prefs.edit()
                            .putBoolean("flutter.pending_emergency_active", false)
                            .apply()
                        EmergencyForegroundService.isEmergencyActive = false
                        pendingTriggerEmergency = false

                        result.success(mapOf(
                            "hasPending" to true,
                            "isDispatched" to false,
                            "source" to source,
                            "alertType" to alertType
                        ))
                    } else {
                        result.success(mapOf("hasPending" to false))
                    }
                }
                "cancelEmergency" -> {
                    EmergencyForegroundService.cancelEmergency(applicationContext)
                    pendingTriggerEmergency = false
                    result.success(true)
                }
                "checkPendingStopTracking" -> {
                    if (pendingStopTrackingPin) {
                        pendingStopTrackingPin = false
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }
                "isNativeActive" -> {
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // Si había llamadas pendientes antes de que Flutter terminara de inicializar
        if (pendingTriggerEmergency) {
            triggerPanicFromNative(pendingSource, pendingAlertType)
        }

        if (pendingStopTrackingPin) {
            runOnUiThread {
                methodChannel?.invokeMethod("onOpenStopTrackingDialog", null)
            }
        }
    }

    private var lastPanicTriggerTime: Long = 0

    fun triggerPanicFromNative(source: String, alertType: String = "ROBO"): Boolean {
        pendingTriggerEmergency = true
        pendingSource = source
        pendingAlertType = alertType
        if (methodChannel == null) return false
        val now = System.currentTimeMillis()
        if (now - lastPanicTriggerTime < 1200) {
            // Ignorar disparos duplicados dentro de 1.2 segundos
            return true
        }
        lastPanicTriggerTime = now
        runOnUiThread {
            methodChannel?.invokeMethod("onPanicTriggered", mapOf("source" to source, "alertType" to alertType))
        }
        return true
    }

    fun onEmergencyDispatchedFromNative(alertType: String, source: String) {
        runOnUiThread {
            methodChannel?.invokeMethod("onEmergencyDispatched", mapOf("alertType" to alertType, "source" to source))
        }
    }

    override fun onDestroy() {
        if (instance == this) {
            instance = null
        }
        super.onDestroy()
    }
}
