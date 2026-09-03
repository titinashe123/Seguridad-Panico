import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'ui/features/auth/login_view.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AlertaCiudadanaApp());
}

class AlertaCiudadanaApp extends StatelessWidget {
  const AlertaCiudadanaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Alerta Ciudadana',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const LoginView(),
    );
  }
}
