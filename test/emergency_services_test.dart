import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:alerta_ciudadana/data/services/whatsapp_api_service.dart';
import 'package:alerta_ciudadana/data/services/sensor_emergency_service.dart';
import 'package:alerta_ciudadana/data/services/session_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WhatsAppApiService Tests', () {
    test('default recipient is +51 976264949 and normalizes to 51976264949', () {
      expect(WhatsAppApiService.defaultEmergencyRecipient, '+51 976264949');
      expect(WhatsAppApiService.normalizeNumber('+51 976264949'), '51976264949');
      expect(WhatsAppApiService.normalizeNumber('976264949'), '51976264949');
    });

    test('getPredefinedMessage formats correctly for ROBO', () {
      final msg = WhatsAppApiService.getPredefinedMessage(
        'ROBO',
        address: 'Av. Test 123',
        lat: -12.04,
        lon: -77.02,
        source: 'BOTÓN ROJO',
      );
      expect(msg, contains('ROBANDO'));
      expect(msg, contains('Av. Test 123'));
      expect(msg, contains('BOTÓN ROJO'));
      expect(msg, contains('Central de Video Vigilancia'));
    });

    test('sendAutomatedEmergencyAlert completes successfully to 976264949', () async {
      final success = await WhatsAppApiService.sendAutomatedEmergencyAlert(
        category: 'ROBO',
        recipientNumber: '976264949',
        source: 'TEST_SUITE',
      );
      expect(success, isNotNull);
    });
  });

  group('SensorEmergencyService Tests', () {
    test('simulation triggers callback with reason', () {
      final sensor = SensorEmergencyService();
      String? triggeredReason;
      String? triggeredSource;

      sensor.startMonitoring(
        listenToHardware: false,
        onTriggered: (reason, source) {
          triggeredReason = reason;
          triggeredSource = source;
        },
      );

      sensor.simulateTheftSnatchTrigger();
      expect(triggeredReason, contains('Antirrobo'));
      expect(triggeredSource, 'sensor_simulado_robo');
      sensor.stopMonitoring();
    });
  });

  group('SessionService Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
    });

    test('verifySecretPin validates default PIN and custom PIN', () async {
      // Default fallback PIN is 7462 (primeros 4 dígitos de DNI 74629337)
      final defaultValid = await SessionService.verifySecretPin('7462');
      expect(defaultValid, isTrue);

      final wrongPin = await SessionService.verifySecretPin('9999');
      expect(wrongPin, isFalse);

      await SessionService.saveSession(
        dni: '77889900',
        secretPin: '4321',
      );

      final customValid = await SessionService.verifySecretPin('4321');
      expect(customValid, isTrue);
    });
  });
}
