import 'dart:developer' as developer;

/// Servicio para el envío automatizado de alertas vía WhatsApp API
/// con mensajes predefinidos según la categoría de emergencia.
class WhatsAppApiService {
  static String getPredefinedMessage(
    String category, {
    String address = 'Av. de la Constitución 145',
    double lat = -12.04637,
    double lon = -77.02987,
  }) {
    final catNormalized = category.trim().toUpperCase();

    String headline;
    switch (catNormalized) {
      case 'ROBO':
        headline = '🚨 ¡AUXILIO! ME ESTÁN ROBANDO 🚨';
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
        headline = '⚠️ ¡ALERTA DE SEGURIDAD PERSONALIZADA! ⚠️';
        break;
      default:
        headline = '🚨 ¡ALERTA DE EMERGENCIA CIUDADANA: $catNormalized! 🚨';
        break;
    }

    return '$headline\n'
        '📍 Ubicación: $address\n'
        '🛰️ Coordenadas: Lat ${lat.toStringAsFixed(5)}, Lon ${lon.toStringAsFixed(5)}\n'
        '🛡️ Despacho automático encriptado - Central de Seguridad Móvil.';
  }

  /// Despacha la alerta a través del endpoint de la API de WhatsApp
  static Future<bool> sendAutomatedEmergencyAlert({
    required String category,
    String? customMessage,
    String recipientNumber = '+51999999999',
  }) async {
    try {
      final message = customMessage ?? getPredefinedMessage(category);

      developer.log('Despachando alerta automática [$category] vía WhatsApp API a $recipientNumber');
      developer.log('Contenido: $message');

      // Simulación de llamada HTTP POST al servicio de WhatsApp Cloud API / Gateway
      // await http.post(Uri.parse('https://graph.facebook.com/v20.0/YOUR_PHONE_ID/messages'), ...);
      await Future.delayed(const Duration(milliseconds: 400));

      developer.log('Alerta de $category despachada con éxito vía WhatsApp API');
      return true;
    } catch (e) {
      developer.log('Error al enviar alerta WhatsApp API: $e');
      return false;
    }
  }
}
