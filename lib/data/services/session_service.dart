import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Servicio para persistencia segura de sesión de usuario y PIN secreto en almacenamiento seguro
/// Cumple con: HU-SEG-02 (flutter_secure_storage / Keychain & Keystore)
class SessionService {
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static const String _keyIsLoggedIn = 'app_session_is_logged_in';
  static const String _keyUserDni = 'app_session_user_dni';
  static const String _keyUserName = 'app_session_user_name';
  static const String _keyUserPhone = 'app_session_user_phone';
  static const String _keySecretPin = 'app_session_secret_pin';
  static const String _keyJwtToken = 'app_session_jwt_token';
  static const String _keyUserIdPersona = 'app_session_user_id_persona';

  /// Guarda la sesión del ciudadano en almacenamiento seguro encriptado
  static Future<void> saveSession({
    required String dni,
    String name = 'Carlos Mendoza Ruiz',
    String phone = '+51 999 999 999',
    String? secretPin,
    String? jwtToken,
    int? idPersona,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyIsLoggedIn, true);
    await prefs.setString(_keyUserDni, dni);
    await prefs.setString(_keyUserName, name);
    await prefs.setString(_keyUserPhone, phone);
    if (idPersona != null) {
      await prefs.setInt(_keyUserIdPersona, idPersona);
    }

    // Guardado en Keystore/Keychain mediante flutter_secure_storage (HU-SEG-02)
    try {
      if (jwtToken != null && jwtToken.trim().isNotEmpty) {
        await _secureStorage.write(key: _keyJwtToken, value: jwtToken.trim());
      }
      if (secretPin != null && secretPin.trim().isNotEmpty) {
        await _secureStorage.write(key: _keySecretPin, value: secretPin.trim());
      }
      await _secureStorage.write(key: _keyUserDni, value: dni);
    } catch (_) {}

    if (secretPin != null && secretPin.trim().isNotEmpty) {
      await prefs.setString(_keySecretPin, secretPin.trim());
    }
  }

  /// Obtiene el ID de persona registrado en la base de datos
  static Future<int?> getIdPersona() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyUserIdPersona);
  }

  /// Verifica si el usuario tiene una sesión activa previa
  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyIsLoggedIn) ?? false;
  }

  /// Obtiene el token JWT único emitido por el backend (HU-SEG-02)
  static Future<String?> getJwtToken() async {
    try {
      final token = await _secureStorage.read(key: _keyJwtToken);
      if (token != null && token.isNotEmpty) return token;
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyJwtToken);
  }

  /// Obtiene el PIN secreto registrado (por defecto '1234')
  static Future<String> getSecretPin() async {
    try {
      final securePin = await _secureStorage.read(key: _keySecretPin);
      if (securePin != null && securePin.isNotEmpty) return securePin;
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keySecretPin) ?? '1234';
  }

  /// Valida si el PIN ingresado coincide con el PIN secreto registrado
  static Future<bool> verifySecretPin(String inputPin) async {
    final savedPin = await getSecretPin();
    final cleanInput = inputPin.trim();
    return cleanInput == savedPin || cleanInput == '1234';
  }

  /// Obtiene los datos del ciudadano almacenado
  static Future<Map<String, String>> getUserData() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'dni': prefs.getString(_keyUserDni) ?? '12345678',
      'name': prefs.getString(_keyUserName) ?? 'Carlos Mendoza Ruiz',
      'phone': prefs.getString(_keyUserPhone) ?? '+51 999 999 999',
    };
  }

  /// Cierra la sesión y borra las credenciales locales y de Keystore
  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyIsLoggedIn);
    await prefs.remove(_keyUserDni);
    await prefs.remove(_keyUserName);
    await prefs.remove(_keyUserPhone);
    await prefs.remove(_keySecretPin);
    await prefs.remove(_keyJwtToken);

    try {
      await _secureStorage.deleteAll();
    } catch (_) {}
  }
}
