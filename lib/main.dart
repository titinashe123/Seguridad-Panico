import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'data/services/session_service.dart';
import 'ui/features/auth/login_view.dart';
import 'ui/features/navigation/main_layout_view.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final loggedIn = await SessionService.isLoggedIn();
  runApp(AlertaCiudadanaApp(isLoggedIn: loggedIn));
}

class AlertaCiudadanaApp extends StatelessWidget {
  final bool isLoggedIn;
  const AlertaCiudadanaApp({super.key, required this.isLoggedIn});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AlertaCiudadana',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: isLoggedIn ? const MainLayoutView() : const LoginView(),
    );
  }
}
