import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'session_service.dart';
import 'whatsapp_api_service.dart';

/// Servicio para almacenamiento dual (Local persistente + Supabase en la nube)
/// de todos los reportes ciudadanos, tanto enviados exitosamente como aquellos
/// pendientes o no enviados por corte de red o falta de conexión.
class ReportStorageService {
  static const String _keyLocalReports = 'local_saved_reports_v2';
  static const String _supabaseUrl = 'https://emtzprcntefzkvvzmhfk.supabase.co';

  /// Obtiene los headers autorizados para PostgREST de Supabase
  /// Importante: PostgREST exige el JWT anónimo del proyecto en Authorization: Bearer
  static Map<String, String> get _supabaseHeaders => {
        'apikey': WhatsAppApiService.supabaseAnonKey,
        'Authorization': 'Bearer ${WhatsAppApiService.supabaseAnonKey}',
        'Content-Type': 'application/json',
      };

  /// Mapea el nombre de la categoría a su respectivo id_tipo
  static int getTipoId(String category) {
    switch (category.trim().toUpperCase()) {
      case 'ROBO':
        return 1;
      case 'ACCIDENTE':
        return 2;
      case 'INCENDIO':
        return 3;
      case 'GRESCA':
        return 4;
      case 'ASESINATO':
        return 5;
      case 'SECUESTRO':
        return 6;
      case 'PERSONALIZADO':
      default:
        return 7;
    }
  }

