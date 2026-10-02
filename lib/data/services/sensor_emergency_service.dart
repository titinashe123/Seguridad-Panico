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

  /// Umbral de aceleración para detectar un arrebato violento de celular (m/s²)
  /// Calibrado según patrones de Google Theft Detection Lock:
  /// En reposo/caminar normal la gravedad es 9.8 m/s². Un tirón brusco o arrebato genera picos > 21.0 m/s².
  double snatchAccelerationThreshold = 21.0;

  /// Umbral de tirón dinámico |magnitud - gravedad| (m/s²)
  double dynamicJerkThreshold = 11.5;

  /// Umbral de rotación brusca para el giroscopio ante forcejeo de robo (rad/s)
  /// Más de 5.5 rad/s equivale a > 315°/seg de giro violento
  double struggleGyroThreshold = 5.5;

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

      developer.log('Sensores Antirrobo (Acelerómetro y Giroscopio) activos en monitoreo continuo', name: 'SensorEmergencyService');
    } catch (e) {
      developer.log('Dispositivo no soporta sensores de movimiento nativos o web: $e', name: 'SensorEmergencyService');
    }
  }

  void _handleAccelerometer(double x, double y, double z) {
    // Calcular magnitud total del vector de aceleración: sqrt(x^2 + y^2 + z^2)
    final magnitude = math.sqrt(x * x + y * y + z * z);
    final dynamicJerk = (magnitude - 9.8).abs();

    if (magnitude > snatchAccelerationThreshold || dynamicJerk > dynamicJerkThreshold) {
      _dispatchEmergencyIfReady(
        reason: 'Arrebato violento de celular detectado (${magnitude.toStringAsFixed(1)} m/s²)',
        source: 'sensor_antirrobo_acelerometro',
      );
    }
  }

  void _handleGyroscope(double x, double y, double z) {
    // Magnitud de rotación angular
    final rotMagnitude = math.sqrt(x * x + y * y + z * z);

    if (rotMagnitude > struggleGyroThreshold) {
      _dispatchEmergencyIfReady(
        reason: 'Forcejeo o giro violento detectado (${rotMagnitude.toStringAsFixed(1)} rad/s)',
        source: 'sensor_antirrobo_giroscopio',
      );
    }
  }

  void _dispatchEmergencyIfReady({required String reason, required String source}) {
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
  void simulateTheftSnatchTrigger() {
    _dispatchEmergencyIfReady(
      reason: 'Simulación Antirrobo: Arrebato detectado a 24.2 m/s²',
      source: 'sensor_simulado_robo',
    );
  }

  /// Alias de compatibilidad previa
  void simulateImpactTrigger() => simulateTheftSnatchTrigger();

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
