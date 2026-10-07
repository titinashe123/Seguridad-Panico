import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import 'whatsapp_api_service.dart';

/// Resultado crudo de una consulta de identidad contra RENIEC.
enum ReniecLookupStatus {
  success,
  invalidFormat,
  notFound,
  unauthorized,
  rateLimited,
  networkError,
  apiError,
  notConfigured,
}

/// Identidad oficial devuelta por RENIEC (nombres y apellidos separados).
class ReniecIdentity {
  final String dni;
  final String nombres;
  final String apellidos;
  final String fullName;
  final String? dv;
  final String provider;

  const ReniecIdentity({
    required this.dni,
    required this.nombres,
    required this.apellidos,
    required this.fullName,
    this.dv,
    this.provider = 'reniec',
  });
}

class ReniecLookupResult {
  final ReniecLookupStatus status;
  final String message;
  final ReniecIdentity? identity;

  const ReniecLookupResult({
    required this.status,
    this.message = '',
    this.identity,
  });

  bool get isSuccess => status == ReniecLookupStatus.success && identity != null;
}

class _CachedIdentity {
  final ReniecIdentity identity;
  final DateTime expiresAt;

  _CachedIdentity(this.identity, this.expiresAt);
}

/// HU-IDENTIDAD-01: Consulta y contraste de identidad oficial RENIEC.
///
/// Arquitectura de consumo (en orden de prioridad):
///  1. Backend propio: Edge Function `reniec` de Supabase (el token de la API
///     nunca se expone en el cliente, cumpliendo CORS de Apis Perú).
///  2. Directo Apis Perú / Decolecta (`api.decolecta.com/v1/reniec/dni`).
///  3. Directo Apis Perú Dev (`dniruc.apisperu.com`).
///
/// Configuración de tokens (opcional, sólo si se consume en directo):
///   flutter run --dart-define=APIS_TOKEN=tu_token
///   flutter run --dart-define=APIS_DEV_TOKEN=tu_token_dev
class ReniecService {
  ReniecService._();

  /// Endpoint del backend propio (Supabase Edge Function)
  static const String _backendUrl =
      'https://emtzprcntefzkvvzmhfk.supabase.co/functions/v1/reniec';

  /// Apis Perú / Decolecta (producción)
  static const String _apisPeruUrl = 'https://api.decolecta.com/v1/reniec/dni';

  /// Apis Perú legacy (mismo token de Apis Perú)
  static const String _apisNetLegacyUrl = 'https://api.apis.net.pe/v1/dni';

  /// Apis Perú Dev (plan gratuito de pruebas)
  static const String _apisPeruDevUrl = 'https://dniruc.apisperu.com/api/v1/dni';

  static const String _apisToken = String.fromEnvironment('APIS_TOKEN');
  static const String _apisDevToken = String.fromEnvironment('APIS_DEV_TOKEN');

  static const Duration _httpTimeout = Duration(seconds: 8);
  static const Duration _cacheTtl = Duration(hours: 12);

  static final Map<String, _CachedIdentity> _cache = {};

  /// Valida el formato oficial: exactamente 8 dígitos.
  static bool isValidDniFormat(String dni) =>
      RegExp(r'^\d{8}$').hasMatch(dni.trim());

