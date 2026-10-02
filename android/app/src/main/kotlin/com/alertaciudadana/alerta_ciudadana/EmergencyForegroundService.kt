package com.alertaciudadana.alerta_ciudadana

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.os.SystemClock
import android.os.VibrationEffect
import android.os.Vibrator
import androidx.core.app.NotificationCompat

class EmergencyForegroundService : Service() {

    private val powerPressTimestamps = mutableListOf<Long>()
    private var screenReceiver: BroadcastReceiver? = null
    private var isLiveTrackingActive: Boolean = false

    private var sensorManager: SensorManager? = null
    private var accelerometer: Sensor? = null
    private var sensorEventListener: SensorEventListener? = null
    private var lastAccidentTriggerTime: Long = 0

    companion object {
        const val CHANNEL_ID = "alerta_ciudadana_protection_channel"
        const val EMERGENCY_ALARM_CHANNEL_ID = "alerta_ciudadana_emergency_alarm"
        const val NOTIFICATION_ID = 1001
        const val PANIC_NOTIFICATION_ID = 9999

        const val ACTION_START_GUARD = "ACTION_START_GUARD"
        const val ACTION_STOP_GUARD = "ACTION_STOP_GUARD"
        const val ACTION_SET_TRACKING = "ACTION_SET_TRACKING"
        const val EXTRA_IS_TRACKING = "EXTRA_IS_TRACKING"

        var isServiceRunning = false

        fun startService(context: Context) {
            val intent = Intent(context, EmergencyForegroundService::class.java).apply {
                action = ACTION_START_GUARD
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun updateTrackingStatus(context: Context, isTracking: Boolean) {
            val intent = Intent(context, EmergencyForegroundService::class.java).apply {
                action = ACTION_SET_TRACKING
                putExtra(EXTRA_IS_TRACKING, isTracking)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stopService(context: Context) {
            val intent = Intent(context, EmergencyForegroundService::class.java).apply {
                action = ACTION_STOP_GUARD
            }
            context.stopService(intent)
        }
    }

    override fun onCreate() {
        super.onCreate()
        isServiceRunning = true
        createNotificationChannels()
        registerScreenReceiver()
        registerSensorListener()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP_GUARD -> {
                stopForeground(true)
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_SET_TRACKING -> {
                isLiveTrackingActive = intent.getBooleanExtra(EXTRA_IS_TRACKING, false)
            }
        }

        registerScreenReceiver()
        registerSensorListener()

        val notification = buildCurrentNotification()
        startForeground(NOTIFICATION_ID, notification)

        return START_STICKY
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager

            // 1. Canal de guardia permanente (discreto)
            val guardChannel = NotificationChannel(
                CHANNEL_ID,
                "Protección de Seguridad Continua",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Monitoreo del botón de encendido (3x) y estado de protección"
                setShowBadge(false)
            }
            manager?.createNotificationChannel(guardChannel)

            // 2. Canal de emergencia máxima para Full-Screen Intent y Heads-Up emergente
            val alarmChannel = NotificationChannel(
                EMERGENCY_ALARM_CHANNEL_ID,
                "Alarma de Emergencia Inmediata",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Muestra la pantalla de cancelación por PIN fuera de la aplicación"
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 300, 150, 300)
            }
            manager?.createNotificationChannel(alarmChannel)
        }
    }

    private fun buildCurrentNotification(): Notification {
        val appIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val appPendingIntent = PendingIntent.getActivity(
            this,
            0,
            appIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val smallIcon = applicationInfo.icon.takeIf { it != 0 } ?: android.R.drawable.ic_lock_idle_alarm

        if (isLiveTrackingActive) {
            val stopTrackingIntent = Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra(MainActivity.EXTRA_STOP_TRACKING_PIN, true)
            }
            val stopTrackingPendingIntent = PendingIntent.getActivity(
                this,
                1,
                stopTrackingIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            return NotificationCompat.Builder(this, CHANNEL_ID)
                .setSmallIcon(smallIcon)
                .setContentTitle("🚨 RASTREO GPS EN VIVO: ROBO ACTIVO")
                .setContentText("Transmitiendo tu ubicación en tiempo real a la Central...")
                .setStyle(NotificationCompat.BigTextStyle().bigText("Transmitiendo tu ubicación en tiempo real a la Central de Video Vigilancia.\nToca para abrir o presiona el botón inferior para detener."))
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setOngoing(true)
                .setContentIntent(stopTrackingPendingIntent)
                .addAction(
                    android.R.drawable.ic_delete,
                    "🛑 DETENER TRANSMISIÓN (PIN)",
                    stopTrackingPendingIntent
                )
                .build()
        } else {
            return NotificationCompat.Builder(this, CHANNEL_ID)
                .setSmallIcon(smallIcon)
                .setContentTitle("AlertaCiudadana - Protección Activa")
                .setContentText("Monitoreando botón de encendido (3x) para emergencias")
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .setOngoing(true)
                .setContentIntent(appPendingIntent)
                .build()
        }
    }

    private fun registerScreenReceiver() {
        if (screenReceiver != null) return
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(Intent.ACTION_SCREEN_ON)
        }

        screenReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                val now = System.currentTimeMillis()
                powerPressTimestamps.add(now)

                // Ventana ágil para 3 pulsaciones rápidas (2200ms)
                powerPressTimestamps.removeAll { now - it > 2200 }

                if (powerPressTimestamps.size >= 3) {
                    powerPressTimestamps.clear()
                    onTriplePowerPressDetected()
                }
            }
        }

        registerReceiver(screenReceiver, filter)
    }

