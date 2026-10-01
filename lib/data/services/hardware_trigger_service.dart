import 'dart:developer' as developer;
import 'package:flutter/services.dart';

typedef HardwareTriggerCallback = void Function(String source);
typedef StopTrackingDialogCallback = void Function();

/// Servicio que interactúa con la capa nativa de Android para:
/// 1. Recibir activación de emergencia por 3 pulsaciones del botón de encendido.
/// 2. Controlar el servicio en primer plano persistente en segundo plano (Foreground Service).
/// 3. Gestionar la notificación interactiva de rastreo en vivo y apertura de diálogo de PIN.
class HardwareTriggerService {
  static final HardwareTriggerService _instance = HardwareTriggerService._internal();
  factory HardwareTriggerService() => _instance;
  HardwareTriggerService._internal();

  static const MethodChannel _channel = MethodChannel('com.alertaciudadana/hardware_trigger');

  HardwareTriggerCallback? _onHardwareTriggered;
  StopTrackingDialogCallback? _onOpenStopTrackingDialog;
  bool _initialized = false;

  void initialize({
    required HardwareTriggerCallback onTriggered,
    StopTrackingDialogCallback? onOpenStopTrackingDialog,
  }) {
    _onHardwareTriggered = onTriggered;
    if (onOpenStopTrackingDialog != null) {
      _onOpenStopTrackingDialog = onOpenStopTrackingDialog;
    }

    if (_initialized) return;
    _initialized = true;

    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onPanicTriggered':
          final Map? args = call.arguments as Map?;
          final String source = args?['source'] as String? ?? 'power_button_3x';
          developer.log('🚨 DISPARO NATIVO BOTÓN DE ENCENDIDO (3x): $source', name: 'HardwareTriggerService');
          _onHardwareTriggered?.call(source);
          break;

        case 'onOpenStopTrackingDialog':
          developer.log('🛑 SOLICITUD DESDE NOTIFICACIÓN: Abrir diálogo de PIN para detener rastreo', name: 'HardwareTriggerService');
          _onOpenStopTrackingDialog?.call();
          break;
      }
    });

    // Iniciar automáticamente el servicio persistente en Android
    startBackgroundService();
    developer.log('Canal de disparador por hardware y segundo plano inicializado', name: 'HardwareTriggerService');
  }

  void setStopTrackingDialogCallback(StopTrackingDialogCallback callback) {
    _onOpenStopTrackingDialog = callback;
  }

  /// Inicia el servicio persistente en primer plano de Android
  Future<void> startBackgroundService() async {
    try {
      await _channel.invokeMethod('startBackgroundService');
    } catch (e) {
      developer.log('Plataforma no nativa Android o error al iniciar servicio: $e', name: 'HardwareTriggerService');
    }
  }

  /// Detiene el servicio persistente en Android
  Future<void> stopBackgroundService() async {
    try {
      await _channel.invokeMethod('stopBackgroundService');
    } catch (e) {
      developer.log('Error al detener servicio: $e', name: 'HardwareTriggerService');
    }
  }

  /// Actualiza la barra de notificaciones según si hay rastreo en vivo de ROBO activo
  Future<void> updateLiveTrackingNotification(bool isTracking) async {
    try {
      await _channel.invokeMethod('updateLiveTrackingNotification', {'isTracking': isTracking});
    } catch (e) {
      developer.log('Error al actualizar notificación de rastreo en vivo: $e', name: 'HardwareTriggerService');
    }
  }

  /// Permite simular las 3 pulsaciones del botón de encendido para pruebas rápidas
  Future<void> simulatePowerButtonTriplePress() async {
    try {
      await _channel.invokeMethod('simulatePowerPress3x');
    } catch (_) {
      // Fallback para entornos donde el canal nativo de Android no está presente (ej. Web)
      _onHardwareTriggered?.call('power_button_3x_simulado');
    }
  }
}
