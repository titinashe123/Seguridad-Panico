import 'dart:developer' as developer;
import 'package:flutter/services.dart';

typedef HardwareTriggerCallback = void Function(String source, [String? alertType]);
typedef StopTrackingDialogCallback = void Function();

/// Servicio que interactúa con la capa nativa de Android para:
/// 1. Recibir activación de emergencia por 3 pulsaciones del botón de encendido o impacto físico en segundo plano.
/// 2. Controlar el servicio en primer plano persistente en segundo plano (Foreground Service).
/// 3. Gestionar la notificación interactiva de rastreo en vivo y apertura de diálogo de PIN.
/// 4. Recuperar activaciones de emergencia ocurridas mientras la app estaba completamente cerrada (arranque en frío).
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

    if (_initialized) {
      // Si ya estaba inicializado pero se volvió a vincular la UI, revisar si hay disparos pendientes
      checkPendingTriggers();
      return;
    }
    _initialized = true;

    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onPanicTriggered':
          final Map? args = call.arguments as Map?;
          final String source = args?['source'] as String? ?? 'power_button_3x';
          final String? alertType = args?['alertType'] as String?;
          developer.log('🚨 DISPARO NATIVO DE EMERGENCIA: $source ($alertType)', name: 'HardwareTriggerService');
          _onHardwareTriggered?.call(source, alertType);
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

    // Verificar si la app fue abierta debido a una emergencia pendiente (arranque desde app cerrada)
    checkPendingTriggers();
  }

  /// Verifica si la actividad nativa fue despertada por una emergencia pendiente mientras Flutter cargaba
  Future<void> checkPendingTriggers() async {
    try {
      final Map? pending = await _channel.invokeMapMethod('checkPendingTrigger');
      if (pending != null && pending['hasPending'] == true) {
        final String source = pending['source'] as String? ?? 'power_button_3x';
        final String? alertType = pending['alertType'] as String?;
        developer.log('🚨 DISPARO PENDIENTE AL ABRIR LA APP: $source ($alertType)', name: 'HardwareTriggerService');
        // Pequeño delay para asegurar que el widget esté montado en el árbol
        Future.delayed(const Duration(milliseconds: 350), () {
          _onHardwareTriggered?.call(source, alertType);
        });
      }
    } catch (e) {
      developer.log('Error al verificar disparo pendiente: $e', name: 'HardwareTriggerService');
    }

    try {
      final bool? pendingStop = await _channel.invokeMethod<bool>('checkPendingStopTracking');
      if (pendingStop == true) {
        Future.delayed(const Duration(milliseconds: 350), () {
          _onOpenStopTrackingDialog?.call();
        });
      }
    } catch (_) {}
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