    private fun registerSensorListener() {
        if (sensorManager != null) return
        try {
            sensorManager = getSystemService(Context.SENSOR_SERVICE) as? SensorManager
            accelerometer = sensorManager?.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
            if (accelerometer != null) {
                sensorEventListener = object : SensorEventListener {
                    override fun onSensorChanged(event: SensorEvent?) {
                        if (event == null) return
                        val x = event.values[0]
                        val y = event.values[1]
                        val z = event.values[2]
                        // Magnitud de aceleración total (incluyendo gravedad 9.8 m/s²)
                        val magnitude = Math.sqrt((x * x + y * y + z * z).toDouble()).toFloat()
                        // Umbral de impacto severo o caída brusca (28.0 m/s², aprox 2.85G)
                        if (magnitude > 28.0f) {
                            val now = System.currentTimeMillis()
                            if (now - lastAccidentTriggerTime > 10000) { // Debounce de 10s
                                lastAccidentTriggerTime = now
                                onAccidentDetected(magnitude)
                            }
                        }
                    }

                    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
                }
                sensorManager?.registerListener(
                    sensorEventListener,
                    accelerometer,
                    SensorManager.SENSOR_DELAY_UI
                )
            }
        } catch (_: Exception) {}
    }

    private fun unregisterSensorListener() {
        try {
            sensorEventListener?.let {
                sensorManager?.unregisterListener(it)
            }
        } catch (_: Exception) {}
        sensorEventListener = null
        sensorManager = null
    }

    private fun onTriplePowerPressDetected() {
        // 1. Despacho INMEDIATO a la app viva (latencia 0ms)
        try {
            MainActivity.instance?.triggerPanicFromNative("power_button_3x", "ROBO")
        } catch (_: Exception) {}

        // 2. Despertar pantalla con WakeLock inmediatamente
        try {
            val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
            val wakeLock = powerManager?.newWakeLock(
                PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP,
                "AlertaCiudadana:PanicWakeLock"
            )
            wakeLock?.acquire(10000L)
        } catch (_: Exception) {}

        // 3. Crear Intent directo y lanzar actividad inmediatamente al frente
        val fullScreenIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(MainActivity.EXTRA_TRIGGER_EMERGENCY, true)
            putExtra("source", "power_button_3x")
            putExtra("alert_type", "ROBO")
        }
        val fullScreenPendingIntent = PendingIntent.getActivity(
            this,
            999,
            fullScreenIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        try {
            startActivity(fullScreenIntent)
        } catch (_: Exception) {}

        // 4. Vibración táctil de confirmación en el bolsillo
        try {
            val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator?.vibrate(VibrationEffect.createWaveform(longArrayOf(0, 300, 100, 300), -1))
            } else {
                @Suppress("DEPRECATION")
                vibrator?.vibrate(longArrayOf(0, 300, 100, 300), -1)
            }
        } catch (_: Exception) {}

