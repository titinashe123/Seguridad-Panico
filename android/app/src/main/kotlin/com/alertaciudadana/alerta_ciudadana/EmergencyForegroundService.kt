package com.alertaciudadana.alerta_ciudadana

import android.app.AlarmManager
import android.app.KeyguardManager
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

    private var lastScreenAction: String? = null
    private var lastScreenActionTime: Long = 0
    private val powerPressTimestamps = ArrayList<Long>()
    private var screenReceiver: BroadcastReceiver? = null
    private var isLiveTrackingActive: Boolean = false

    private var sensorManager: SensorManager? = null
    private var linearAccelerometer: Sensor? = null
    private var rawAccelerometer: Sensor? = null
    private var gyroscope: Sensor? = null
    private var sensorEventListener: SensorEventListener? = null
    private var lastTheftTriggerTime: Long = 0
    private var lastButtonTriggerTime: Long = 0

    // Verificación de Fuga en 2 Fases (Estándar Google Theft Detection & Descarte de Reposo/Cama)
    private var isVerifyingTheftEscape: Boolean = false
    private var candidateSnatchTime: Long = 0
    private var candidateSnatchSource: String = ""
    private var candidateSnatchDetail: String = ""
    private var tailMotionSamples: Int = 0
    private var tailStillSamples: Int = 0
    private var lastActiveMotionTimestamp: Long = 0
    private var candidateStartLocation: Location? = null
    private var escapeVerificationHandler: android.os.Handler? = null
    private var lastCurrentLinearMag: Float = 0f
    private var lastCurrentGyroMag: Float = 0f

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

        fun isUserLoggedIn(context: Context): Boolean {
            return try {
                val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                prefs.getBoolean("flutter.app_session_is_logged_in", false)
            } catch (_: Exception) {
                false
            }
        }

        fun startService(context: Context) {
            if (!isUserLoggedIn(context)) return
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
                    .putBoolean("flutter.native_dispatched_success", false)
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
        if (!isUserLoggedIn(this)) {
            stopSelf()
            return
        }
        isServiceRunning = true
        createNotificationChannels()
        registerScreenReceiver()
        registerSensorListener()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (!isUserLoggedIn(this)) {
            stopForeground(true)
            stopSelf()
            return START_NOT_STICKY
        }

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
                // Si el usuario no ha iniciado sesión, ignorar completamente cualquier pulsación
                if (!isUserLoggedIn(this@EmergencyForegroundService)) {
                    powerPressTimestamps.clear()
                    lastScreenAction = null
                    return
                }

                // Si ya está activa la emergencia o en cuenta regresiva, NO reiniciar ni alterar
                if (isEmergencyActive) {
                    return
                }

                val action = intent?.action ?: return
                val now = System.currentTimeMillis()

                // 1. Descartar eventos duplicados de la misma acción
                // (evita que Always On Display, ambient display o rebotes del sistema sumen pulsaciones falsas)
                if (action == lastScreenAction) {
                    return
                }

                // 2. Debounce optimizado de 40ms (anteriormente 100ms descartaba clics rápidos sucesivos)
                if (now - lastScreenActionTime < 40) {
                    return
                }

                lastScreenAction = action
                lastScreenActionTime = now

                // 3. Ventana deslizante de 3500ms para admitir pulsaciones rápidas con margen para la respuesta de pantalla
                powerPressTimestamps.removeAll { now - it > 3500 }
                powerPressTimestamps.add(now)

                // 4. Disparo inmediato al completar 3 pulsaciones consecutivas
                if (powerPressTimestamps.size >= 3) {
                    powerPressTimestamps.clear()
                    lastScreenAction = null
                    lastButtonTriggerTime = now
                    android.util.Log.i("EmergencyService", "⚡ DISPARO INSTANTÁNEO BOTÓN DE ENCENDIDO (3X)")
                    onTriplePowerPressDetected()
                }
            }
        }

        registerReceiver(screenReceiver, filter)
    }

    private fun registerSensorListener() {
        if (!isUserLoggedIn(this)) return
        if (sensorManager != null) return
        try {
            sensorManager = getSystemService(Context.SENSOR_SERVICE) as? SensorManager
            // Sensor lineal (excluye gravedad estática de 9.8 m/s²), idéntico al estándar de Theft Detection Lock
            linearAccelerometer = sensorManager?.getDefaultSensor(Sensor.TYPE_LINEAR_ACCELERATION)
            if (linearAccelerometer == null) {
                rawAccelerometer = sensorManager?.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
            }
            gyroscope = sensorManager?.getDefaultSensor(Sensor.TYPE_GYROSCOPE)

            sensorEventListener = object : SensorEventListener {
                override fun onSensorChanged(event: SensorEvent?) {
                    if (event == null) return
                    if (!isUserLoggedIn(this@EmergencyForegroundService)) return
                    val now = System.currentTimeMillis()

                    // Debounce de 8 segundos y no re-disparar si ya hay una emergencia activa
                    if (isEmergencyActive || (now - lastTheftTriggerTime <= 8000)) {
                        return
                    }

                    val x = event.values[0]
                    val y = event.values[1]
                    val z = event.values[2]
                    val magnitude = Math.sqrt((x * x + y * y + z * z).toDouble()).toFloat()

                    // Actualizar memoria sensorial continua para fusión de sensores
                    when (event.sensor.type) {
                        Sensor.TYPE_LINEAR_ACCELERATION -> lastCurrentLinearMag = magnitude
                        Sensor.TYPE_ACCELEROMETER -> lastCurrentLinearMag = Math.abs(magnitude - 9.8f)
                        Sensor.TYPE_GYROSCOPE -> lastCurrentGyroMag = magnitude
                    }

                    // FASE 2: Si estamos dentro de la ventana de verificación de fuga (2200 ms posteriores al jalón)
                    if (isVerifyingTheftEscape) {
                        val isMotionActive = when (event.sensor.type) {
                            Sensor.TYPE_LINEAR_ACCELERATION -> magnitude > 2.8f
                            Sensor.TYPE_ACCELEROMETER -> Math.abs(magnitude - 9.8f) > 2.8f
                            Sensor.TYPE_GYROSCOPE -> magnitude > 1.2f
                            else -> false
                        }

                        val elapsedSinceSnatch = now - candidateSnatchTime
                        val isTailWindow = elapsedSinceSnatch >= 900L

                        if (isMotionActive) {
                            lastActiveMotionTimestamp = now
                            if (isTailWindow) {
                                tailMotionSamples++
                            }
                        } else {
                            val isStill = when (event.sensor.type) {
                                Sensor.TYPE_LINEAR_ACCELERATION -> magnitude < 1.2f
                                Sensor.TYPE_ACCELEROMETER -> Math.abs(magnitude - 9.8f) < 1.2f
                                Sensor.TYPE_GYROSCOPE -> magnitude < 0.5f
                                else -> false
                            }
                            if (isStill && isTailWindow) {
                                tailStillSamples++
                            }
                        }
                        return
                    }

                    // FASE 1: Detección del Jalón de Arrebato Inicial (Candidate Snatch)
                    var isCandidate = false
                    var sourceCandidate = ""
                    var detailCandidate = ""

                    when (event.sensor.type) {
                        Sensor.TYPE_LINEAR_ACCELERATION -> {
                            if (magnitude >= 30.0f) {
                                isCandidate = true
                                sourceCandidate = "sensor_antirrobo_acelerometro"
                                detailCandidate = "Arrebato violento detectado (Aceleración lineal: ${String.format(Locale.US, "%.1f", magnitude)} m/s²)"
                            } else if (magnitude >= 22.0f && lastCurrentGyroMag >= 12.0f) {
                                isCandidate = true
                                sourceCandidate = "sensor_antirrobo_fusion"
                                detailCandidate = "Arrebato con forcejeo detectado (Aceleración: ${String.format(Locale.US, "%.1f", magnitude)} m/s², Giro: ${String.format(Locale.US, "%.1f", lastCurrentGyroMag)} rad/s)"
                            }
                        }
                        Sensor.TYPE_ACCELEROMETER -> {
                            if (magnitude >= 45.0f) {
                                isCandidate = true
                                sourceCandidate = "sensor_antirrobo_acelerometro"
                                detailCandidate = "Arrebato violento detectado (Aceleración total: ${String.format(Locale.US, "%.1f", magnitude)} m/s²)"
                            } else if (magnitude >= 35.0f && lastCurrentGyroMag >= 12.0f) {
                                isCandidate = true
                                sourceCandidate = "sensor_antirrobo_fusion"
                                detailCandidate = "Arrebato con forcejeo detectado (Aceleración: ${String.format(Locale.US, "%.1f", magnitude)} m/s², Giro: ${String.format(Locale.US, "%.1f", lastCurrentGyroMag)} rad/s)"
                            }
                        }
                        Sensor.TYPE_GYROSCOPE -> {
                            if (magnitude >= 18.0f && lastCurrentLinearMag >= 15.0f) {
                                isCandidate = true
                                sourceCandidate = "sensor_antirrobo_giroscopio"
                                detailCandidate = "Forcejeo violento de arrebato detectado (Rotación: ${String.format(Locale.US, "%.1f", magnitude)} rad/s)"
                            } else if (magnitude >= 14.0f && lastCurrentLinearMag >= 20.0f) {
                                isCandidate = true
                                sourceCandidate = "sensor_antirrobo_fusion"
                                detailCandidate = "Forcejeo con jalón detectado (Rotación: ${String.format(Locale.US, "%.1f", magnitude)} rad/s, Aceleración: ${String.format(Locale.US, "%.1f", lastCurrentLinearMag)} m/s²)"
                            }
                        }
                    }

                    if (isCandidate) {
                        // Iniciar Fase 2: Ventana de Verificación de Fuga (2200 ms)
                        // Permite corroborar si tras el jalón hay huida (carrera/moto) o si el celular quedó en reposo (cama/mesa)
                        isVerifyingTheftEscape = true
                        candidateSnatchTime = now
                        candidateSnatchSource = sourceCandidate
                        candidateSnatchDetail = detailCandidate
                        tailMotionSamples = 0
                        tailStillSamples = 0
                        lastActiveMotionTimestamp = now

                        // Capturar ubicación GPS inicial
                        val locationManager = getSystemService(Context.LOCATION_SERVICE) as? LocationManager
                        candidateStartLocation = try {
                            val gps = locationManager?.getLastKnownLocation(LocationManager.GPS_PROVIDER)
                            val net = locationManager?.getLastKnownLocation(LocationManager.NETWORK_PROVIDER)
                            when {
                                gps != null && net != null -> if (gps.time > net.time) gps else net
                                gps != null -> gps
                                else -> net
                            }
                        } catch (_: Exception) { null }

                        escapeVerificationHandler?.removeCallbacksAndMessages(null)
                        escapeVerificationHandler = android.os.Handler(android.os.Looper.getMainLooper())
                        escapeVerificationHandler?.postDelayed({
                            evaluatePostSnatchEscape()
                        }, 2200L)
                    }
                }

                override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
            }

            linearAccelerometer?.let {
                sensorManager?.registerListener(sensorEventListener, it, SensorManager.SENSOR_DELAY_UI)
            }
            rawAccelerometer?.let {
                sensorManager?.registerListener(sensorEventListener, it, SensorManager.SENSOR_DELAY_UI)
            }
            gyroscope?.let {
                sensorManager?.registerListener(sensorEventListener, it, SensorManager.SENSOR_DELAY_UI)
            }
        } catch (_: Exception) {}
    }

    private fun evaluatePostSnatchEscape() {
        if (!isVerifyingTheftEscape) return
        isVerifyingTheftEscape = false

        if (!isUserLoggedIn(this) || isEmergencyActive) return

        val now = System.currentTimeMillis()
        val timeSinceLastMotion = now - lastActiveMotionTimestamp

        // Consultar ubicación GPS actual tras los 2.2 segundos
        val locationManager = getSystemService(Context.LOCATION_SERVICE) as? LocationManager
        var endLocation: Location? = null
        try {
            val gps = locationManager?.getLastKnownLocation(LocationManager.GPS_PROVIDER)
            val net = locationManager?.getLastKnownLocation(LocationManager.NETWORK_PROVIDER)
            endLocation = when {
                gps != null && net != null -> if (gps.time > net.time) gps else net
                gps != null -> gps
                else -> net
            }
        } catch (_: Exception) {}

        val distanceMoved = if (candidateStartLocation != null && endLocation != null) {
            candidateStartLocation!!.distanceTo(endLocation)
        } else {
            0f
        }
        val currentSpeed = endLocation?.speed ?: 0f // metros por segundo

        android.util.Log.d(
            "TheftDetector",
            "Evaluación Fase 2: tiempoSinMov=${timeSinceLastMotion}ms, colaMov=$tailMotionSamples, colaQuieto=$tailStillSamples, dist=${distanceMoved}m, vel=${currentSpeed}m/s"
        )

        // FASE 2: VERIFICACIÓN ESTRICTA DE FUGA (ESTÁNDAR THEFT DETECTION DE GOOGLE)
        // Para confirmar robo se EXIGE que el delincuente esté en fuga real.
        // Un celular arrojado a la cama/mesa queda en reposo sin movimiento sostenido tras el impacto inicial.
        
        // CONDICIÓN A: Fuga en vehículo / motocicleta / bicicleta o alta velocidad GPS
        val hasGpsTransit = (currentSpeed >= 2.2f && distanceMoved >= 5.0f) || (distanceMoved >= 8.0f)

        // CONDICIÓN B: Fuga a pie (carrera con pasos activos ininterrumpidos hasta el final de la ventana)
        // 1. Debe haber movimiento activo en el presente instante (última muestra hace menos de 350 ms)
        // 2. En la segunda mitad de la ventana (cola > 900ms), debe haber al menos 6 muestras de movimiento sostenido
        // 3. El movimiento activo debe superar al reposo
        val hasPedestrianTransit = (timeSinceLastMotion < 350L) &&
                                   (tailMotionSamples >= 6) &&
                                   (tailMotionSamples > tailStillSamples)

        val isConfirmedEscape = hasGpsTransit || hasPedestrianTransit

        if (isConfirmedEscape) {
            lastTheftTriggerTime = now
            val escapeDescription = if (hasGpsTransit) {
                "Fuga en vehículo/moto (${String.format(Locale.US, "%.1f", currentSpeed)} m/s, ${String.format(Locale.US, "%.1f", distanceMoved)} m)"
            } else {
                "Fuga a pie continua confirmada"
            }
            onTheftSnatchDetected(
                candidateSnatchSource,
                "$candidateSnatchDetail ($escapeDescription)"
            )
        } else {
            android.util.Log.i("TheftDetector", "🛑 FALSO POSITIVO DESCARTADO: Fase 2 no cumplida (reposo en cama/mesa o sin escape continuo).")
        }
    }

    private fun unregisterSensorListener() {
        try {
            escapeVerificationHandler?.removeCallbacksAndMessages(null)
            escapeVerificationHandler = null
            isVerifyingTheftEscape = false
            sensorEventListener?.let {
                sensorManager?.unregisterListener(it)
            }
        } catch (_: Exception) {}
        sensorEventListener = null
        sensorManager = null
        linearAccelerometer = null
        rawAccelerometer = null
        gyroscope = null
    }

    private fun onTriplePowerPressDetected() {
        if (!isUserLoggedIn(this)) return
        if (isEmergencyActive) return
        startEmergencyFlow("power_button_3x", "ROBO", "Se detectaron 3 pulsaciones rápidas del botón de encendido")
    }

    private fun onTheftSnatchDetected(source: String, detailInfo: String) {
        if (!isUserLoggedIn(this)) return
        if (isEmergencyActive) return
        startEmergencyFlow(source, "ROBO", detailInfo)
    }

    private fun startEmergencyFlow(source: String, alertType: String, detailInfo: String) {
        if (!isUserLoggedIn(this)) {
            return
        }

        // Si ya hay una emergencia en curso y no ha sido cancelada, ignorar disparos adicionales de pánico
        if (isEmergencyActive && !isEmergencyDispatched) {
            return
        }

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

        val keyguardManager = getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
        val isDeviceLocked = keyguardManager?.isKeyguardLocked ?: false

        // 1. Crear Intent para la actividad
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

        // 2. Si el dispositivo NO está bloqueado, interactuar con la app viva
        if (!isDeviceLocked) {
            try {
                MainActivity.instance?.triggerPanicFromNative(source, alertType)
            } catch (_: Exception) {}

            try {
                val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
                val wakeLock = powerManager?.newWakeLock(
                    PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP,
                    "AlertaCiudadana:PanicWakeLock"
                )
                wakeLock?.acquire(15000L)
            } catch (_: Exception) {}

            try {
                startActivity(fullScreenIntent)
            } catch (_: Exception) {}
        }

        // 3. Vibración táctil de confirmación en el bolsillo
        try {
            val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator?.vibrate(VibrationEffect.createWaveform(longArrayOf(0, 300, 150, 300, 150, 400), -1))
            } else {
                @Suppress("DEPRECATION")
                vibrator?.vibrate(longArrayOf(0, 300, 150, 300, 150, 400), -1)
            }
        } catch (_: Exception) {}

        // 4. Iniciar la notificación con cuenta regresiva (5 segundos)
        updateEmergencyNotificationCountdown(5, alertType, fullScreenPendingIntent)

        // 5. Iniciar temporizador nativo de 5 segundos
        activeCountdownTimer?.cancel()
        activeCountdownTimer = object : CountDownTimer(5000, 1000) {
            override fun onTick(millisUntilFinished: Long) {
                val seconds = (millisUntilFinished / 1000) + 1
                if (isEmergencyActive && !isEmergencyDispatched) {
                    updateEmergencyNotificationCountdown(seconds, alertType, fullScreenPendingIntent)
                }
            }

            override fun onFinish() {
                val shouldDispatch = isEmergencyActive && !isEmergencyDispatched
                isEmergencyActive = false
                activeCountdownTimer = null
                if (shouldDispatch) {
                    dispatchEmergencyAlertFromService(source, alertType)
                }
            }
        }.start()
    }

    private fun updateEmergencyNotificationCountdown(secondsLeft: Long, alertType: String, fullScreenPendingIntent: PendingIntent) {
        val keyguardManager = getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
        val isDeviceLocked = keyguardManager?.isKeyguardLocked ?: false

        val smallIcon = applicationInfo.icon.takeIf { it != 0 } ?: android.R.drawable.ic_lock_idle_alarm
        val title = if (alertType == "ACCIDENTE") {
            "🚗 ¡ACCIDENTE DETECTADO! ($secondsLeft seg)"
        } else {
            "🚨 ¡ALERTA DE ROBO ACTIVADA! ($secondsLeft seg)"
        }
        val text = "Despachando alerta en $secondsLeft segundos. Toca para ingresar PIN y cancelar."

        val builder = NotificationCompat.Builder(this, EMERGENCY_ALARM_CHANNEL_ID)
            .setSmallIcon(smallIcon)
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText("$text\nSi fue una falsa alarma, ingresa tu PIN."))
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setOngoing(false)
            .setAutoCancel(true)
            .setContentIntent(fullScreenPendingIntent)
            .addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                "❌ CANCELAR CON PIN",
                fullScreenPendingIntent
            )

        if (isDeviceLocked) {
            // Modo Sigiloso: en la pantalla de bloqueo NO se expone la alerta ni se lanza la pantalla completa
            builder.setVisibility(NotificationCompat.VISIBILITY_SECRET)
        } else {
            builder.setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            builder.setFullScreenIntent(fullScreenPendingIntent, true)
        }

        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
        notificationManager?.notify(PANIC_NOTIFICATION_ID, builder.build())
    }

    private fun dispatchEmergencyAlertFromService(source: String, alertType: String) {
        if (!isUserLoggedIn(this)) return
        Thread {
            var nativeSuccess = false
            var createdReportId: Long? = null
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

                // 2. Leer datos del ciudadano desde SharedPreferences de forma completamente segura (sin ClassCastException)
                val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                val citizenDni = prefs.getString("flutter.app_session_user_dni", null) ?: "74629337"
                val idPersona: Int = try {
                    val raw = prefs.all["flutter.app_session_user_id_persona"]
                    when (raw) {
                        is Number -> raw.toInt()
                        is String -> raw.toIntOrNull() ?: 3
                        else -> 3
                    }
                } catch (_: Exception) {
                    3
                }

                val headline = if (alertType == "ACCIDENTE") {
                    "🚗💥 ¡ACCIDENTE DE TRÁNSITO! AMBULANCIA Y POLICÍA REQUERIDA 🚗💥"
                } else {
                    "🚨 ¡AUXILIO! ME ESTÁN ROBANDO 🚨"
                }
                val triggerLabel = when (source) {
                    "power_button_3x" -> "BOTÓN DE ENCENDIDO (3X RÁPIDO) [MODO BOLSILLO / APP CERRADA]"
                    "sensor_antirrobo_acelerometro" -> "SENSOR ANTIRROBO (ARREBATO BRUSCO / ACELERÓMETRO)"
                    "sensor_antirrobo_giroscopio" -> "SENSOR ANTIRROBO (FORCEJEO BRUSCO / GIROSCOPIO)"
                    "sensor_antirrobo" -> "SENSOR ANTIRROBO (DETECCIÓN DE ROBO EN SEGUNDO PLANO)"
                    "physical_button_3x" -> "BOTÓN FÍSICO RÁPIDO (3X) [DESESPERACIÓN / ROBO]"
                    else -> "DETECCIÓN AUTOMÁTICA DE ROBO (FONDO)"
                }
                val latStr = String.format(Locale.US, "%.5f", lat)
                val lonStr = String.format(Locale.US, "%.5f", lon)
                val gmapsUrl = "https://maps.google.com/?q=$latStr,$lonStr"
                val gmapsNav = "🚗 Cómo llegar (Google Maps): https://www.google.com/maps/dir/?api=1&destination=$latStr,$lonStr"

                val message = "$headline\n" +
                        "📍 Ubicación: Ubicación móvil GPS (Pisco)\n" +
                        "🛰️ Coordenadas: Lat $latStr, Lon $lonStr\n" +
                        "🗺️ Mapa: $gmapsUrl\n" +
                        "$gmapsNav\n" +
                        "⚡ Disparador: $triggerLabel\n" +
                        "🛡️ Despacho automático WhatsApp API a la Central de Video Vigilancia."

                // 3. Despachar mensaje a WhatsApp vía Green-API (con timeouts explícitos y UTF-8)
                try {
                    val waUrl = URL("https://7105.api.greenapi.com/waInstance710522731795/sendMessage/1d98a458d1a64672abcff255236d807432183678856b42cfba")
                    val conn = waUrl.openConnection() as HttpURLConnection
                    conn.requestMethod = "POST"
                    conn.setRequestProperty("Content-Type", "application/json; charset=utf-8")
                    conn.connectTimeout = 10000
                    conn.readTimeout = 10000
                    conn.doOutput = true
                    val jsonBody = JSONObject().apply {
                        put("chatId", "51976264949@c.us")
                        put("message", message)
                    }
                    val bytes = jsonBody.toString().toByteArray(Charsets.UTF_8)
                    conn.setFixedLengthStreamingMode(bytes.size)
                    conn.outputStream.use { os ->
                        os.write(bytes)
                        os.flush()
                    }
                    val code = conn.responseCode
                    val resText = if (code in 200..299) {
                        conn.inputStream.bufferedReader().use { it.readText() }
                    } else {
                        conn.errorStream?.bufferedReader()?.use { it.readText() } ?: ""
                    }
                    android.util.Log.d("EmergencyForegroundService", "Green API Response ($code): $resText")
                    if (code in 200..299) {
                        nativeSuccess = true
                    }
                    conn.disconnect()
                } catch (waErr: Exception) {
                    android.util.Log.e("EmergencyForegroundService", "Green API error: ${waErr.message}", waErr)
                }

                // 4. Registrar reporte en Supabase
                val df = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
                    timeZone = TimeZone.getTimeZone("UTC")
                }
                val nowUtcIso = df.format(Date())

                try {
                    val supabaseUrl = URL("https://emtzprcntefzkvvzmhfk.supabase.co/rest/v1/reporte")
                    val sConn = supabaseUrl.openConnection() as HttpURLConnection
                    sConn.requestMethod = "POST"
                    sConn.setRequestProperty("Content-Type", "application/json; charset=utf-8")
                    sConn.setRequestProperty("apikey", "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVtdHpwcmNudGVmemt2dnptaGZrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTA3ODIxNzIsImV4cCI6MjEwNjM1ODE3Mn0.x18Bh68n4ZgtNOyVPwIc01V6aL50oUaXjeXELzlWEh4")
                    sConn.setRequestProperty("Authorization", "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVtdHpwcmNudGVmemt2dnptaGZrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTA3ODIxNzIsImV4cCI6MjEwNjM1ODE3Mn0.x18Bh68n4ZgtNOyVPwIc01V6aL50oUaXjeXELzlWEh4")
                    sConn.setRequestProperty("Prefer", "return=representation")
                    sConn.connectTimeout = 10000
                    sConn.readTimeout = 10000
                    sConn.doOutput = true

                    val sBody = JSONObject().apply {
                        put("id_persona", idPersona)
                        put("id_tipo", if (alertType == "ACCIDENTE") 2 else 1)
                        put("id_estado", 1)
                        put("fecha_hora", nowUtcIso)
                        put("descripcion", message)
                        put("direccion_texto", "Ubicación móvil GPS (Pisco)")
                    }
                    val sBytes = sBody.toString().toByteArray(Charsets.UTF_8)
                    sConn.setFixedLengthStreamingMode(sBytes.size)
                    sConn.outputStream.use { os ->
                        os.write(sBytes)
                        os.flush()
                    }
                    val sCode = sConn.responseCode
                    val sResText = if (sCode in 200..299) {
                        sConn.inputStream.bufferedReader().use { it.readText() }
                    } else {
                        sConn.errorStream?.bufferedReader()?.use { it.readText() } ?: ""
                    }
                    android.util.Log.d("EmergencyForegroundService", "Supabase Response ($sCode): $sResText")
                    if (sCode in 200..299) {
                        nativeSuccess = true
                        try {
                            val jsonArr = org.json.JSONArray(sResText)
                            if (jsonArr.length() > 0) {
                                createdReportId = jsonArr.getJSONObject(0).optLong("id_reporte")
                            }
                        } catch (_: Exception) {}
                    }
                    sConn.disconnect()
                } catch (sErr: Exception) {
                    android.util.Log.e("EmergencyForegroundService", "Supabase error: ${sErr.message}", sErr)
                }

                // 5. Guardar inmediatamente en la caché local de reportes de Flutter (local_saved_reports_v2)
                try {
                    val rawJson = prefs.getString("flutter.local_saved_reports_v2", null)
                    val localArray = if (rawJson != null && rawJson.isNotEmpty()) {
                        try { org.json.JSONArray(rawJson) } catch (_: Exception) { org.json.JSONArray() }
                    } else {
                        org.json.JSONArray()
                    }

                    val reportRecord = JSONObject().apply {
                        put("id_reporte", createdReportId ?: System.currentTimeMillis())
                        put("id_tipo", if (alertType == "ACCIDENTE") 2 else 1)
                        put("tipo_incidencia", JSONObject().apply {
                            put("nombre", alertType)
                        })
                        put("id_estado", 1)
                        put("estado_reporte", JSONObject().apply {
                            put("nombre", "Enviado")
                        })
                        put("fecha_hora", nowUtcIso)
                        put("descripcion", message)
                        put("direccion_texto", "Ubicación móvil GPS (Pisco)")
                        put("fotos", org.json.JSONArray())
                        put("latitud", lat)
                        put("longitud", lon)
                        put("is_synced", true)
                    }

                    val newLocalArray = org.json.JSONArray()
                    newLocalArray.put(reportRecord)
                    for (i in 0 until localArray.length()) {
                        newLocalArray.put(localArray.get(i))
                    }
                    prefs.edit()
                        .putString("flutter.local_saved_reports_v2", newLocalArray.toString())
                        .apply()
                } catch (_: Exception) {}

                // 6. Actualizar flags de despacho y éxito
                isEmergencyDispatched = true
                isEmergencyActive = false
                prefs.edit()
                    .putBoolean("flutter.pending_emergency_dispatched", true)
                    .putBoolean("flutter.pending_emergency_active", false)
                    .putBoolean("flutter.native_dispatched_success", nativeSuccess)
                    .putString("flutter.last_dispatched_alert_type", alertType)
                    .putString("flutter.last_dispatched_source", source)
                    .putLong("flutter.last_dispatched_time", System.currentTimeMillis())
                    .apply()

                // 7. Activar rastreo en vivo si es ROBO
                if (alertType == "ROBO") {
                    isLiveTrackingActive = true
                    val notif = buildCurrentNotification()
                    val manager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
                    manager?.notify(NOTIFICATION_ID, notif)
                }

                // 8. Vibración de confirmación
                val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    vibrator?.vibrate(VibrationEffect.createOneShot(500, VibrationEffect.DEFAULT_AMPLITUDE))
                } else {
                    @Suppress("DEPRECATION")
                    vibrator?.vibrate(500)
                }

                // 9. Actualizar notificación permanente de alarma a despachado
                showDispatchedNotification(alertType)

                // 10. Si MainActivity está abierta o se abre, informarle
                MainActivity.instance?.runOnUiThread {
                    MainActivity.instance?.onEmergencyDispatchedFromNative(alertType, source)
                }
            } catch (fatal: Exception) {
                android.util.Log.e("EmergencyForegroundService", "Fatal error in dispatch: ${fatal.message}", fatal)
            }
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
        if (!isUserLoggedIn(applicationContext)) {
            super.onTaskRemoved(rootIntent)
            return
        }
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
