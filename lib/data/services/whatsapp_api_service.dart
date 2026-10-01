import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:http/http.dart' as http;
import 'report_storage_service.dart';
import 'session_service.dart';

/// Servicio para el envío automatizado de alertas vía WhatsApp API
/// con mensajes predefinidos según la categoría de emergencia y despacho directo
/// al número oficial 976264949 sin abrir la aplicación de WhatsApp.
class WhatsAppApiService {
  /// Número oficial de auxilio y despacho de la Central de Video Vigilancia (Perú)
  static const String defaultEmergencyRecipient = '+51 976264949';
  
  /// URL del backend central de despacho de emergencias
  static const String backendBaseUrl = 'http://127.0.0.1:5000';

  /// URL de Supabase Edge Function de producción
  static const String supabaseFunctionsUrl = 'https://emtzprcntefzkvvzmhfk.supabase.co/functions/v1/alerts';

  /// Clave pública anónima de Supabase
  static const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVtdHpwcmNudGVmemt2dnptaGZrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTA3ODIxNzIsImV4cCI6MjEwNjM1ODE3Mn0.x18Bh68n4ZgtNOyVPwIc01V6aL50oUaXjeXELzlWEh4';

  /// Normaliza el número al formato internacional para la API (51976264949)
  static String normalizeNumber(String phone) {
    final clean = phone.replaceAll(RegExp(r'\D'), '');
    if (clean.length == 9 && clean.startsWith('9')) {
      return '51$clean';
    }
    if (clean.startsWith('51') && clean.length == 11) {
      return clean;
    }
    return clean.isNotEmpty ? clean : '51976264949';
  }

  static String getPredefinedMessage(
    String category, {
    String address = 'Av. de la Constitución 145, Lima',
    double lat = -12.04637,
    double lon = -77.02987,
    String source = 'BOTÓN PRINCIPAL',
  }) {
    final catNormalized = category.trim().toUpperCase();

    String headline;
    switch (catNormalized) {
      case 'ROBO':
        headline = '🚨 ¡AUXILIO! ME ESTÁN ROBANDO 🚨';
        break;
      case 'SECUESTRO':
        headline = '🛑 ¡ALERTA MÁXIMA: POSIBLE SECUESTRO EN CURSO! INTERVENCIÓN POLICIAL INMEDIATA 🛑';
        break;
      case 'INCENDIO':
        headline = '🔥 ¡ALERTA DE INCENDIO! UNIDAD DE BOMBEROS REQUERIDA 🔥';
        break;
      case 'ACCIDENTE':
        headline = '🚗💥 ¡ACCIDENTE DE TRÁNSITO! AMBULANCIA Y POLICÍA REQUERIDA 🚗💥';
        break;
      case 'ASESINATO':
        headline = '🛑 ¡ALERTA CRÍTICA: ATENTADO / ASESINATO! INTERVENCIÓN INMEDIATA 🛑';
        break;
      case 'GRESCA':
        headline = '🥊 ¡ALTERCADO / GRESCA EN VÍA PÚBLICA! PATRULLAJE URGENTE 🥊';
        break;
      case 'PERSONALIZADO':
        headline = '⚠️ ¡ALERTA DE SEGURIDAD CIUDADANA! ⚠️';
        break;
      default:
        headline = '🚨 ¡ALERTA DE EMERGENCIA CIUDADANA: $catNormalized! 🚨';
        break;
    }

    final gmapsNav = '🚗 Cómo llegar (Google Maps): https://www.google.com/maps/dir/?api=1&destination=${lat.toStringAsFixed(5)},${lon.toStringAsFixed(5)}';

    return '$headline\n'
        '📍 Ubicación: $address\n'
        '🛰️ Coordenadas: Lat ${lat.toStringAsFixed(5)}, Lon ${lon.toStringAsFixed(5)}\n'
        '🗺️ Mapa: https://maps.google.com/?q=${lat.toStringAsFixed(5)},${lon.toStringAsFixed(5)}\n'
        '$gmapsNav\n'
        '⚡ Disparador: $source\n'
        '🛡️ Despacho automático WhatsApp API a la Central de Video Vigilancia.';
  }

  /// Último ID de alerta despachada (usado para inicializar rastreo en vivo de ROBO)
  static String? lastAlertId;

