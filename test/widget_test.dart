import 'package:flutter_test/flutter_test.dart';
import 'package:alerta_ciudadana/main.dart';

void main() {
  testWidgets('Renders LoginView on app launch', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const AlertaCiudadanaApp(isLoggedIn: false));

    // Verify key elements from Figma Image 1 are present
    expect(find.text('AlertaCiudadana'), findsOneWidget);
    expect(find.text('CENTRAL DE SEGURIDAD MÓVIL'), findsOneWidget);
    expect(find.text('INICIAR SESIÓN'), findsOneWidget);
    expect(find.text('Crear cuenta'), findsOneWidget);
  });
}
