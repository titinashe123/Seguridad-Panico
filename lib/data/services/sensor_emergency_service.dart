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
  /// Un tirón brusco real al arrebatar el teléfono genera aceleraciones superiores a 28.5 m/s² (~2.9G).
  /// Esto previene falsos positivos al presionar botones físicos con fuerza, caminar o sentarse.
  double snatchAccelerationThreshold = 28.5;

  /// Umbral de rotación brusca para el giroscopio ante forcejeo violento de robo (rad/s)
  /// Más de 8.5 rad/s equivale a > 487°/seg de giro violento (evita falsos giros rápidos de muñeca).
  double struggleGyroThreshold = 8.5;

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

    if (magnitude > snatchAccelerationThreshold) {
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