        // 5. Notificación de emergencia emergente (Full-Screen Intent / Heads-Up)
        val smallIcon = applicationInfo.icon.takeIf { it != 0 } ?: android.R.drawable.ic_lock_idle_alarm
        val alarmNotification = NotificationCompat.Builder(this, EMERGENCY_ALARM_CHANNEL_ID)
            .setSmallIcon(smallIcon)
            .setContentTitle("🚨 ¡ALERTA DE ROBO ACTIVADA! (5 seg)")
            .setContentText("Toca de inmediato para abrir y cancelar con tu PIN secreto")
            .setStyle(NotificationCompat.BigTextStyle().bigText("Se detectaron 3 pulsaciones del botón de encendido.\nSi fue accidental, toca aquí de inmediato o presiona CANCELAR para ingresar tu PIN."))
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setFullScreenIntent(fullScreenPendingIntent, true)
            .setOngoing(false)
            .setAutoCancel(true)
            .setContentIntent(fullScreenPendingIntent)
            .addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                "❌ CANCELAR CON PIN",
                fullScreenPendingIntent
            )
            .build()

        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
        notificationManager?.notify(PANIC_NOTIFICATION_ID, alarmNotification)
    }

    private fun onAccidentDetected(magnitude: Float) {
        // 1. Despacho INMEDIATO a la app viva
        try {
            MainActivity.instance?.triggerPanicFromNative("sensor_impacto", "ACCIDENTE")
        } catch (_: Exception) {}

        // 2. Despertar pantalla con WakeLock inmediatamente
        try {
            val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
            val wakeLock = powerManager?.newWakeLock(
                PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP,
                "AlertaCiudadana:AccidentWakeLock"
            )
            wakeLock?.acquire(10000L)
        } catch (_: Exception) {}

        // 3. Crear Intent directo y lanzar actividad al frente
        val fullScreenIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(MainActivity.EXTRA_TRIGGER_EMERGENCY, true)
            putExtra("source", "sensor_impacto")
            putExtra("alert_type", "ACCIDENTE")
        }
        val fullScreenPendingIntent = PendingIntent.getActivity(
            this,
            998,
            fullScreenIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        try {
            startActivity(fullScreenIntent)
        } catch (_: Exception) {}

        // 4. Vibración de advertencia
        try {
            val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator?.vibrate(VibrationEffect.createWaveform(longArrayOf(0, 500, 200, 500), -1))
            } else {
                @Suppress("DEPRECATION")
                vibrator?.vibrate(longArrayOf(0, 500, 200, 500), -1)
            }
        } catch (_: Exception) {}

        // 5. Notificación emergente (Full-Screen Intent / Heads-Up)
        val smallIcon = applicationInfo.icon.takeIf { it != 0 } ?: android.R.drawable.ic_lock_idle_alarm
        val alarmNotification = NotificationCompat.Builder(this, EMERGENCY_ALARM_CHANNEL_ID)
            .setSmallIcon(smallIcon)
            .setContentTitle("🚗 ¡POSIBLE ACCIDENTE / IMPACTO DETECTADO!")
            .setContentText("Cuenta regresiva iniciada. Toca para cancelar si estás bien.")
            .setStyle(NotificationCompat.BigTextStyle().bigText("Se detectó un impacto fuerte (${String.format("%.1f", magnitude)} m/s²).\nSi estás bien, toca aquí para cancelar con tu PIN antes de que se alerte a las autoridades y familiares."))
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setFullScreenIntent(fullScreenPendingIntent, true)
            .setOngoing(false)
            .setAutoCancel(true)
            .setContentIntent(fullScreenPendingIntent)
            .addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                "❌ ESTOY BIEN (CANCELAR)",
                fullScreenPendingIntent
            )
            .build()

        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
        notificationManager?.notify(PANIC_NOTIFICATION_ID, alarmNotification)
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        val restartServiceIntent = Intent(applicationContext, EmergencyForegroundService::class.java).apply {
            setPackage(packageName)
        }
        val restartPendingIntent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            PendingIntent.getForegroundService(
                applicationContext,
                101,
                restartServiceIntent,
                PendingIntent.FLAG_ONE_SHOT or PendingIntent.FLAG_IMMUTABLE
            )
        } else {
            PendingIntent.getService(
                applicationContext,
                101,
                restartServiceIntent,
                PendingIntent.FLAG_ONE_SHOT or PendingIntent.FLAG_IMMUTABLE
            )
        }
        val alarmManager = getSystemService(Context.ALARM_SERVICE) as? AlarmManager
        alarmManager?.set(
            AlarmManager.ELAPSED_REALTIME,
            SystemClock.elapsedRealtime() + 1000,
            restartPendingIntent
        )
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        isServiceRunning = false
        screenReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (_: Exception) {}
        }
        screenReceiver = null
        unregisterSensorListener()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
