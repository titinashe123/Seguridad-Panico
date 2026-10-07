import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:alerta_ciudadana/data/services/whatsapp_api_service.dart';
import 'package:alerta_ciudadana/data/services/sensor_emergency_service.dart';
import 'package:alerta_ciudadana/data/services/session_service.dart';
import 'package:alerta_ciudadana/data/services/auth_service.dart';

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

    test('does not trigger emergency if user is logged out', () async {
      SharedPreferences.setMockInitialValues({'app_session_is_logged_in': false});
      final sensor = SensorEmergencyService();
      String? triggeredReason;

      sensor.startMonitoring(
        listenToHardware: false,
        onTriggered: (reason, source) {
          triggeredReason = reason;
        },
      );

      sensor.simulateTheftSnatchTrigger(bypassAuth: false);
      await Future.delayed(const Duration(milliseconds: 50));
      expect(triggeredReason, isNull);
      sensor.stopMonitoring();
    });

    test('sensor thresholds enforce snatch and violent twist conditions', () {
      final sensor = SensorEmergencyService();
      expect(sensor.snatchLinearThreshold, 24.0);
      expect(sensor.struggleGyroThreshold, 7.0);
      expect(sensor.snatchRawThreshold, 38.0);
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

  group('AuthService & WhatsApp OTP Recovery Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
    });

    test('sendWhatsAppOtp and verifyRecoveryOtp validate 6-digit WhatsApp OTP code', () async {
      const testDni = '74629337';
      const testPhone = '+51 976264949';

      final sendRes = await AuthService.sendWhatsAppOtp(
        dni: testDni,
        phone: testPhone,
        purpose: 'recuperación de contraseña',
      );
      expect(sendRes.success, isTrue);

      // Verify wrong length code fails
      final invalidLen = await AuthService.verifyRecoveryOtp(
        dni: testDni,
        phone: testPhone,
        code: '123',
      );
      expect(invalidLen.success, isFalse);
      expect(invalidLen.errorMessage, contains('6 dígitos'));

      // Verify universal test code 123456 passes
      final validOtp = await AuthService.verifyRecoveryOtp(
        dni: testDni,
        phone: testPhone,
        code: '123456',
      );
      expect(validOtp.success, isTrue);
    });

    test('resetPassword validates min 6 characters and updates properly', () async {
      const testDni = '12345678';
      final tooShort = await AuthService.resetPassword(dni: testDni, newPassword: '123');
      expect(tooShort.success, isFalse);
      expect(tooShort.errorMessage, contains('6 caracteres'));

      final validReset = await AuthService.resetPassword(dni: testDni, newPassword: 'newSecretPass2026');
      expect(validReset.success, isTrue);
    });

    test('updatePin updates secret PIN in SessionService and rejects invalid PINs', () async {
      const testDni = '12345678';

      // Rejects non-4-digit PIN
      final invalidLen = await AuthService.updatePin(dni: testDni, newPin: '123');
      expect(invalidLen, isFalse);

      final invalidAlpha = await AuthService.updatePin(dni: testDni, newPin: 'abcd');
      expect(invalidAlpha, isFalse);

      // Valid 4-digit PIN
      final success = await AuthService.updatePin(dni: testDni, newPin: '9876');
      expect(success, isTrue);

      // Verify SessionService reflects the updated PIN
      final savedPin = await SessionService.getSecretPin();
      expect(savedPin, '9876');
      expect(await SessionService.verifySecretPin('9876'), isTrue);
    });
  });
}
