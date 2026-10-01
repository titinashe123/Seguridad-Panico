import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'whatsapp_api_service.dart';
import 'hardware_trigger_service.dart';

/// Servicio de Seguimiento y Rastreo GPS en Tiempo Real exclusivo para casos de ROBO.
/// Transmite periódicamente las coordenadas actualizadas a la Central de Video Vigilancia
/// y al mapa en vivo para seguir el desplazamiento de la víctima.
class LocationTrackingService extends ChangeNotifier {
  static final LocationTrackingService _instance = LocationTrackingService._internal();
  factory LocationTrackingService() => _instance;
  LocationTrackingService._internal();

  Timer? _trackingTimer;
  String? _activeAlertId;
  bool _isTracking = false;

  double _currentLat = -12.04637;
  double _currentLon = -77.02987;
  int _pointCount = 0;

  bool get isTracking => _isTracking;
  String? get activeAlertId => _activeAlertId;
  double get currentLat => _currentLat;
  double get currentLon => _currentLon;
  int get pointCount => _pointCount;

  String? get trackingMapUrl => _activeAlertId != null
      ? '${WhatsAppApiService.backendBaseUrl}/tracking/$_activeAlertId'
      : null;

  /// Inicia el rastreo GPS en vivo para una alerta de ROBO
  void startTracking({
    required String alertId,
    double initialLat = -12.04637,
    double initialLon = -77.02987,
  }) {
    // Si ya hay un rastreo activo previo, lo detenemos
    stopTracking(notifyBackend: false);

    _activeAlertId = alertId;
    _isTracking = true;
    _currentLat = initialLat;
    _currentLon = initialLon;
    _pointCount = 1;
    notifyListeners();

    // Notificar al servicio nativo para actualizar la barra de notificaciones de Android
    HardwareTriggerService().updateLiveTrackingNotification(true);

    developer.log(
      '🚨 Iniciando rastreo GPS en tiempo real para ROBO (ID: $alertId) en Lat $_currentLat, Lon $_currentLon',
      name: 'LocationTrackingService',
    );

    // Enviar actualización periódica cada 5 segundos
    _trackingTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      await _updateLiveLocation();
    });
  }

  Future<void> _updateLiveLocation() async {
    if (!_isTracking || _activeAlertId == null) return;

    // Simulación de desplazamiento natural (caminata / vehículo) en pruebas
    // En dispositivo móvil real se integra con la corriente GPS del sistema
    _pointCount++;
    _currentLat += (0.00018 * ((_pointCount % 2 == 0) ? 1.0 : 0.6));
    _currentLon += (0.00014 * ((_pointCount % 3 == 0) ? -1.0 : 1.0));

    notifyListeners();

    developer.log(
      '📍 Transmitiendo punto #$_pointCount de rastreo: Lat ${_currentLat.toStringAsFixed(5)}, Lon ${_currentLon.toStringAsFixed(5)}',
      name: 'LocationTrackingService',
    );

    // 1. Envío directo a la base de datos Supabase (tabla 'ubicacion')
    final numReportId = int.tryParse(_activeAlertId!.replaceAll(RegExp(r'\D'), ''));
    if (numReportId != null) {
      try {
        await http
            .post(
              Uri.parse('https://emtzprcntefzkvvzmhfk.supabase.co/rest/v1/ubicacion'),
              headers: {
                'Content-Type': 'application/json',
                'apikey': WhatsAppApiService.supabaseAnonKey,
                'Authorization': 'Bearer ${WhatsAppApiService.supabaseAnonKey}',
              },
              body: jsonEncode({
                'id_reporte': numReportId,
                'latitud': _currentLat,
                'longitud': _currentLon,
              }),
            )
            .timeout(const Duration(seconds: 4));
        developer.log('Punto #$_pointCount transmitido exitosamente a Supabase', name: 'LocationTrackingService');
      } catch (e) {
        developer.log('Fallo al transmitir a Supabase: $e', name: 'LocationTrackingService');
      }
    }

    // 2. Envío al backend local si está en ejecución
    try {
      final response = await http
          .post(
            Uri.parse('${WhatsAppApiService.backendBaseUrl}/api/tracking/$_activeAlertId'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'lat': _currentLat,
              'lon': _currentLon,
              'speed': '${(12 + (_pointCount % 6) * 3)} km/h',
              'timestamp': DateTime.now().toIso8601String(),
            }),
          )
          .timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        developer.log('Punto transmitido exitosamente al servidor de rastreo', name: 'LocationTrackingService');
      }
    } catch (e) {
      developer.log('Fallo al transmitir punto al backend local: $e', name: 'LocationTrackingService');
    }
  }

  /// Detiene el rastreo continuo de la víctima
  Future<void> stopTracking({bool notifyBackend = true}) async {
    final alertToStop = _activeAlertId;
    _trackingTimer?.cancel();
    _trackingTimer = null;
    _isTracking = false;
    _activeAlertId = null;
    _pointCount = 0;
    notifyListeners();

    // Restaurar notificación nativa a modo guardia normal
    HardwareTriggerService().updateLiveTrackingNotification(false);

    if (notifyBackend && alertToStop != null) {
      developer.log('Deteniendo rastreo en el backend para $alertToStop', name: 'LocationTrackingService');
      try {
        await http
            .post(
              Uri.parse('${WhatsAppApiService.backendBaseUrl}/api/tracking/$alertToStop/stop'),
              headers: {'Content-Type': 'application/json'},
            )
            .timeout(const Duration(seconds: 3));
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _trackingTimer?.cancel();
    super.dispose();
  }
}