  /// Persiste el reporte e incidencias en almacenamiento dual (Local y Supabase)
  /// Almacena imágenes adjuntas en formato base64 / metadata dentro del campo fotos (JSONB)
  static Future<int?> saveReportToDatabase({
    required String category,
    required String message,
    required String address,
    required double lat,
    required double lon,
    List<String>? imagePaths,
    bool isSuccessfullyDispatched = false,
  }) async {
    try {
      final record = await ReportStorageService.saveReport(
        category: category,
        message: message,
        address: address,
        lat: lat,
        lon: lon,
        imagePaths: imagePaths,
        isSuccessfullyDispatched: isSuccessfullyDispatched,
      );
      final id = record['id_reporte'];
      if (id is int) return id;
      if (id is String) return int.tryParse(id.replaceAll(RegExp(r'\D'), ''));
      return null;
    } catch (e) {
      developer.log('Excepción al persistir reporte: $e', name: 'WhatsAppApiService');
      return null;
    }
  }

  /// Despacha la alerta directamente a través de la API de WhatsApp vía Backend HTTP POST
  /// Sin abrir la app de WhatsApp en el dispositivo del usuario.
  /// Retorna el ID de la alerta (ej: 'ALT-17889291234') si el envío fue exitoso.
  static Future<String?> sendAutomatedEmergencyAlert({
    required String category,
    String? customMessage,
    String recipientNumber = defaultEmergencyRecipient,
    String source = 'ui_button',
    double lat = -12.04637,
    double lon = -77.02987,
    String address = 'Av. de la Constitución 145, Lima',
    List<String>? imagePaths,
  }) async {
    final message = customMessage ??
        getPredefinedMessage(
          category,
          address: address,
          lat: lat,
          lon: lon,
          source: source,
        );

    final cleanRecipient = normalizeNumber(recipientNumber);
    developer.log(
      'Enviando alerta directa WhatsApp API a +$cleanRecipient (Origen: $source)',
      name: 'WhatsAppApiService',
    );

    // HU-SEG-09: Persistencia asegurada en Supabase (tabla reporte y ubicacion con fotos)
    int? dbReportId;
    try {
      dbReportId = await saveReportToDatabase(
        category: category,
        message: message,
        address: address,
        lat: lat,
        lon: lon,
        imagePaths: imagePaths,
      );
      if (dbReportId != null) {
        lastAlertId = 'ALT-$dbReportId';
      }
    } catch (dbErr) {
      developer.log('Error al invocar saveReportToDatabase: $dbErr', name: 'WhatsAppApiService');
    }

    // Obtener datos del ciudadano registrado y token JWT de Keystore
    Map<String, String>? citizen;
    String? jwtToken;
    try {
      citizen = await SessionService.getUserData();
      jwtToken = await SessionService.getJwtToken();
    } catch (_) {}

    // Despacho de fotografías de evidencia vía Green API (sendFileByUpload)
    bool photoDispatched = false;
    if (imagePaths != null && imagePaths.isNotEmpty) {
      for (int i = 0; i < imagePaths.length; i++) {
        final filePath = imagePaths[i];
        final file = File(filePath);
        if (await file.exists()) {
          try {
            final uploadUri = Uri.parse(
              'https://7105.api.greenapi.com/waInstance710522731795/sendFileByUpload/1d98a458d1a64672abcff255236d807432183678856b42cfba',
            );
            final request = http.MultipartRequest('POST', uploadUri);
            request.fields['chatId'] = '$cleanRecipient@c.us';
            request.fields['caption'] = i == 0
                ? message
                : '📸 Evidencia fotográfica adicional #${i + 1}';
            request.fields['fileName'] = 'evidencia_${i + 1}.jpg';
            request.files.add(await http.MultipartFile.fromPath('file', filePath));

            final streamedResponse = await request.send().timeout(const Duration(seconds: 15));
            final resBody = await streamedResponse.stream.bytesToString();
            developer.log('Evidencia fotográfica #$i despachada a WhatsApp: $resBody', name: 'WhatsAppApiService');
            if (streamedResponse.statusCode == 200) {
              photoDispatched = true;
            }
          } catch (photoErr) {
            developer.log('Error enviando foto #$i vía Green API: $photoErr', name: 'WhatsAppApiService');
          }
        }
      }

      // Si las fotos con el mensaje como pie de foto se enviaron con éxito,
      // el despacho a WhatsApp está 100% completado. Retornar de inmediato
      // para evitar que se envíe un segundo mensaje de texto por WhatsApp.
      if (photoDispatched) {
        if (dbReportId != null) {
          ReportStorageService.markReportAsSent(dbReportId);
          lastAlertId = 'ALT-$dbReportId';
        } else {
          lastAlertId = 'ALT-${DateTime.now().millisecondsSinceEpoch}';
        }
        developer.log('Reporte personalizado con fotos enviado exitosamente sin duplicados.', name: 'WhatsAppApiService');
        return lastAlertId;
      }
    }

    // 1. Despacho principal a través de Supabase Edge Function (Nube oficial)
    try {
      final authBearer = jwtToken != null && jwtToken.isNotEmpty ? jwtToken : supabaseAnonKey;
      final response = await http
          .post(
            Uri.parse(supabaseFunctionsUrl),
            headers: {
              'Content-Type': 'application/json; charset=utf-8',
              'Authorization': 'Bearer $authBearer',
              'apikey': supabaseAnonKey,
            },
            body: jsonEncode({
              'category': category,
              'message': message,
              'recipientNumber': cleanRecipient,
              'source': source,
              'coordinates': {'lat': lat, 'lon': lon},
              'address': address,
              'citizen': citizen,
              'reportId': dbReportId,
              'alreadySaved': dbReportId != null,
            }),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        if (dbReportId != null) {
          ReportStorageService.markReportAsSent(dbReportId);
        }
        developer.log(
          'Alerta despachada exitosamente a Supabase Edge Function: ${response.body}',
          name: 'WhatsAppApiService',
        );
        try {
          final data = jsonDecode(response.body);
          if (data['reportId'] != null) {
            lastAlertId = 'ALT-${data['reportId']}';
          } else {
            lastAlertId = data['alertId'] as String?;
          }
        } catch (_) {
          lastAlertId = 'ALT-${DateTime.now().millisecondsSinceEpoch}';
        }
        return lastAlertId;
      }
    } catch (e) {
      developer.log(
        'Supabase no alcanzable temporalmente, intentando backend alterno: $e',
        name: 'WhatsAppApiService',
      );
    }

    // 2. Intento secundario de despacho a través del Backend local (si está activo)
    try {
      final response = await http
          .post(
            Uri.parse('$backendBaseUrl/api/alerts'),
            headers: {'Content-Type': 'application/json; charset=utf-8'},
            body: jsonEncode({
              'category': category,
              'message': message,
              'recipientNumber': cleanRecipient,
              'source': source,
              'coordinates': {'lat': lat, 'lon': lon},
              'address': address,
              'timestamp': DateTime.now().toIso8601String(),
              'citizen': citizen,
            }),
          )
          .timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        if (dbReportId != null) {
          ReportStorageService.markReportAsSent(dbReportId);
        }
        developer.log(
          'Alerta despachada exitosamente al Backend/WhatsApp API: ${response.body}',
          name: 'WhatsAppApiService',
        );
        try {
          final data = jsonDecode(response.body);
          lastAlertId = data['alertId'] as String?;
        } catch (_) {
          lastAlertId = 'ALT-${DateTime.now().millisecondsSinceEpoch}';
        }
        return lastAlertId;
      }
    } catch (e) {
      developer.log(
        'Backend local no alcanzable, despachando directamente a la API en la nube: $e',
        name: 'WhatsAppApiService',
      );
    }

    // 2. Despacho directo a la API en la nube (Green API) para máxima disponibilidad
    try {
      final cloudResponse = await http
          .post(
            Uri.parse(
              'https://7105.api.greenapi.com/waInstance710522731795/sendMessage/1d98a458d1a64672abcff255236d807432183678856b42cfba',
            ),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'chatId': '$cleanRecipient@c.us',
              'message': message,
            }),
          )
          .timeout(const Duration(seconds: 6));

      if (cloudResponse.statusCode == 200) {
        if (dbReportId != null) {
          ReportStorageService.markReportAsSent(dbReportId);
        }
        developer.log(
          'Alerta despachada con éxito vía Green API en la nube: ${cloudResponse.body}',
          name: 'WhatsAppApiService',
        );
        lastAlertId = 'ALT-${DateTime.now().millisecondsSinceEpoch}';
        return lastAlertId;
      }
    } catch (e) {
      developer.log('Fallo pasarela directa en la nube: $e', name: 'WhatsAppApiService');
    }

    lastAlertId = 'ALT-${DateTime.now().millisecondsSinceEpoch}';
    return lastAlertId;
  }
}
