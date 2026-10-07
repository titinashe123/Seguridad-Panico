import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import 'package:shared_preferences/shared_preferences.dart';

/// Servicio para obtención de ubicación GPS exacta en tiempo real del dispositivo
class GpsLocationService {
  /// Obtiene la posición GPS exacta del dispositivo con manejo de permisos y alta precisión satelital
  static Future<Position?> getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    try {
      // 1. Verificar si los servicios de ubicación del sistema están activados
      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        developer.log('Servicios de ubicación desactivados en el teléfono', name: 'GpsLocationService');
        return await _getFilteredLastKnown();
      }

      // 2. Verificar permisos de acceso a la ubicación
      permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          developer.log('Permisos de GPS denegados por el usuario', name: 'GpsLocationService');
          return await _getFilteredLastKnown();
        }
      }

      if (permission == LocationPermission.deniedForever) {
        developer.log('Permisos de GPS denegados permanentemente', name: 'GpsLocationService');
        return await _getFilteredLastKnown();
      }

      // 3. Revisar si la última posición en caché es ULTRA reciente (menor a 25s) y de gran precisión (< 15m)
      final quickPos = await Geolocator.getLastKnownPosition();
      if (quickPos != null) {
        final age = DateTime.now().difference(quickPos.timestamp);
        if (age.inSeconds < 25 && quickPos.accuracy <= 15.0) {
          developer.log('✅ Usando posición reciente de alta fidelidad (±${quickPos.accuracy}m)', name: 'GpsLocationService');
          _savePositionToCache(quickPos);
          return quickPos;
        }
      }

      // 4. Solicitar posición GPS satelital con máxima precisión (bestForNavigation) y 10s de ventana de fijación
      final locationSettings = defaultTargetPlatform == TargetPlatform.android
          ? AndroidSettings(
              accuracy: LocationAccuracy.bestForNavigation,
              distanceFilter: 0,
              forceLocationManager: false,
              intervalDuration: const Duration(milliseconds: 500),
              timeLimit: const Duration(seconds: 10),
            )
          : const LocationSettings(
              accuracy: LocationAccuracy.bestForNavigation,
              timeLimit: Duration(seconds: 10),
            );

      try {
        final position = await Geolocator.getCurrentPosition(locationSettings: locationSettings);
        developer.log('🛰️ GPS satelital fijado con éxito: Lat ${position.latitude}, Lon ${position.longitude}, Margen ±${position.accuracy}m', name: 'GpsLocationService');
        _savePositionToCache(position);
        return position;
      } catch (e) {
        developer.log('Reintentando con sensor de hardware GPS directo (forceLocationManager=true): $e', name: 'GpsLocationService');
        if (defaultTargetPlatform == TargetPlatform.android) {
          final hwSettings = AndroidSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 0,
            forceLocationManager: true,
            timeLimit: const Duration(seconds: 8),
          );
          final hwPos = await Geolocator.getCurrentPosition(locationSettings: hwSettings);
          _savePositionToCache(hwPos);
          return hwPos;
        }
        rethrow;
      }
    } catch (e) {
      developer.log('Error obteniendo posición GPS en tiempo real: $e', name: 'GpsLocationService');
      return await _getFilteredLastKnown();
    }
  }

  static void _savePositionToCache(Position pos) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_known_real_lat', pos.latitude.toString());
      await prefs.setString('last_known_real_lon', pos.longitude.toString());
      await prefs.setInt('last_known_real_time', DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
  }

  /// Recupera la última posición real persistida en SharedPreferences
  static Future<Map<String, dynamic>?> getCachedRealCoordinates() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final latStr = prefs.getString('last_known_real_lat');
      final lonStr = prefs.getString('last_known_real_lon');
      final addr = prefs.getString('last_known_real_address');
      if (latStr != null && lonStr != null) {
        final lat = double.tryParse(latStr);
        final lon = double.tryParse(lonStr);
        if (lat != null && lon != null) {
          return {
            'lat': lat,
            'lon': lon,
            'address': addr ?? 'Ubicación móvil GPS previa',
          };
        }
      }
    } catch (_) {}
    return null;
  }

  /// Retorna la última posición en memoria como último recurso
  static Future<Position?> _getFilteredLastKnown() async {
    try {
      final pos = await Geolocator.getLastKnownPosition();
      if (pos != null) {
        _savePositionToCache(pos);
      }
      return pos;
    } catch (_) {
      return null;
    }
  }

  /// Geocodificación inversa para obtener el nombre real de la calle/distrito
  static Future<String?> getAddressFromCoordinates(double lat, double lon) async {
    try {
      final url = Uri.parse('https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lon&zoom=18&addressdetails=1');
      final response = await http.get(url, headers: {
        'User-Agent': 'AlertaCiudadanaPisco/1.0',
      }).timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final address = data['address'] as Map<String, dynamic>?;
        if (address != null) {
          final road = address['road'] ?? address['pedestrian'] ?? address['suburb'];
          final city = address['city'] ?? address['town'] ?? address['county'] ?? 'Pisco';
          if (road != null) {
            return '$road, $city';
          }
        }
        final displayName = data['display_name'] as String?;
        if (displayName != null) {
          final parts = displayName.split(',');
          return parts.take(2).join(',').trim();
        }
      }
    } catch (_) {}
    return null;
  }

  /// Retorna un texto formateado de la dirección o coordenadas para la alerta
  static String formatLocationText(Position? position, {String fallback = 'Pisco, Ica - Ubicación móvil GPS'}) {
    if (position == null) return fallback;
    final accuracyStr = ' (±${position.accuracy.toStringAsFixed(1)}m)';
    return 'Lat: ${position.latitude.toStringAsFixed(5)}, Lon: ${position.longitude.toStringAsFixed(5)}$accuracyStr';
  }
}
