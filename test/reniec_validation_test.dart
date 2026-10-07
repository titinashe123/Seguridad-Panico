import 'package:flutter_test/flutter_test.dart';
import 'package:alerta_ciudadana/data/services/reniec_service.dart';

void main() {
  const identity = ReniecIdentity(
    dni: '72845241',
    nombres: 'JHEFERSON ELIEL',
    apellidos: 'YALLE JAYO',
    fullName: 'JHEFERSON ELIEL YALLE JAYO',
  );

  group('ReniecService.normalizeName', () {
    test('minusculas, tildes y espacios sobrantes', () {
      expect(
        ReniecService.normalizeName('  JHEFERSON   Eliél '),
        'jheferson eliel',
      );
      expect(
        ReniecService.normalizeName('Yállé Jáyo'),
        'yalle jayo',
      );
    });
  });

  group('ReniecService.matchesIdentity (validación ciega)', () {
    test('coincide con mayúsculas/minúsculas y tildes distintas', () {
      expect(
        ReniecService.matchesIdentity(
          identity: identity,
          nombres: 'Jheferson Eliel',
          apellidos: 'Yalle Jayo',
        ),
        isTrue,
      );
    });

    test('coincide con espacios accidentales', () {
      expect(
        ReniecService.matchesIdentity(
          identity: identity,
          nombres: '  Jheferson   Eliel ',
          apellidos: 'Yalle  Jayo ',
        ),
        isTrue,
      );
    });

    test('coincide con datos en mayúsculas como RENIEC', () {
      expect(
        ReniecService.matchesIdentity(
          identity: identity,
          nombres: 'JHEFERSON ELIEL',
          apellidos: 'YALLE JAYO',
        ),
        isTrue,
      );
    });

    test('falla con una letra de más en los nombres', () {
      expect(
        ReniecService.matchesIdentity(
          identity: identity,
          nombres: 'Jheferson Eliel Andres',
          apellidos: 'Yalle Jayo',
        ),
        isFalse,
      );
    });

    test('falla con apellido materno y paterno invertidos', () {
      expect(
        ReniecService.matchesIdentity(
          identity: identity,
          nombres: 'Jheferson Eliel',
          apellidos: 'Jayo Yalle',
        ),
        isFalse,
      );
    });

    test('falla con error tipográfico', () {
      expect(
        ReniecService.matchesIdentity(
          identity: identity,
          nombres: 'Jheferson Elier',
          apellidos: 'Yalle Jayo',
        ),
        isFalse,
      );
    });

    test('falla si el usuario no escribe nada', () {
      expect(
        ReniecService.matchesIdentity(
          identity: identity,
          nombres: '',
          apellidos: '',
        ),
        isFalse,
      );
    });
  });

  group('ReniecService.isValidDniFormat', () {
    test('acepta exactamente 8 dígitos', () {
      expect(ReniecService.isValidDniFormat('72845241'), isTrue);
      expect(ReniecService.isValidDniFormat('7284524'), isFalse);
      expect(ReniecService.isValidDniFormat('728452411'), isFalse);
      expect(ReniecService.isValidDniFormat('7284524a'), isFalse);
    });
  });
}
