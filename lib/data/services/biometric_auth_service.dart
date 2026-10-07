import 'dart:developer' as developer;
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Servicio de Autenticación Biométrica (Huella Digital / Biometría Facial)
/// Permite inicio de sesión rápido y cancelación de alertas sin digitar PIN
class BiometricAuthService {
  static final LocalAuthentication _localAuth = LocalAuthentication();
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static const String _keyBiometricsEnabled = 'app_biometrics_enabled_pref';
  static const String _keyEnrolledDni = 'app_biometric_enrolled_dni';

  /// Obtiene el DNI que fue vinculado legítimamente con contraseña a este dispositivo
  static Future<String?> getEnrolledDni() async {
    try {
      final secureDni = await _secureStorage.read(key: _keyEnrolledDni);
      if (secureDni != null && secureDni.isNotEmpty) {
        return secureDni.trim();
      }
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyEnrolledDni);
  }

  /// Vincula un DNI a la biometría del dispositivo tras una autenticación exitosa con contraseña
  static Future<void> enrollUser({required String dni}) async {
    final cleanDni = dni.trim();
    if (cleanDni.isEmpty) return;

    try {
      await _secureStorage.write(key: _keyEnrolledDni, value: cleanDni);
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyEnrolledDni, cleanDni);
  }

  /// Elimina la vinculación biométrica del dispositivo
  static Future<void> removeEnrollment() async {
    try {
      await _secureStorage.delete(key: _keyEnrolledDni);
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyEnrolledDni);
  }

  /// Verifica si el DNI proporcionado es el único autorizado para ingresar con biometría
  static Future<bool> isUserEnrolledForBiometrics(String dni) async {
    final cleanDni = dni.trim();
    if (cleanDni.isEmpty) return false;
    final enrolled = await getEnrolledDni();
    return enrolled != null && enrolled.isNotEmpty && enrolled == cleanDni;
  }

  /// Verifica si el hardware del dispositivo tiene lector biométrico y si el dispositivo es compatible
  static Future<bool> isHardwareAvailable() async {
    try {
      final isSupported = await _localAuth.isDeviceSupported();
      final canCheck = await _localAuth.canCheckBiometrics;
      return isSupported && canCheck;
    } on PlatformException catch (e) {
      developer.log('Error verificando hardware biométrico: $e', name: 'BiometricAuth');
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Verifica si el usuario tiene al menos una huella o biometría registrada en su teléfono
  static Future<bool> hasEnrolledBiometrics() async {
    try {
      final availableBiometrics = await _localAuth.getAvailableBiometrics();
      return availableBiometrics.isNotEmpty;
    } on PlatformException catch (e) {
      developer.log('Error verificando biometrías enroladas: $e', name: 'BiometricAuth');
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Retorna si la biometría está completamente disponible para usarse en este dispositivo
  static Future<bool> isBiometricsReady() async {
    final available = await isHardwareAvailable();
    if (!available) return false;
    final enrolled = await hasEnrolledBiometrics();
    return enrolled;
  }

  /// Retorna si el usuario tiene habilitado el uso de huella digital en los ajustes de la aplicación
  static Future<bool> isBiometricsEnabled() async {
    final isReady = await isBiometricsReady();
    if (!isReady) return false;

    final prefs = await SharedPreferences.getInstance();
    // Por defecto habilitado si el dispositivo cuenta con biometría
    return prefs.getBool(_keyBiometricsEnabled) ?? true;
  }

  /// Activa o desactiva la preferencia del usuario para usar huella digital
  static Future<void> setBiometricsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyBiometricsEnabled, enabled);
  }

  /// Ejecuta el diálogo nativo de verificación de huella digital del sistema operativo
  static Future<bool> authenticate({
    String reason = 'Coloca tu huella digital para verificar tu identidad',
  }) async {
    try {
      final isReady = await isBiometricsReady();
      if (!isReady) return false;

      final bool didAuthenticate = await _localAuth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );

      return didAuthenticate;
    } on PlatformException catch (e) {
      developer.log('Error durante autenticación biométrica: ${e.code} - ${e.message}', name: 'BiometricAuth');
      return false;
    } catch (e) {
      developer.log('Error inesperado en biometría: $e', name: 'BiometricAuth');
      return false;
    }
  }

  /// Obtiene los tipos de biometría disponibles (Huella dactilar, Rostro, etc.)
  static Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _localAuth.getAvailableBiometrics();
    } catch (_) {
      return [];
    }
  }
}
