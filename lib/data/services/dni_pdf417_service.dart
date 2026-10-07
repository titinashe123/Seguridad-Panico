import 'dart:developer' as developer;

/// Datos parseados del código PDF417 impreso en el reverso del DNI peruano.
///
/// Estructura preparada para la integración futura de una librería de
/// escaneo/decodificación PDF417 (ver `pubspec.yaml`, sección opcional):
///  1. `mobile_scanner` (ML Kit) decodifica el código PDF417 con la cámara.
///  2. El payload devuelto se pasa a [DniPdf417Service.tryParse].
///  3. El formulario de registro rellena DNI / NOMBRES / APELLIDOS con
///     [DniPdf417Data.toFormValues] y dispara la consulta RENIEC.
class DniPdf417Data {
  final String? numeroDocumento;
  final String? nombres;
  final String? apellidos;
  final String? fechaNacimiento;
  final String? sexo;
  final String? pais;
  final String raw;

  const DniPdf417Data({
    this.numeroDocumento,
    this.nombres,
    this.apellidos,
    this.fechaNacimiento,
    this.sexo,
    this.pais,
    required this.raw,
  });

  bool get hasIdentity =>
      (numeroDocumento?.isNotEmpty ?? false) &&
      (nombres?.isNotEmpty ?? false) &&
      (apellidos?.isNotEmpty ?? false);

  Map<String, String> toFormValues() => {
        'dni': numeroDocumento ?? '',
        'nombres': nombres ?? '',
        'apellidos': apellidos ?? '',
        'fechaNacimiento': fechaNacimiento ?? '',
        'sexo': sexo ?? '',
      };

  @override
  String toString() =>
      'DniPdf417Data(dni: $numeroDocumento, nombres: $nombres, apellidos: $apellidos)';
}

class DniPdf417Service {
  DniPdf417Service._();

  /// Claves reconocidas en el payload cuando viene en formato
  /// `clave=valor`, `clave:valor` o `<clave>valor`.
  static const Map<String, String> _keyAliases = {
    'dni': 'numeroDocumento',
    'numdoc': 'numeroDocumento',
    'numero': 'numeroDocumento',
    'documentnumber': 'numeroDocumento',
    'document_number': 'numeroDocumento',
    'nombres': 'nombres',
    'nombrescompletos': 'nombres',
    'firstname': 'nombres',
    'first_name': 'nombres',
    'apellidos': 'apellidos',
    'apellidopaterno': 'apellidos',
    'apellido_paterno': 'apellidos',
    'first_last_name': 'apellidos',
    'fechanacimiento': 'fechaNacimiento',
    'fecha_nacimiento': 'fechaNacimiento',
    'birthdate': 'fechaNacimiento',
    'sexo': 'sexo',
    'sex': 'sexo',
    'genero': 'sexo',
    'pais': 'pais',
    'country': 'pais',
  };

  /// Intenta parsear el payload crudo del PDF417 del reverso del DNI.
  ///
  /// Soporta:
  ///  - Formato `clave=valor` / `clave:valor` / `<clave>valor` (preferente).
  ///  - Formato delimitado por `|`, `;`, tabulador o salto de línea
  ///    con orden estándar: TIPO | DNI | APELLIDOS | NOMBRES | FECHA | SEXO
  ///
  /// Devuelve `null` si el payload no puede interpretarse.
  static DniPdf417Data? tryParse(String? payload) {
    if (payload == null || payload.trim().isEmpty) return null;
    final raw = payload.trim();

    final keyValue = _parseKeyValue(raw);
    if (keyValue != null && keyValue.numeroDocumento != null) return keyValue;

    final delimited = _parseDelimited(raw);
    if (delimited != null && delimited.numeroDocumento != null) return delimited;

    developer.log('Payload PDF417 no reconocido', name: 'DniPdf417Service');
    return null;
  }

  static DniPdf417Data? _parseKeyValue(String raw) {
    final result = <String, String>{};

    // <clave>valor  |  clave=valor  |  clave:valor
    final patterns = [
      RegExp(r'<([a-zA-Z_]+)>\s*([^<\r\n]+)'),
      RegExp(r'([a-zA-Z_]{2,})\s*[=:]\s*([^;|\r\n]+)'),
    ];

    for (final pattern in patterns) {
      for (final match in pattern.allMatches(raw)) {
        final key = match.group(1)!.toLowerCase().replaceAll(RegExp(r'[\s-]+'), '');
        final field = _keyAliases[key];
        if (field != null && result[field] == null) {
          result[field] = match.group(2)!.trim();
        }
      }
    }

    if (result.isEmpty) return null;

    final dni = _sanitizeDni(result['numeroDocumento']) ??
        _sanitizeDni(raw); // último recurso: primeros 8 dígitos del payload

    return DniPdf417Data(
      numeroDocumento: dni,
      nombres: _clean(result['nombres']),
      apellidos: _clean(result['apellidos']),
      fechaNacimiento: _clean(result['fechaNacimiento']),
      sexo: _clean(result['sexo']),
      pais: _clean(result['pais']),
      raw: raw,
    );
  }

  static DniPdf417Data? _parseDelimited(String raw) {
    if (!raw.contains(RegExp(r'[|;\t\n]'))) return null;

    final tokens = raw
        .split(RegExp(r'[|;\t\n]'))
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    if (tokens.length < 3) return null;

    String? dni;
    String? fecha;
    String? sexo;
    final words = <String>[];

    for (final token in tokens) {
      final sanitized = _sanitizeDni(token);
      if (sanitized != null && dni == null && token.replaceAll(RegExp(r'\D'), '').length == 8) {
        dni = sanitized;
      } else if (RegExp(r'^\d{2}[/-]\d{2}[/-]\d{2,4}$').hasMatch(token)) {
        fecha = token;
      } else if (token.length == 1 && RegExp(r'^[MF]$').hasMatch(token.toUpperCase())) {
        sexo = token.toUpperCase();
      } else if (RegExp(r"^[A-Za-zÁÉÍÓÚÑáéíóúñ\s.'-]+$").hasMatch(token) && token.length > 1) {
        words.add(token.toUpperCase());
      }
    }

    if (dni == null || words.length < 2) return null;

    // Orden estándar RENIEC: APELLIDO_PAT APELLIDO_MAT NOMBRES...
    // Sólo se aplica cuando hay 3 o más bloques de texto.
    String apellidos;
    String nombres;
    if (words.length >= 3) {
      apellidos = '${words[0]} ${words[1]}';
      nombres = words.sublist(2).join(' ');
    } else {
      apellidos = words[0];
      nombres = words.sublist(1).join(' ');
    }

    return DniPdf417Data(
      numeroDocumento: dni,
      nombres: nombres,
      apellidos: apellidos,
      fechaNacimiento: fecha,
      sexo: sexo,
      raw: raw,
    );
  }

  static String? _sanitizeDni(String? value) {
    if (value == null) return null;
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 8) return digits;
    return null;
  }

  static String? _clean(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  /// Punto de entrada para el futuro escáner PDF417:
  /// recibe el payload decodificado por la librería de cámara/código de
  /// barras y devuelve los datos listos para autocompletar el formulario.
  static DniPdf417Data? fromScannerPayload(String payload) => tryParse(payload);
}
