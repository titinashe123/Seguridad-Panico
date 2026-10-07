import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'session_service.dart';

/// Servicio central para el bloqueo de seguridad por inactividad / segundo plano.
/// Mantiene la sesión del ciudadano siempre abierta (token, datos y monitoreo activos),
/// pero bloquea visualmente la interfaz exigiendo huella digital o PIN secreto de 4 dígitos
/// cada vez que el usuario sale de la aplicación y vuelve a entrar.
class AppLockService {
  static final AppLockService _instance = AppLockService._internal();
  factory AppLockService() => _instance;
  AppLockService._internal();

  /// Notificador observable para determinar si la aplicación está bloqueada
  final ValueNotifier<bool> isLockedNotifier = ValueNotifier<bool>(false);

  bool get isLocked => isLockedNotifier.value;

  /// Bandera para evitar que el diálogo nativo biométrico del sistema
  /// (que produce eventos pause/resume transitorios en Android) provoque un bucle de bloqueo.
  bool isAuthenticatingBiometrics = false;

  /// Bandera para evitar bloquear la app en el instante en que el usuario
  /// acaba de iniciar sesión o registrarse desde LoginView.
  bool justLoggedIn = false;

  DateTime? _pausedAt;

  /// Inicializa el estado de bloqueo al encender la app (cold start)
  Future<void> initOnLaunch({required bool isLoggedIn}) async {
    if (isLoggedIn) {
      developer.log('App iniciada con sesión activa previa: activando pantalla de bloqueo.', name: 'AppLockService');
      isLockedNotifier.value = true;
    } else {
      isLockedNotifier.value = false;
    }
  }

  /// Desbloquea la interfaz tras validación exitosa de huella o PIN
  void unlock() {
    developer.log('Desbloqueo de seguridad completado exitosamente', name: 'AppLockService');
    isLockedNotifier.value = false;
    _pausedAt = null;
  }

  /// Marca que el usuario acaba de iniciar sesión con credenciales
  void markJustLoggedIn() {
    justLoggedIn = true;
    isLockedNotifier.value = false;
    _pausedAt = null;
    Future.delayed(const Duration(seconds: 4), () {
      justLoggedIn = false;
    });
  }

  /// Se ejecuta cuando la aplicación pasa a segundo plano o se bloquea la pantalla
  void onAppPaused() {
    if (isAuthenticatingBiometrics) return;
    _pausedAt = DateTime.now();
  }

  /// Se ejecuta cuando la aplicación regresa a primer plano
  Future<void> onAppResumed() async {
    if (isAuthenticatingBiometrics) return;
    if (justLoggedIn) return;

    final loggedIn = await SessionService.isLoggedIn();
    if (!loggedIn) {
      isLockedNotifier.value = false;
      return;
    }

    if (_pausedAt != null) {
      final elapsed = DateTime.now().difference(_pausedAt!);
      // Si la app estuvo en segundo plano más de 600ms, exigir autenticación
      if (elapsed.inMilliseconds > 600) {
        developer.log('App reanudada tras ${elapsed.inMilliseconds}ms en segundo plano: activando bloqueo de seguridad.', name: 'AppLockService');
        isLockedNotifier.value = true;
      }
    }
    _pausedAt = null;
  }

  /// Desactiva el bloqueo si se cierra la sesión intencionalmente
  void onLogout() {
    isLockedNotifier.value = false;
    justLoggedIn = false;
    _pausedAt = null;
  }
}
