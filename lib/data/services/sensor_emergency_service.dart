import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math' as math;
import 'package:sensors_plus/sensors_plus.dart';
import 'package:geolocator/geolocator.dart';

import 'session_service.dart';

typedef EmergencyTriggerCallback = void Function(String triggerReason, String source);

/// Servicio para la detección de arrebato violento de celular mediante
/// acelerómetro y giroscopio con verificación de fuga en dos fases (estándar Google Theft Detection)
class SensorEmergencyService {
  static final SensorEmergencyService _instance = SensorEmergencyService._internal();
  factory SensorEmergencyService() => _instance;
  SensorEmergencyService._internal();

  StreamSubscription<UserAccelerometerEvent>? _userAccelSubscription;
  StreamSubscription<AccelerometerEvent>? _rawAccelSubscription;
  StreamSubscription<GyroscopeEvent>? _gyroSubscription;
  StreamSubscription<Position>? _gpsEscapeSubscription;

  EmergencyTriggerCallback? _onEmergencyTriggered;

  bool _isListening = false;
  bool get isListening => _isListening;

  /// Umbral de aceleración lineal para detectar un jalón violento (m/s²)
  /// Un tirón violento de arrebato callejero genera aceleraciones bruscas >= 24.0 m/s²
  double snatchLinearThreshold = 24.0;

  /// Umbral con gravedad incluida para acelerómetro crudo
  double snatchRawThreshold = 38.0;

  /// Umbral de rotación brusca simultánea para el giroscopio ante forcejeo o arrebato (rad/s)
  /// Exige que exista torsión o arrancamiento violento de los dedos (> 400°/s)
  double struggleGyroThreshold = 7.0;

  DateTime? _lastTriggerTime;

  // Variables de memoria sensorial continua (Fusión de sensores)
  double _lastLinearMag = 0.0;
  double _lastGyroMag = 0.0;

  // FASE 2: Variables de Verificación de Huida Posterior (Flight Verification)
  bool _isVerifyingEscape = false;
  DateTime? _candidateSnatchTime;
  DateTime? _lastActiveMotionTime;
  final List<double> _flightLinearSamples = [];
  final List<double> _flightGyroSamples = [];
  String _candidateReason = '';
  String _candidateSource = '';
  Timer? _escapeVerificationTimer;

  Position? _startPosition;
  double _maxGpsSpeed = 0.0;
  double _maxGpsDistance = 0.0;

  /// Inicia el monitoreo de los sensores del teléfono
  void startMonitoring({
    required EmergencyTriggerCallback onTriggered,
    bool listenToHardware = true,
  }) {
    _onEmergencyTriggered = onTriggered;

    if (_isListening || !listenToHardware) return;
    _isListening = true;

    try {
      // 1. Escuchar Acelerómetro Lineal (sin gravedad estática)
      _userAccelSubscription = userAccelerometerEventStream().listen(
        (UserAccelerometerEvent event) {
          _handleLinearAccelerometer(event.x, event.y, event.z);
        },
        onError: (error) {
          developer.log('Error en sensor userAccelerometer: $error', name: 'SensorEmergencyService');
        },
        cancelOnError: false,
      );

      // Fallback para acelerómetro estándar si no hay sensor sintético
      _rawAccelSubscription = accelerometerEventStream().listen(
        (AccelerometerEvent event) {
          _handleRawAccelerometer(event.x, event.y, event.z);
        },
        onError: (_) {},
        cancelOnError: false,
      );

      // 2. Escuchar Giroscopio
      _gyroSubscription = gyroscopeEventStream().listen(
        (GyroscopeEvent event) {
          _handleGyroscope(event.x, event.y, event.z);
        },
        onError: (error) {
          developer.log('Error en sensor de giroscopio: $error', name: 'SensorEmergencyService');
        },
        cancelOnError: false,
      );

      developer.log('Sensores Antirrobo en 2 Fases (Jalón + Huida GPS) activos', name: 'SensorEmergencyService');
    } catch (e) {
      developer.log('Dispositivo no soporta sensores de movimiento nativos o web: $e', name: 'SensorEmergencyService');
    }
  }

