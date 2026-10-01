import 'dart:developer' as developer;
import 'package:geolocator/geolocator.dart';

/// Servicio para obtención de ubicación GPS exacta en tiempo real del dispositivo
class GpsLocationService {
  /// Obtiene la posición GPS exacta del dispositivo con manejo de permisos
  static Future<Position?> getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    try {
      // 1. Verificar si los servicios de ubicación del sistema están activados
      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        developer.log('Servicios de ubicación desactivados en el teléfono', name: 'GpsLocationService');
        // Intentar obtener última posición conocida
        return await Geolocator.getLastKnownPosition();
      }

      // 2. Verificar permisos de acceso a la ubicación
      permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          developer.log('Permisos de GPS denegados por el usuario', name: 'GpsLocationService');
          return await Geolocator.getLastKnownPosition();
        }
      }

      if (permission == LocationPermission.deniedForever) {
        developer.log('Permisos de GPS denegados permanentemente', name: 'GpsLocationService');
        return await Geolocator.getLastKnownPosition();
      }

      // 3. Obtener posición GPS actual con alta precisión
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
    } catch (e) {
      developer.log('Error obteniendo posición GPS: $e', name: 'GpsLocationService');
      try {
        return await Geolocator.getLastKnownPosition();
      } catch (_) {
        return null;
      }
    }
  }

  /// Retorna un texto formateado de la dirección o coordenadas para la alerta
  static String formatLocationText(Position? position, {String fallback = 'Pisco, Ica - Ubicación móvil GPS'}) {
    if (position == null) return fallback;
    return 'Lat: ${position.latitude.toStringAsFixed(5)}, Lon: ${position.longitude.toStringAsFixed(5)}';
  }
}
