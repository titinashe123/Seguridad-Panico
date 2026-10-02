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
import android.location.Location
import android.location.LocationManager
import android.os.Build
import android.os.CountDownTimer
import android.os.IBinder
import android.os.PowerManager
import android.os.SystemClock
import android.os.VibrationEffect
import android.os.Vibrator
import androidx.core.app.NotificationCompat
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

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

        var activeCountdownTimer: CountDownTimer? = null
        var isEmergencyActive: Boolean = false
        var currentEmergencySource: String = "power_button_3x"
        var currentEmergencyAlertType: String = "ROBO"
        var emergencyTriggerTimestamp: Long = 0
        var isEmergencyDispatched: Boolean = false

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

        fun cancelEmergency(context: Context) {
            activeCountdownTimer?.cancel()
            activeCountdownTimer = null
            isEmergencyActive = false
            isEmergencyDispatched = false

            try {
                val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                prefs.edit()
                    .putBoolean("flutter.pending_emergency_active", false)
                    .putBoolean("flutter.pending_emergency_dispatched", false)
                    .apply()
            } catch (_: Exception) {}

            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            notificationManager?.cancel(PANIC_NOTIFICATION_ID)
        }

        fun stopService(context: Context) {
            cancelEmergency(context)
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
        startEmergencyFlow("power_button_3x", "ROBO", "Se detectaron 3 pulsaciones del botón de encendido")
    }

    private fun onAccidentDetected(magnitude: Float) {
        startEmergencyFlow("sensor_impacto", "ACCIDENTE", "Impacto fuerte detectado: ${String.format(Locale.US, "%.1f", magnitude)} m/s²")
    }

    private fun startEmergencyFlow(source: String, alertType: String, detailInfo: String) {
        isEmergencyActive = true
        currentEmergencySource = source
        currentEmergencyAlertType = alertType
        emergencyTriggerTimestamp = System.currentTimeMillis()
        isEmergencyDispatched = false

        // Guardar estado en SharedPreferences
        try {
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            prefs.edit()
                .putBoolean("flutter.pending_emergency_active", true)
                .putString("flutter.pending_emergency_source", source)
                .putString("flutter.pending_emergency_alert_type", alertType)
                .putLong("flutter.pending_emergency_time", emergencyTriggerTimestamp)
                .putBoolean("flutter.pending_emergency_dispatched", false)
                .apply()
        } catch (_: Exception) {}

        // 1. Despacho INMEDIATO a la app viva (si ya está abierta)
        try {
            MainActivity.instance?.triggerPanicFromNative(source, alertType)
        } catch (_: Exception) {}

        // 2. Despertar pantalla con WakeLock inmediatamente
        try {
            val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
            val wakeLock = powerManager?.newWakeLock(
                PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP,
                "AlertaCiudadana:PanicWakeLock"
            )
            wakeLock?.acquire(15000L)
        } catch (_: Exception) {}

        // 3. Crear Intent directo y lanzar actividad inmediatamente al frente
        val fullScreenIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(MainActivity.EXTRA_TRIGGER_EMERGENCY, true)
            putExtra("source", source)
            putExtra("alert_type", alertType)
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
                vibrator?.vibrate(VibrationEffect.createWaveform(longArrayOf(0, 300, 150, 300, 150, 400), -1))
            } else {
                @Suppress("DEPRECATION")
                vibrator?.vibrate(longArrayOf(0, 300, 150, 300, 150, 400), -1)
            }
        } catch (_: Exception) {}

        // 5. Iniciar la notificación con cuenta regresiva
        updateEmergencyNotificationCountdown(5, alertType, fullScreenPendingIntent)

        // 6. Iniciar temporizador nativo de 5 segundos
        activeCountdownTimer?.cancel()
        activeCountdownTimer = object : CountDownTimer(5000, 1000) {
            override fun onTick(millisUntilFinished: Long) {
                val seconds = (millisUntilFinished / 1000) + 1
                if (isEmergencyActive && !isEmergencyDispatched) {
                    updateEmergencyNotificationCountdown(seconds, alertType, fullScreenPendingIntent)
                }
            }

            override fun onFinish() {
                if (isEmergencyActive && !isEmergencyDispatched) {
                    isEmergencyDispatched = true
                    dispatchEmergencyAlertFromService(source, alertType)
                }
            }
        }.start()
    }

    private fun updateEmergencyNotificationCountdown(secondsLeft: Long, alertType: String, fullScreenPendingIntent: PendingIntent) {
        val smallIcon = applicationInfo.icon.takeIf { it != 0 } ?: android.R.drawable.ic_lock_idle_alarm
        val title = if (alertType == "ACCIDENTE") {
            "🚗 ¡ACCIDENTE DETECTADO! ($secondsLeft seg)"
        } else {
            "🚨 ¡ALERTA DE ROBO ACTIVADA! ($secondsLeft seg)"
        }
        val text = "Despachando alerta en $secondsLeft segundos. Toca para ingresar PIN y cancelar."

        val alarmNotification = NotificationCompat.Builder(this, EMERGENCY_ALARM_CHANNEL_ID)
            .setSmallIcon(smallIcon)
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText("$text\nSi fue una falsa alarma, ingresa tu PIN."))
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

    private fun dispatchEmergencyAlertFromService(source: String, alertType: String) {
        Thread {
            try {
                // 1. Obtener última ubicación GPS
                val locationManager = getSystemService(Context.LOCATION_SERVICE) as? LocationManager
                var bestLocation: Location? = null
                try {
                    val gpsLoc = locationManager?.getLastKnownLocation(LocationManager.GPS_PROVIDER)
                    val netLoc = locationManager?.getLastKnownLocation(LocationManager.NETWORK_PROVIDER)
                    bestLocation = when {
                        gpsLoc != null && netLoc != null -> if (gpsLoc.time > netLoc.time) gpsLoc else netLoc
                        gpsLoc != null -> gpsLoc
                        else -> netLoc
                    }
                } catch (_: Exception) {}

                val lat = bestLocation?.latitude ?: -13.71450
                val lon = bestLocation?.longitude ?: -76.20320

                // 2. Leer datos del ciudadano desde SharedPreferences
                val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                val citizenDni = prefs.getString("flutter.app_session_user_dni", "74629337") ?: "74629337"
                val idPersona = prefs.getInt("flutter.app_session_user_id_persona", 3)

                val headline = if (alertType == "ACCIDENTE") {
                    "🚗💥 ¡ACCIDENTE DE TRÁNSITO! AMBULANCIA Y POLICÍA REQUERIDA 🚗💥"
                } else {
                    "🚨 ¡AUXILIO! ME ESTÁN ROBANDO 🚨"
                }
                val triggerLabel = if (source == "power_button_3x") {
                    "BOTÓN DE ENCENDIDO (3X) [MODO BOLSILLO / APP CERRADA]"
                } else {
                    "SENSOR DE IMPACTO / ACCIDENTE [APP CERRADA]"
                }
                val gmapsUrl = "https://maps.google.com/?q=${String.format(Locale.US, "%.5f,%.5f", lat, lon)}"
                val gmapsNav = "https://www.google.com/maps/dir/?api=1&destination=${String.format(Locale.US, "%.5f,%.5f", lat, lon)}"

                val message = "$headline\n" +
                        "📍 Ubicación: Ubicación móvil GPS (Pisco)\n" +
                        "🛰️ Coordenadas: Lat ${String.format(Locale.US, "%.5f", lat)}, Lon ${String.format(Locale.US, "%.5f", lon)}\n" +
                        "🗺️ Mapa: $gmapsUrl\n" +
                        "🚗 Cómo llegar: $gmapsNav\n" +
                        "⚡ Disparador: $triggerLabel\n" +
                        "🛡️ Despacho automático WhatsApp API a la Central de Video Vigilancia."

                // 3. Despachar mensaje a WhatsApp vía Green-API
                try {
                    val waUrl = URL("https://7105.api.greenapi.com/waInstance710522731795/sendMessage/1d98a458d1a64672abcff255236d807432183678856b42cfba")
                    val conn = waUrl.openConnection() as HttpURLConnection
                    conn.requestMethod = "POST"
                    conn.setRequestProperty("Content-Type", "application/json")
                    conn.doOutput = true
                    val jsonBody = JSONObject().apply {
                        put("chatId", "51976264949@c.us")
                        put("message", message)
                    }
                    val os = conn.outputStream
                    os.write(jsonBody.toString().toByteArray(Charsets.UTF_8))
                    os.flush()
                    os.close()
                    val code = conn.responseCode
                    conn.disconnect()
                } catch (_: Exception) {}

                // 4. Registrar reporte en Supabase
                try {
                    val df = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
                        timeZone = TimeZone.getTimeZone("UTC")
                    }
                    val nowUtcIso = df.format(Date())

                    val supabaseUrl = URL("https://emtzprcntefzkvvzmhfk.supabase.co/rest/v1/reporte")
                    val sConn = supabaseUrl.openConnection() as HttpURLConnection
                    sConn.requestMethod = "POST"
                    sConn.setRequestProperty("Content-Type", "application/json")
                    sConn.setRequestProperty("apikey", "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVtdHpwcmNudGVmemt2dnptaGZrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTA3ODIxNzIsImV4cCI6MjEwNjM1ODE3Mn0.x18Bh68n4ZgtNOyVPwIc01V6aL50oUaXjeXELzlWEh4")
                    sConn.setRequestProperty("Authorization", "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVtdHpwcmNudGVmemt2dnptaGZrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTA3ODIxNzIsImV4cCI6MjEwNjM1ODE3Mn0.x18Bh68n4ZgtNOyVPwIc01V6aL50oUaXjeXELzlWEh4")
                    sConn.setRequestProperty("Prefer", "return=representation")
                    sConn.doOutput = true

                    val sBody = JSONObject().apply {
                        put("id_persona", idPersona)
                        put("id_tipo", if (alertType == "ACCIDENTE") 4 else 1)
                        put("id_estado", 1)
                        put("fecha_hora", nowUtcIso)
                        put("descripcion", message)
                        put("direccion_texto", "Ubicación móvil GPS (Pisco)")
                    }
                    val sOs = sConn.outputStream
                    sOs.write(sBody.toString().toByteArray(Charsets.UTF_8))
                    sOs.flush()
                    sOs.close()
                    val sCode = sConn.responseCode
                    sConn.disconnect()
                } catch (_: Exception) {}

                // 5. Guardar estado de despacho en SharedPreferences para que Flutter lo detecte al abrir
                prefs.edit()
                    .putBoolean("flutter.pending_emergency_dispatched", true)
                    .putBoolean("flutter.pending_emergency_active", false)
                    .putString("flutter.last_dispatched_alert_type", alertType)
                    .putString("flutter.last_dispatched_source", source)
                    .putLong("flutter.last_dispatched_time", System.currentTimeMillis())
                    .apply()

                // 6. Activar rastreo en vivo si es ROBO
                if (alertType == "ROBO") {
                    isLiveTrackingActive = true
                    val notif = buildCurrentNotification()
                    val manager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
                    manager?.notify(NOTIFICATION_ID, notif)
                }

                // 7. Vibración de confirmación
                val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    vibrator?.vibrate(VibrationEffect.createOneShot(500, VibrationEffect.DEFAULT_AMPLITUDE))
                } else {
                    @Suppress("DEPRECATION")
                    vibrator?.vibrate(500)
                }

                // 8. Actualizar notificación permanente de alarma a despachado
                showDispatchedNotification(alertType)

                // 9. Si MainActivity está abierta o se abre, informarle
                MainActivity.instance?.runOnUiThread {
                    MainActivity.instance?.onEmergencyDispatchedFromNative(alertType, source)
                }
            } catch (_: Exception) {}
        }.start()
    }

    private fun showDispatchedNotification(alertType: String) {
        val appIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val appPendingIntent = PendingIntent.getActivity(
            this,
            1005,
            appIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val smallIcon = applicationInfo.icon.takeIf { it != 0 } ?: android.R.drawable.ic_lock_idle_alarm
        val notification = NotificationCompat.Builder(this, EMERGENCY_ALARM_CHANNEL_ID)
            .setSmallIcon(smallIcon)
            .setContentTitle("✅ ALERTA DE $alertType ENVIADA A LA CENTRAL")
            .setContentText("Ubicación GPS transmitida con éxito. Toca para ver en la app.")
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setContentIntent(appPendingIntent)
            .setAutoCancel(true)
            .build()

        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
        notificationManager?.notify(PANIC_NOTIFICATION_ID, notification)
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