  /// Carga la lista combinada de reportes:
  /// 1. Lee la memoria caché local persistente (SharedPreferences).
  /// 2. Consulta a Supabase los reportes en la nube.
  /// 3. Fusiona y actualiza la caché local, mostrando reportes enviados y no enviados.
  static Future<List<Map<String, dynamic>>> loadAllReports() async {
    final prefs = await SharedPreferences.getInstance();
    List<Map<String, dynamic>> localList = [];

    final rawJson = prefs.getString(_keyLocalReports);
    if (rawJson != null && rawJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawJson) as List<dynamic>;
        localList = decoded.cast<Map<String, dynamic>>().toList();
      } catch (e) {
        developer.log('Error decodificando reportes locales: $e', name: 'ReportStorageService');
      }
    }

    // Consulta a Supabase en la nube
    try {
      final uriWithFotos = Uri.parse(
        '$_supabaseUrl/rest/v1/reporte?select=id_reporte,descripcion,fecha_hora,direccion_texto,id_tipo,id_estado,fotos,tipo_incidencia(nombre),estado_reporte(nombre)&order=fecha_hora.desc',
      );

      var response = await http
          .get(uriWithFotos, headers: _supabaseHeaders)
          .timeout(const Duration(seconds: 6));

      // Si la columna fotos aún no fue creada en PostgreSQL, consultar columnas base
      if (response.statusCode == 400 && response.body.contains('fotos')) {
        final uriBase = Uri.parse(
          '$_supabaseUrl/rest/v1/reporte?select=id_reporte,descripcion,fecha_hora,direccion_texto,id_tipo,id_estado,tipo_incidencia(nombre),estado_reporte(nombre)&order=fecha_hora.desc',
        );
        response = await http
            .get(uriBase, headers: _supabaseHeaders)
            .timeout(const Duration(seconds: 6));
      }

      if (response.statusCode == 200) {
        final List<dynamic> remoteData = jsonDecode(response.body);
        final remoteReports = remoteData.cast<Map<String, dynamic>>();

        // Fusionar: Mantener reportes locales que no han sido sincronizados (id_estado = 2 o locales)
        final Map<String, Map<String, dynamic>> mergedMap = {};

        // Agregar primero los remotos
        for (final r in remoteReports) {
          final idKey = 'REP-${r['id_reporte']}';
          mergedMap[idKey] = r;
        }

        // Agregar o sobreescribir los locales no sincronizados o pendientes
        for (final l in localList) {
          final isSynced = l['is_synced'] == true;
          final idKey = l['id_reporte'] != null ? 'REP-${l['id_reporte']}' : 'LOC-${l['fecha_hora']}';
          if (!isSynced || !mergedMap.containsKey(idKey)) {
            mergedMap[idKey] = l;
          }
        }

        // Ordenar por fecha descendente
        final mergedList = mergedMap.values.toList();
        mergedList.sort((a, b) {
          final dtA = DateTime.tryParse(a['fecha_hora']?.toString() ?? '') ?? DateTime(2000);
          final dtB = DateTime.tryParse(b['fecha_hora']?.toString() ?? '') ?? DateTime(2000);
          return dtB.compareTo(dtA);
        });

        // Guardar la caché consolidada
        await prefs.setString(_keyLocalReports, jsonEncode(mergedList));
        return mergedList;
      }
    } catch (e) {
      developer.log('Sin conexión con Supabase. Mostrando caché local: $e', name: 'ReportStorageService');
    }

    return localList;
  }

  /// Guarda un reporte inmediatamente (tanto en almacenamiento local como en Supabase)
  /// Si el envío falla o está offline, queda registrado con id_estado = 2 ("No enviado").
  static Future<Map<String, dynamic>> saveReport({
    required String category,
    required String message,
    required String address,
    required double lat,
    required double lon,
    List<String>? imagePaths,
    bool isSuccessfullyDispatched = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final idTipo = getTipoId(category);

    // 1. Procesar fotografías a Base64
    final List<Map<String, dynamic>> fotosList = [];
    if (imagePaths != null && imagePaths.isNotEmpty) {
      for (int i = 0; i < imagePaths.length; i++) {
        final f = File(imagePaths[i]);
        if (await f.exists()) {
          try {
            final bytes = await f.readAsBytes();
            final b64 = base64Encode(bytes);
            fotosList.add({
              'nombre': f.uri.pathSegments.isNotEmpty ? f.uri.pathSegments.last : 'foto_${i + 1}.jpg',
              'data': 'data:image/jpeg;base64,$b64',
              'tamano': bytes.length,
            });
          } catch (e) {
            developer.log('Error codificando foto $i: $e', name: 'ReportStorageService');
          }
        }
      }
    }

    // 2. Crear objeto reporte inicial
    final Map<String, dynamic> reportRecord = {
      'id_reporte': DateTime.now().millisecondsSinceEpoch,
      'id_tipo': idTipo,
      'tipo_incidencia': {'nombre': category.trim().toUpperCase()},
      'id_estado': isSuccessfullyDispatched ? 1 : 2,
      'estado_reporte': {'nombre': isSuccessfullyDispatched ? 'Enviado' : 'No enviado'},
      'fecha_hora': nowIso,
      'descripcion': message,
      'direccion_texto': address,
      'fotos': fotosList,
      'latitud': lat,
      'longitud': lon,
      'is_synced': false,
    };

    // 3. Guardado preventivo inmediato en memoria local
    List<Map<String, dynamic>> currentLocal = [];
    final rawJson = prefs.getString(_keyLocalReports);
    if (rawJson != null && rawJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawJson) as List<dynamic>;
        currentLocal = decoded.cast<Map<String, dynamic>>().toList();
      } catch (_) {}
    }
    currentLocal.insert(0, reportRecord);
    await prefs.setString(_keyLocalReports, jsonEncode(currentLocal));

    // 4. Intentar sincronización con Supabase
    try {
      int? idPersona = await SessionService.getIdPersona();
      if (idPersona == null) {
        final citizen = await SessionService.getUserData();
        final dni = citizen['dni'] ?? '';
        if (dni.isNotEmpty) {
          try {
            final pRes = await http.get(
              Uri.parse('$_supabaseUrl/rest/v1/persona?dni=eq.$dni&select=id_persona'),
              headers: _supabaseHeaders,
            ).timeout(const Duration(seconds: 4));
            if (pRes.statusCode == 200) {
              final List<dynamic> pData = jsonDecode(pRes.body);
              if (pData.isNotEmpty) {
                idPersona = int.tryParse(pData.first['id_persona']?.toString() ?? '');
              }
            }
          } catch (_) {}
        }
      }
      idPersona ??= 1;

      final reportUri = Uri.parse('$_supabaseUrl/rest/v1/reporte');
      final insertHeaders = {
        ..._supabaseHeaders,
        'Prefer': 'return=representation',
      };

      Map<String, dynamic> remotePayload = {
        'id_persona': idPersona,
        'id_tipo': idTipo,
        'id_estado': isSuccessfullyDispatched ? 1 : 2,
        'fecha_hora': nowIso,
        'descripcion': message,
        'direccion_texto': address,
      };

      if (fotosList.isNotEmpty) {
        remotePayload['fotos'] = fotosList;
      }

      var res = await http.post(
        reportUri,
        headers: insertHeaders,
        body: jsonEncode(remotePayload),
      ).timeout(const Duration(seconds: 7));

      if (res.statusCode == 400 && res.body.contains('fotos')) {
        remotePayload.remove('fotos');
        if (fotosList.isNotEmpty) {
          remotePayload['descripcion'] = '$message\n📸 [${fotosList.length} fotografía(s) adjunta(s)]';
        }
        res = await http.post(
          reportUri,
          headers: insertHeaders,
          body: jsonEncode(remotePayload),
        ).timeout(const Duration(seconds: 7));
      }

      if (res.statusCode == 201 || res.statusCode == 200) {
        final List<dynamic> resData = jsonDecode(res.body);
        if (resData.isNotEmpty) {
          final int newReportId = int.parse(resData.first['id_reporte'].toString());
          reportRecord['id_reporte'] = newReportId;
          reportRecord['is_synced'] = true;
          reportRecord['id_estado'] = 1;
          reportRecord['estado_reporte'] = {'nombre': 'Enviado'};

          // Actualizar en lista local
          currentLocal[0] = reportRecord;
          await prefs.setString(_keyLocalReports, jsonEncode(currentLocal));

          // Guardar ubicación en Supabase
          try {
            await http.post(
              Uri.parse('$_supabaseUrl/rest/v1/ubicacion'),
              headers: insertHeaders,
              body: jsonEncode({
                'id_reporte': newReportId,
                'latitud': lat,
                'longitud': lon,
                'fecha_hora': nowIso,
              }),
            ).timeout(const Duration(seconds: 4));
          } catch (_) {}

          developer.log('Reporte #$newReportId sincronizado exitosamente con Supabase', name: 'ReportStorageService');
        }
      } else {
        developer.log('Supabase no aceptó inserción (${res.statusCode}): ${res.body}. Conservado localmente.', name: 'ReportStorageService');
      }
    } catch (e) {
      developer.log('Error o sin conexión al persistir en Supabase: $e. Conservado localmente como "No enviado".', name: 'ReportStorageService');
    }

    return reportRecord;
  }

  /// Actualiza un reporte existente en la caché local como "Enviado" (id_estado = 1)
  static Future<void> markReportAsSent(int idReporte) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawJson = prefs.getString(_keyLocalReports);
      if (rawJson != null && rawJson.isNotEmpty) {
        final decoded = jsonDecode(rawJson) as List<dynamic>;
        final list = decoded.cast<Map<String, dynamic>>().toList();
        for (var r in list) {
          if (r['id_reporte'] == idReporte) {
            r['id_estado'] = 1;
            r['estado_reporte'] = {'nombre': 'Enviado'};
            break;
          }
        }
        await prefs.setString(_keyLocalReports, jsonEncode(list));
      }
    } catch (_) {}
  }
}