  void _handleLinearAccelerometer(double x, double y, double z) {
    final magnitude = math.sqrt(x * x + y * y + z * z);
    _lastLinearMag = magnitude;
    final now = DateTime.now();

    // FASE 2: Si ya hay una verificación de huida en curso
    if (_isVerifyingEscape) {
      final elapsed = _candidateSnatchTime != null
          ? now.difference(_candidateSnatchTime!).inMilliseconds
          : 0;

      // Registrar aceleración posterior a partir de los 650 ms (fase de locomoción/fuga)
      if (elapsed >= 650) {
        _flightLinearSamples.add(magnitude);
        if (magnitude > 1.8) {
          _lastActiveMotionTime = now;
        }
      }
      return;
    }

    if (_lastTriggerTime != null && now.difference(_lastTriggerTime!).inSeconds < 8) {
      return;
    }

    // FASE 1: Detección estricta de Jalón Y Movimiento Brusco
    // Solo se activa si detecta un jalón violento acompañado de torsión/movimiento brusco
    final hasSnatchAndTwist = (magnitude >= snatchLinearThreshold && _lastGyroMag >= struggleGyroThreshold);
    final hasExtremeYank = (magnitude >= 36.0 && _lastGyroMag >= 4.0);

    if (hasSnatchAndTwist || hasExtremeYank) {
      _startEscapeVerification(
        reason: 'Jalón y movimiento brusco detectado (${magnitude.toStringAsFixed(1)} m/s², ${_lastGyroMag.toStringAsFixed(1)} rad/s)',
        source: 'sensor_antirrobo_fusion',
      );
    }
  }

  void _handleRawAccelerometer(double x, double y, double z) {
    if (_userAccelSubscription != null) return;

    final magnitude = math.sqrt(x * x + y * y + z * z);
    final linearEst = (magnitude - 9.8).abs();
    _lastLinearMag = linearEst;
    final now = DateTime.now();

    if (_isVerifyingEscape) {
      final elapsed = _candidateSnatchTime != null
          ? now.difference(_candidateSnatchTime!).inMilliseconds
          : 0;
      if (elapsed >= 650) {
        _flightLinearSamples.add(linearEst);
        if (linearEst > 1.8) {
          _lastActiveMotionTime = now;
        }
      }
      return;
    }

    if (_lastTriggerTime != null && now.difference(_lastTriggerTime!).inSeconds < 8) {
      return;
    }

    final hasSnatchAndTwist = (magnitude >= snatchRawThreshold && _lastGyroMag >= struggleGyroThreshold);
    final hasExtremeYank = (magnitude >= 45.0 && _lastGyroMag >= 4.0);

    if (hasSnatchAndTwist || hasExtremeYank) {
      _startEscapeVerification(
        reason: 'Jalón y movimiento brusco detectado (${magnitude.toStringAsFixed(1)} m/s², ${_lastGyroMag.toStringAsFixed(1)} rad/s)',
        source: 'sensor_antirrobo_acelerometro',
      );
    }
  }

  void _handleGyroscope(double x, double y, double z) {
    final rotMagnitude = math.sqrt(x * x + y * y + z * z);
    _lastGyroMag = rotMagnitude;
    final now = DateTime.now();

    if (_isVerifyingEscape) {
      final elapsed = _candidateSnatchTime != null
          ? now.difference(_candidateSnatchTime!).inMilliseconds
          : 0;
      if (elapsed >= 650) {
        _flightGyroSamples.add(rotMagnitude);
        if (rotMagnitude > 0.8) {
          _lastActiveMotionTime = now;
        }
      }
      return;
    }

    if (_lastTriggerTime != null && now.difference(_lastTriggerTime!).inSeconds < 8) {
      return;
    }

    // Si el movimiento angular es violento y coincide con tirón lineal
    final hasSnatchAndTwist = (rotMagnitude >= struggleGyroThreshold && _lastLinearMag >= snatchLinearThreshold);
    final hasHighStruggle = (rotMagnitude >= 14.0 && _lastLinearMag >= 18.0);

    if (hasSnatchAndTwist || hasHighStruggle) {
      _startEscapeVerification(
        reason: 'Forcejeo con jalón brusco detectado (${rotMagnitude.toStringAsFixed(1)} rad/s, ${_lastLinearMag.toStringAsFixed(1)} m/s²)',
        source: 'sensor_antirrobo_giroscopio',
      );
    }
  }

