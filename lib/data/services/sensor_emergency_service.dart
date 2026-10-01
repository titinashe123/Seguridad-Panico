import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math' as math;
import 'package:sensors_plus/sensors_plus.dart';

typedef EmergencyTriggerCallback = void Function(String triggerReason, String source);

/// Servicio para la detección de caídas, golpes o impactos violentos mediante
/// los sensores de hardware del móvil (Acelerómetro y Giroscopio).
class SensorEmergencyService {
  static final SensorEmergencyService _instance = SensorEmergencyService._internal();
  factory SensorEmergencyService() => _instance;
  SensorEmergencyService._internal();

  StreamSubscription<AccelerometerEvent>? _accelSubscription;
  StreamSubscription<GyroscopeEvent>? _gyroSubscription;

  EmergencyTriggerCallback? _onEmergencyTriggered;

  bool _isListening = false;
  bool get isListening => _isListening;

  /// Umbral de aceleración para detectar un impacto o caída severa (m/s^2)
  /// La gravedad normal es aprox 9.8 m/s^2. Una caída o impacto violento supera 26-30 m/s^2.
  double impactThreshold = 28.0;

  /// Umbral de rotación brusca para el giroscopio (rad/s)
  double gyroRotationThreshold = 8.5;

  DateTime? _lastTriggerTime;

  /// Inicia el monitoreo de los sensores del teléfono
  void startMonitoring({
    required EmergencyTriggerCallback onTriggered,
    bool listenToHardware = true,
  }) {
    _onEmergencyTriggered = onTriggered;

    if (_isListening || !listenToHardware) return;
    _isListening = true;

    try {
      // 1. Escuchar eventos del acelerómetro
      _accelSubscription = accelerometerEventStream().listen(
        (AccelerometerEvent event) {
          _handleAccelerometer(event.x, event.y, event.z);
        },
        onError: (error) {
          developer.log('Error en sensor de acelerómetro: $error', name: 'SensorEmergencyService');
        },
        cancelOnError: false,
      );

      // 2. Escuchar eventos del giroscopio
      _gyroSubscription = gyroscopeEventStream().listen(
        (GyroscopeEvent event) {
          _handleGyroscope(event.x, event.y, event.z);
        },
        onError: (error) {
          developer.log('Error en sensor de giroscopio: $error', name: 'SensorEmergencyService');
        },
        cancelOnError: false,
      );

      developer.log('Sensores (Acelerómetro y Giroscopio) activos en monitoreo continuo', name: 'SensorEmergencyService');
    } catch (e) {
      developer.log('Dispositivo no soporta sensores de movimiento nativos o web: $e', name: 'SensorEmergencyService');
    }
  }

  void _handleAccelerometer(double x, double y, double z) {
    // Calcular magnitud total del vector de aceleración: sqrt(x^2 + y^2 + z^2)
    final magnitude = math.sqrt(x * x + y * y + z * z);

    if (magnitude > impactThreshold) {
      _dispatchEmergencyIfReady(
        reason: 'Impacto o Caída Violenta detectada (${magnitude.toStringAsFixed(1)} m/s²)',
        source: 'sensor_acelerometro',
      );
    }
  }

  void _handleGyroscope(double x, double y, double z) {
    // Magnitud de rotación angular
    final rotMagnitude = math.sqrt(x * x + y * y + z * z);

    if (rotMagnitude > gyroRotationThreshold) {
      _dispatchEmergencyIfReady(
        reason: 'Rotación brusca o forcejeo detectado (${rotMagnitude.toStringAsFixed(1)} rad/s)',
        source: 'sensor_giroscopio',
      );
    }
  }

  void _dispatchEmergencyIfReady({required String reason, required String source}) {
    final now = DateTime.now();
    // Cooldown de 12 segundos para prevenir múltiples disparos seguidos por el mismo impacto
    if (_lastTriggerTime != null && now.difference(_lastTriggerTime!).inSeconds < 12) {
      return;
    }
    _lastTriggerTime = now;

    developer.log('🚨 DISPARO POR SENSOR: $reason (Origen: $source)', name: 'SensorEmergencyService');
    _onEmergencyTriggered?.call(reason, source);
  }

  /// Método para simular un impacto/caída violenta (útil en emuladores o navegador web)
  void simulateImpactTrigger() {
    _dispatchEmergencyIfReady(
      reason: 'Prueba de Sensor: Impacto simulado a 32.4 m/s²',
      source: 'sensor_simulado',
    );
  }

  /// Detiene la escucha de sensores
  void stopMonitoring() {
    _accelSubscription?.cancel();
    _gyroSubscription?.cancel();
    _accelSubscription = null;
    _gyroSubscription = null;
    _isListening = false;
    developer.log('Sensores detenidos', name: 'SensorEmergencyService');
  }
}