  /// Normaliza un texto para el contraste (lado API y lado usuario):
  ///  - minúsculas (.toLowerCase())
  ///  - sin tildes/acentos (á, é, í, ó, ú → vocal sin tilde)
  ///  - sin espacios sobrantes (.trim + espacios múltiples → uno solo)
  static String normalizeName(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r'[áàäâ]'), 'a')
        .replaceAll(RegExp(r'[éèëê]'), 'e')
        .replaceAll(RegExp(r'[íìïî]'), 'i')
        .replaceAll(RegExp(r'[óòöô]'), 'o')
        .replaceAll(RegExp(r'[úùüû]'), 'u')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static bool _sameWordsInOtherOrder(String a, String b) {
    final wordsA = a.split(' ')..sort();
    final wordsB = b.split(' ')..sort();
    return wordsA.join(' ') == wordsB.join(' ') && a != b;
  }

  /// Contraste de validación ciega: compara lo digitado por el ciudadano
  /// contra los datos de RENIEC SIN mostrarlos ni copiarlos al formulario.
  ///
  /// Ambos textos se normalizan antes de comparar (minúsculas, sin tildes,
  /// espacios colapsados) para que mayúsculas o espacios accidentales no
  /// bloqueen el registro. Las discrepancias reales (letras de más, errores
  /// tipográficos) siguen bloqueando.
  ///
  /// Emite un log con exactamente lo que devuelve la API frente a lo que
  /// escribió el usuario para depurar desfases de orden de apellidos.
  static bool matchesIdentity({
    required ReniecIdentity identity,
    String? nombres,
    String? apellidos,
  }) {
    final apiNombres = normalizeName(identity.nombres);
    final apiApellidos = normalizeName(identity.apellidos);
    final userNombres = normalizeName(nombres ?? '');
    final userApellidos = normalizeName(apellidos ?? '');

    if (userNombres.isEmpty ||
        userApellidos.isEmpty ||
        apiNombres.isEmpty ||
        apiApellidos.isEmpty) {
      developer.log(
        'RENIEC contraste INCOMPLETO | API="${identity.nombres} / ${identity.apellidos}" | '
        'USUARIO="${nombres ?? ''} / ${apellidos ?? ''}"',
        name: 'ReniecValidation',
      );
      return false;
    }

    final match =
        userNombres == apiNombres && userApellidos == apiApellidos;

    // Log de depuración: respuesta oficial vs digitación del ciudadano
    developer.log(
      'RENIEC API="${identity.nombres} / ${identity.apellidos}" '
      '(normalizado="$apiNombres / $apiApellidos") || '
      'USUARIO="${nombres ?? ''} / ${apellidos ?? ''}" '
      '(normalizado="$userNombres / $userApellidos") || coincide=$match',
      name: 'ReniecValidation',
    );

    if (!match &&
        userNombres == apiNombres &&
        _sameWordsInOtherOrder(userApellidos, apiApellidos)) {
      developer.log(
        'RENIEC ALERTA: apellidos con las mismas palabras en distinto orden '
        '(¿apellido paterno y materno invertidos?) API="$apiApellidos" USUARIO="$userApellidos"',
        name: 'ReniecValidation',
      );
    }

    return match;
  }

  /// Consulta la identidad oficial de un DNI (con caché local de 12 horas).
  static Future<ReniecLookupResult> lookup(String dni) async {
    final clean = dni.trim();
    if (!isValidDniFormat(clean)) {
      return const ReniecLookupResult(
        status: ReniecLookupStatus.invalidFormat,
        message: 'DNI inválido: debe contener exactamente 8 dígitos.',
      );
    }

    final cached = _cache[clean];
    if (cached != null && DateTime.now().isBefore(cached.expiresAt)) {
      return ReniecLookupResult(
        status: ReniecLookupStatus.success,
        identity: cached.identity,
        message: 'Identidad verificada con RENIEC.',
      );
    }

    ReniecLookupResult lastFailure = const ReniecLookupResult(
      status: ReniecLookupStatus.apiError,
      message: 'No se pudo consultar RENIEC. Intente nuevamente.',
    );

    // 1. Backend propio (evita exponer el token y resuelve CORS en web)
    final backendResult = await _lookupViaBackend(clean);
    if (backendResult != null) {
      if (backendResult.isSuccess) return _cacheAndReturn(backendResult);
      lastFailure = backendResult;
      if (backendResult.status == ReniecLookupStatus.notFound ||
          backendResult.status == ReniecLookupStatus.invalidFormat) {
        return backendResult;
      }
    }

    // 2. Apis Perú / Decolecta en directo
    if (_apisToken.isNotEmpty) {
      final res = await _lookupDirect(
        dni: clean,
        url: '$_apisPeruUrl?numero=$clean',
        token: _apisToken,
        provider: 'apis_peru',
      );
      if (res.isSuccess) return _cacheAndReturn(res);
      lastFailure = res;
      if (res.status == ReniecLookupStatus.notFound) return res;
    }

    // 3. Apis Perú legacy (funciona sin token, con cuota anónima limitada)
    final resLegacy = await _lookupDirect(
      dni: clean,
      url: '$_apisNetLegacyUrl?numero=$clean',
      token: _apisToken,
      provider: 'apis_net',
    );
    if (resLegacy.isSuccess) return _cacheAndReturn(resLegacy);
    lastFailure = resLegacy;
    if (resLegacy.status == ReniecLookupStatus.notFound) return resLegacy;

    // 4. Apis Perú Dev (pruebas)
    if (_apisDevToken.isNotEmpty) {
      final res = await _lookupDirect(
        dni: clean,
        url: '$_apisPeruDevUrl/$clean?token=$_apisDevToken',
        token: '',
        provider: 'apis_peru_dev',
        useQueryToken: true,
      );
      if (res.isSuccess) return _cacheAndReturn(res);
      lastFailure = res;
      if (res.status == ReniecLookupStatus.notFound) return res;
    }

    return lastFailure;
  }

  static ReniecLookupResult _cacheAndReturn(ReniecLookupResult result) {
    final identity = result.identity;
    if (identity != null) {
      _cache[identity.dni] =
          _CachedIdentity(identity, DateTime.now().add(_cacheTtl));
    }
    return result;
  }

  static Future<ReniecLookupResult?> _lookupViaBackend(String dni) async {
    try {
      final response = await http
          .get(
            Uri.parse('$_backendUrl?dni=$dni'),
            headers: {
              'Content-Type': 'application/json',
              'apikey': WhatsAppApiService.supabaseAnonKey,
              'Authorization': 'Bearer ${WhatsAppApiService.supabaseAnonKey}',
            },
          )
          .timeout(_httpTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final identity = _parseIdentity(data, dni: dni, provider: 'backend');
        if (identity != null) {
          return ReniecLookupResult(
            status: ReniecLookupStatus.success,
            identity: identity,
            message: 'Identidad verificada con RENIEC.',
          );
        }
        return const ReniecLookupResult(
          status: ReniecLookupStatus.apiError,
          message: 'Respuesta inválida del servicio de identidad.',
        );
      }

      if (response.statusCode == 404) {
        return const ReniecLookupResult(
          status: ReniecLookupStatus.notFound,
          message: 'El DNI no existe en los registros de RENIEC.',
        );
      }
      if (response.statusCode == 400) {
        return const ReniecLookupResult(
          status: ReniecLookupStatus.invalidFormat,
          message: 'DNI inválido para consulta RENIEC.',
        );
      }
      if (response.statusCode == 429) {
        return const ReniecLookupResult(
          status: ReniecLookupStatus.rateLimited,
          message: 'Demasiadas consultas. Espere unos segundos e intente de nuevo.',
        );
      }
      if (response.statusCode == 503) {
        return const ReniecLookupResult(
          status: ReniecLookupStatus.notConfigured,
          message: 'El servicio de identidad no tiene un token de API configurado.',
        );
      }

      developer.log('Edge Function reniec respondió ${response.statusCode}',
          name: 'ReniecService');
      return null;
    } catch (e) {
      developer.log('Edge Function reniec inaccesible: $e', name: 'ReniecService');
      return null;
    }
  }

  static Future<ReniecLookupResult> _lookupDirect({
    required String dni,
    required String url,
    required String token,
    required String provider,
    bool useQueryToken = false,
  }) async {
    try {
      final headers = <String, String>{'Accept': 'application/json'};
      if (!useQueryToken && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }

      final response = await http.get(Uri.parse(url), headers: headers).timeout(_httpTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final identity = _parseIdentity(data, dni: dni, provider: provider);
        if (identity != null) {
          return ReniecLookupResult(
            status: ReniecLookupStatus.success,
            identity: identity,
            message: 'Identidad verificada con RENIEC.',
          );
        }
        return const ReniecLookupResult(
          status: ReniecLookupStatus.apiError,
          message: 'Respuesta inválida del proveedor de identidad.',
        );
      }

      if (response.statusCode == 401 || response.statusCode == 403) {
        return const ReniecLookupResult(
          status: ReniecLookupStatus.unauthorized,
          message: 'Token de API de identidad inválido o expirado.',
        );
      }
      if (response.statusCode == 404 || response.statusCode == 410) {
        return const ReniecLookupResult(
          status: ReniecLookupStatus.notFound,
          message: 'El DNI no existe en los registros de RENIEC.',
        );
      }
      if (response.statusCode == 429) {
        return const ReniecLookupResult(
          status: ReniecLookupStatus.rateLimited,
          message: 'Demasiadas consultas. Espere unos segundos e intente de nuevo.',
        );
      }

      return ReniecLookupResult(
        status: ReniecLookupStatus.apiError,
        message: 'El proveedor de identidad respondió ${response.statusCode}.',
      );
    } on http.ClientException catch (e) {
      developer.log('Error de red consultando RENIEC ($provider): $e',
          name: 'ReniecService');
      return const ReniecLookupResult(
        status: ReniecLookupStatus.networkError,
        message: 'Sin conexión con el servicio de identidad. Verifique su red.',
      );
    } on TimeoutException {
      return const ReniecLookupResult(
        status: ReniecLookupStatus.networkError,
        message: 'La consulta a RENIEC tardó demasiado. Intente nuevamente.',
      );
    } catch (e) {
      developer.log('Error consultando RENIEC ($provider): $e',
          name: 'ReniecService');
      return const ReniecLookupResult(
        status: ReniecLookupStatus.networkError,
        message: 'No se pudo consultar RENIEC. Verifique su conexión.',
      );
    }
  }

  /// Acepta todas las variantes de respuesta de los proveedores:
  /// - Decolecta/Apis Perú: first_name, first_last_name, second_last_name, full_name
  /// - Apis Perú Dev / peru-consult: nombres, apellidoPaterno, apellidoMaterno
  /// - Backend propio: dni, nombres, apellidos, fullName, dv
  static ReniecIdentity? _parseIdentity(
    dynamic raw, {
    required String dni,
    required String provider,
  }) {
    if (raw is! Map) return null;
    final data = raw is Map<String, dynamic> ? raw : Map<String, dynamic>.from(raw);

    String pick(List<String> keys) {
      for (final key in keys) {
        final value = data[key];
        if (value is String && value.trim().isNotEmpty) return value.trim();
      }
      return '';
    }

    var nombres = pick([
      'nombres',
      'first_name',
      'firstName',
      'firstNames',
    ]);

    var apellidos = pick([
      'apellidos',
      'apellido_paterno',
      'apellidoPaterno',
      'first_last_name',
      'apellido',
    ]);
    final apellidoMaterno = pick([
      'apellido_materno',
      'apellidoMaterno',
      'second_last_name',
    ]);
    if (apellidoMaterno.isNotEmpty && !apellidos.contains(apellidoMaterno)) {
      apellidos = apellidos.isEmpty
          ? apellidoMaterno
          : '$apellidos $apellidoMaterno'.trim();
    }

    final fullName = pick(['full_name', 'fullName', 'nombre_completo', 'nombreCompleto']);

    // Fallback: proveedor que sólo devuelve el nombre completo en un campo.
    // full_name (Decolecta): "AP_PAT AP_MAT NOMBRES"
    // nombre    (Apis Perú): "NOMBRES APELLIDO_PAT APELLIDO_MAT"
    if (nombres.isEmpty && apellidos.isEmpty) {
      final combinedSource = fullName.isNotEmpty ? fullName : pick(['nombre']);
      if (combinedSource.isNotEmpty) {
        final words = combinedSource.split(RegExp(r'\s+'));
        if (words.length >= 3) {
          if (fullName.isNotEmpty) {
            apellidos = '${words[0]} ${words[1]}';
            nombres = words.sublist(2).join(' ');
          } else {
            nombres = words.sublist(0, words.length - 2).join(' ');
            apellidos = words.sublist(words.length - 2).join(' ');
          }
        } else {
          nombres = combinedSource;
        }
      }
    }

    if (nombres.isEmpty && apellidos.isEmpty && fullName.isEmpty) return null;

    final resolvedFullName = fullName.isNotEmpty
        ? fullName
        : '$nombres $apellidos'.trim();

    final resolvedDni = pick(['dni', 'document_number', 'numero', 'numeroDocumento']);
    final dvValue = pick(['dv', 'codVerifica', 'codigoVerificacion']);
    final providerValue = pick(['provider']);

    return ReniecIdentity(
      dni: resolvedDni.isNotEmpty ? resolvedDni : dni,
      nombres: nombres.trim(),
      apellidos: apellidos.trim(),
      fullName: resolvedFullName.trim(),
      dv: dvValue.isEmpty ? null : dvValue,
      provider: providerValue.isNotEmpty ? providerValue : provider,
    );
  }

  /// Invalida la caché (útil tras un registro o en pruebas).
  static void clearCache() => _cache.clear();
}