  void _startEscapeVerification({required String reason, required String source}) {
    _isVerifyingEscape = true;
    _candidateSnatchTime = DateTime.now();
    _candidateReason = reason;
    _candidateSource = source;
    _flightLinearSamples.clear();
    _flightGyroSamples.clear();
    _lastActiveMotionTime = DateTime.now();
    _maxGpsSpeed = 0.0;
    _maxGpsDistance = 0.0;
    _startPosition = null;

    developer.log(
      '⚡ FASE 1 CONFIRMADA: Jalón y movimiento brusco. Verificando aceleración posterior de huida con apoyo GPS...',
      name: 'SensorEmergencyService',
    );

    // 1. Obtener posición GPS inicial de referencia
    Geolocator.getLastKnownPosition().then((pos) {
      if (pos != null && _startPosition == null) {
        _startPosition = pos;
        if (pos.speed > _maxGpsSpeed) _maxGpsSpeed = pos.speed;
      }
    }).catchError((_) => null);

    // 2. Suscribirse activamente a stream de GPS en alta precisión durante la ventana de huida
    _gpsEscapeSubscription?.cancel();
    try {
      _gpsEscapeSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 0,
        ),
      ).listen(
        (Position pos) {
          if (_startPosition == null) {
            _startPosition = pos;
          } else {
            final dist = Geolocator.distanceBetween(
              _startPosition!.latitude,
              _startPosition!.longitude,
              pos.latitude,
              pos.longitude,
            );
            if (dist > _maxGpsDistance) {
              _maxGpsDistance = dist;
            }
          }
          if (pos.speed > _maxGpsSpeed) {
            _maxGpsSpeed = pos.speed;
          }
        },
        onError: (_) {},
        cancelOnError: false,
      );
    } catch (e) {
      developer.log('Error iniciando stream de GPS para verificación de huida: $e', name: 'SensorEmergencyService');
    }

    _escapeVerificationTimer?.cancel();
    // Ventana de evaluación de huida de 2400 ms
    _escapeVerificationTimer = Timer(const Duration(milliseconds: 2400), () {
      _evaluatePostSnatchEscape();
    });
  }

  void _evaluatePostSnatchEscape() async {
    if (!_isVerifyingEscape) return;
    _isVerifyingEscape = false;

    // Detener stream de GPS
    _gpsEscapeSubscription?.cancel();
    _gpsEscapeSubscription = null;

    final loggedIn = await SessionService.isLoggedIn();
    if (!loggedIn) return;

    final now = DateTime.now();
    final timeSinceLastMotion = _lastActiveMotionTime != null
        ? now.difference(_lastActiveMotionTime!).inMilliseconds
        : 2400;

    // Consulta GPS de cierre
    try {
      final endPos = await Geolocator.getLastKnownPosition();
      if (endPos != null) {
        if (endPos.speed > _maxGpsSpeed) _maxGpsSpeed = endPos.speed;
        if (_startPosition != null) {
          final dist = Geolocator.distanceBetween(
            _startPosition!.latitude,
            _startPosition!.longitude,
            endPos.latitude,
            endPos.longitude,
          );
          if (dist > _maxGpsDistance) _maxGpsDistance = dist;
        }
      }
    } catch (_) {}

    // Estadísticas inerciales de la aceleración posterior en la huida (t >= 650ms)
    double meanFlightAccel = 0.0;
    double peakFlightAccel = 0.0;
    int activeSamples = 0;
    int stillSamples = 0;

    if (_flightLinearSamples.isNotEmpty) {
      double sum = 0.0;
      for (final s in _flightLinearSamples) {
        sum += s;
        if (s > peakFlightAccel) peakFlightAccel = s;
        if (s >= 1.8) {
          activeSamples++;
        } else if (s < 0.8) {
          stillSamples++;
        }
      }
      meanFlightAccel = sum / _flightLinearSamples.length;
    }

    final totalFlightSamples = _flightLinearSamples.length;

    developer.log(
      '📊 Evaluación Fase 2 (Huida): '
      'tiempoSinMov=${timeSinceLastMotion}ms, '
      'muestras=$totalFlightSamples, '
      'mediaAcel=${meanFlightAccel.toStringAsFixed(2)} m/s², '
      'picoAcel=${peakFlightAccel.toStringAsFixed(2)} m/s², '
      'activos=$activeSamples, quietos=$stillSamples, '
      'gpsDist=${_maxGpsDistance.toStringAsFixed(1)}m, '
      'gpsVel=${_maxGpsSpeed.toStringAsFixed(1)}m/s',
      name: 'SensorEmergencyService',
    );

    // CRITERIOS ESTRICTOS DE HUIDA POSTERIOR:
    // 1. Apoyo con GPS: Fuga vehicular o carrera confirmada por velocidad o desplazamiento
    final bool gpsEscapeConfirmed = (_maxGpsSpeed >= 2.0 && _maxGpsDistance >= 3.0) ||
                                    (_maxGpsDistance >= 4.5);

    // 2. Aceleración posterior sostenida: Fuga a pie con zancadas dinámicas
    // - Movimiento presente al final de la ventana (< 380 ms)
    // - Aceleración media >= 2.0 m/s²
    // - Pico de zancada >= 3.5 m/s²
    // - Muestras activas superan al reposo
    final bool inertialEscapeConfirmed = (timeSinceLastMotion < 380) &&
                                         (meanFlightAccel >= 2.0) &&
                                         (peakFlightAccel >= 3.5) &&
                                         (activeSamples >= 5) &&
                                         (activeSamples > stillSamples);

    // Si el celular fue arrojado a la cama, sofá o mesa:
    // Queda en reposo absoluto en la cola de la ventana (mediaAcel < 0.6 m/s², gpsDist == 0 m).
    // Se descarta como falso positivo.

    if (gpsEscapeConfirmed || inertialEscapeConfirmed) {
      String escapeDetails;
      if (gpsEscapeConfirmed) {
        escapeDetails = 'Huida confirmada con GPS (${_maxGpsSpeed.toStringAsFixed(1)} m/s, ${_maxGpsDistance.toStringAsFixed(1)} m)';
      } else {
        escapeDetails = 'Aceleración continua de huida a pie (${meanFlightAccel.toStringAsFixed(1)} m/s² sostenidos)';
      }

      _dispatchEmergencyIfReady(
        reason: '$_candidateReason -> $escapeDetails',
        source: _candidateSource,
      );
    } else {
      developer.log(
        '🛑 FALSO POSITIVO DESCARTADO: No hubo aceleración posterior de huida ni desplazamiento GPS (celular en reposo en cama/mesa).',
        name: 'SensorEmergencyService',
      );
    }
  }

  void _dispatchEmergencyIfReady({
    required String reason,
    required String source,
    bool bypassAuth = false,
  }) async {
    if (!bypassAuth) {
      final loggedIn = await SessionService.isLoggedIn();
      if (!loggedIn) return;
    }

    final now = DateTime.now();
    // Cooldown de 8 segundos para prevenir múltiples disparos seguidos por el mismo arrebato
    if (_lastTriggerTime != null && now.difference(_lastTriggerTime!).inSeconds < 8) {
      return;
    }
    _lastTriggerTime = now;

    developer.log('🚨 DISPARO POR SENSOR ANTIRROBO: $reason (Origen: $source)', name: 'SensorEmergencyService');
    _onEmergencyTriggered?.call(reason, source);
  }

  /// Método para simular un arrebato de celular (útil en pruebas)
  void simulateTheftSnatchTrigger({bool bypassAuth = true}) {
    _dispatchEmergencyIfReady(
      reason: 'Simulación Antirrobo: Arrebato detectado a 30.5 m/s²',
      source: 'sensor_simulado_robo',
      bypassAuth: bypassAuth,
    );
  }

  /// Alias de compatibilidad previa
  void simulateImpactTrigger() => simulateTheftSnatchTrigger();

  /// Detiene la escucha de sensores
  void stopMonitoring() {
    _escapeVerificationTimer?.cancel();
    _escapeVerificationTimer = null;
    _gpsEscapeSubscription?.cancel();
    _gpsEscapeSubscription = null;
    _isVerifyingEscape = false;
    _userAccelSubscription?.cancel();
    _rawAccelSubscription?.cancel();
    _gyroSubscription?.cancel();
    _userAccelSubscription = null;
    _rawAccelSubscription = null;
    _gyroSubscription = null;
    _isListening = false;
    developer.log('Sensores detenidos', name: 'SensorEmergencyService');
  }
}
