import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/services/app_lock_service.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/biometric_auth_service.dart';
import '../../../data/services/hardware_trigger_service.dart';
import '../../../data/services/reniec_service.dart';
import '../../../data/services/session_service.dart';
import '../navigation/main_layout_view.dart';

class RegisterView extends StatefulWidget {
  const RegisterView({super.key});

  @override
  State<RegisterView> createState() => _RegisterViewState();
}

class _RegisterViewState extends State<RegisterView> {
  final _dniController = TextEditingController();
  final _dvController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _pinController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _acceptTerms = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _dniController.dispose();
    _dvController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  void _onDniChanged(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits != value) {
      _dniController.value = TextEditingValue(
        text: digits,
        selection: TextSelection.collapsed(offset: digits.length),
      );
    }
  }

  void _onRegister() async {
    if (_isLoading) return;

    final dni = _dniController.text.trim();
    final dv = _dvController.text.trim();
    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final phone = _phoneController.text.trim();
    final password = _passwordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();
    final pin = _pinController.text.trim();

    // 1. Verificación de formato inicial (datos requeridos)
    if (dni.isEmpty ||
        !ReniecService.isValidDniFormat(dni) ||
        dv.isEmpty ||
        firstName.isEmpty ||
        lastName.isEmpty) {
      _showError('Por favor, ingrese sus datos correctamente.');
      return;
    }

    if (phone.isEmpty || phone.length < 9) {
      _showError('Por favor, ingrese un número de celular válido.');
      return;
    }
    if (password.isEmpty || password.length < 6) {
      _showError('La contraseña debe tener al menos 6 caracteres.');
      return;
    }
    if (password != confirmPassword) {
      _showError('Contraseña incorrecta');
      return;
    }
    final pinSecurityError = AuthService.validatePinSecurity(pin);
    if (pinSecurityError != null) {
      _showError(pinSecurityError);
      return;
    }
    if (!_acceptTerms) {
      _showError('Debe aceptar las Políticas de Privacidad y Términos de Uso para continuar con el registro.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 2. Consulta a RENIEC para contraste
      final lookupResult = await ReniecService.lookup(dni);
      if (!mounted) return;

      if (!lookupResult.isSuccess || lookupResult.identity == null) {
        setState(() => _isLoading = false);
        if (lookupResult.status == ReniecLookupStatus.networkError) {
          _showError('No se pudo conectar con el servicio de verificación. Revise su conexión.');
        } else {
          _showError('Por favor, ingrese sus datos correctamente.');
        }
        return;
      }

      final identity = lookupResult.identity!;

      // 3. Validación de Nombres y Apellidos con RENIEC
      final identityMatches = ReniecService.matchesIdentity(
        identity: identity,
        nombres: firstName,
        apellidos: lastName,
      );

      if (!identityMatches) {
        setState(() => _isLoading = false);
        // Mensaje genérico de seguridad sin revelar qué campo falló
        _showError('Por favor, ingrese sus datos correctamente.');
        return;
      }

      // 5. Todo validado exitosamente: Solicitar código OTP vía WhatsApp
      final otpReq = await AuthService.requestOtp(dni: dni, phone: phone);

      if (!mounted) return;
      setState(() => _isLoading = false);

      if (!otpReq.success) {
        _showError(otpReq.errorMessage ?? 'No se pudo enviar el código de verificación.');
        return;
      }

      // Abrir pantalla modal de ingreso de código de verificación
      _showOtpVerificationDialog(
        dni: dni,
        firstName: firstName,
        lastName: lastName,
        phone: phone,
        password: password,
        pin: pin,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError('Por favor, ingrese sus datos correctamente.');
    }
  }

  void _showOtpVerificationDialog({
    required String dni,
    required String firstName,
    required String lastName,
    required String phone,
    required String password,
    required String pin,
  }) {
    final otpController = TextEditingController();
    bool isVerifying = false;
    String? otpError;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: AppColors.accentOrange, width: 1.5),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.accentOrange.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.security_rounded, color: AppColors.accentOrange, size: 22),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Verificación OTP',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Hemos enviado un código de 6 dígitos a tu WhatsApp (+51 $phone) para validar tu identidad.',
                    style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.timer_outlined, size: 16, color: AppColors.accentOrange),
                      const SizedBox(width: 6),
                      Text(
                        'Válido por: 5 minutos',
                        style: GoogleFonts.chakraPetch(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.accentOrange,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: otpController,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 8,
                      color: Colors.white,
                    ),
                    decoration: InputDecoration(
                      hintText: '••••••',
                      counterText: '',
                      hintStyle: GoogleFonts.inter(letterSpacing: 6, color: AppColors.textMuted),
                      errorText: otpError,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: Text(
                    'CANCELAR',
                    style: GoogleFonts.inter(color: AppColors.textSecondary, fontWeight: FontWeight.bold),
                  ),
                ),
                ElevatedButton(
                  onPressed: isVerifying
                      ? null
                      : () async {
                          final code = otpController.text.trim();
                          if (code.length != 6) {
                            setDialogState(() {
                              otpError = 'Ingresa los 6 dígitos';
                            });
                            return;
                          }

                          setDialogState(() {
                            isVerifying = true;
                            otpError = null;
                          });

                          // 1. Verificar OTP
                          final verifyRes = await AuthService.verifyOtp(
                            dni: dni,
                            phone: phone,
                            code: code,
                          );

                          if (!verifyRes.success) {
                            setDialogState(() {
                              isVerifying = false;
                              otpError = verifyRes.errorMessage ?? 'Código inválido o expirado';
                            });
                            return;
                          }

                          // 2. Registrar usuario en la base de datos con Bcrypt y JWT (HU-SEG-02, HU-SEG-06)
                          final regResult = await AuthService.register(
                            dni: dni,
                            firstName: firstName,
                            lastName: lastName,
                            phone: phone,
                            password: password,
                            pin: pin,
                            otpCode: code,
                          );

                          if (!dialogCtx.mounted) return;
                          Navigator.of(dialogCtx).pop();

                          if (regResult.success) {
                            await BiometricAuthService.enrollUser(dni: dni);
                            await SessionService.saveLastDni(dni);
                            await HardwareTriggerService().startBackgroundService();
                            AppLockService().markJustLoggedIn();
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  '¡Cuenta verificada y registrada exitosamente!',
                                  style: GoogleFonts.inter(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                                backgroundColor: AppColors.accentGreen,
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                            Navigator.of(context).pushAndRemoveUntil(
                              MaterialPageRoute(builder: (_) => const MainLayoutView()),
                              (route) => false,
                            );
                          } else {
                            _showError(regResult.errorMessage ?? 'Error al registrar.');
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryRed,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: isVerifying
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : Text(
                          'CONFIRMAR',
                          style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showPrivacyPolicyDialog() {
    showDialog(
      context: context,
      builder: (dialogCtx) {
        return Dialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.border, width: 1),
          ),
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 520, maxHeight: 600),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primaryRed.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.shield_outlined,
                        color: AppColors.primaryRed,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Términos y Política de Privacidad',
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Alerta Ciudadana • Ley N° 29733 (Perú)',
                            style: GoogleFonts.inter(
                              color: AppColors.textMuted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: AppColors.textSecondary, size: 20),
                      onPressed: () => Navigator.of(dialogCtx).pop(),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Divider(color: AppColors.border, height: 1),
                const SizedBox(height: 14),

                // Contenido desplazable
                Expanded(
                  child: RawScrollbar(
                    thumbColor: AppColors.border,
                    radius: const Radius.circular(4),
                    thickness: 4,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.only(right: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildPolicySection(
                            '1. Identificación y Finalidad del Servicio',
                            'La aplicación móvil "Alerta Ciudadana" es una plataforma comunitaria de auxilio, prevención y reporte de incidencias para la seguridad vecinal, conectada a la Central de Serenazgo y Video Vigilancia.\n\nSu propósito exclusivo es salvaguardar la vida, integridad física y patrimonio de los ciudadanos mediante la emisión de alertas de emergencia y coordinación directa con las fuerzas del orden (Serenazgo y Policía Nacional del Perú - PNP).',
                          ),
                          _buildPolicySection(
                            '2. Datos Personales Recopilados',
                            'En estricto cumplimiento de la Ley N° 29733 (Ley de Protección de Datos Personales del Perú) y su Reglamento, se recopilan únicamente los siguientes datos esenciales:\n'
                            '• Documento Nacional de Identidad (DNI) y dígito verificador para cotejo de autenticidad ante el Registro Nacional de Identificación y Estado Civil (RENIEC).\n'
                            '• Nombres, apellidos y número de teléfono celular para comunicación y auxilio en emergencias.\n'
                            '• Contraseña de acceso y PIN secreto de 4 dígitos (encriptados en el dispositivo mediante Keystore/Keychain de alta seguridad).',
                          ),
                          _buildPolicySection(
                            '3. Geolocalización en Tiempo Real y Rastreo',
                            'Para que las unidades de auxilio puedan acudir al punto exacto de los hechos, el usuario autoriza el acceso a su ubicación GPS en los siguientes términos:\n'
                            '• Transmisión precisa de coordenadas en tiempo real al activar una alerta de auxilio (Robo, Violencia, Accidente, Incendio o Emergencia Médica).\n'
                            '• En caso de ROBO, se activará un protocolo de rastreo continuo en segundo plano ("Live Tracking") para guiar a las patrullas policiales o de serenazgo, el cual únicamente puede ser detenido ingresando su PIN secreto de 4 dígitos.',
                          ),
                          _buildPolicySection(
                            '4. Sensores de Hardware y Segundo Plano',
                            'La aplicación incorpora mecanismos autónomos de protección:\n'
                            '• Detección de pulsación rápida (3 o más toques) del botón físico para pánico inmediato.\n'
                            '• Sensores de movimiento (acelerómetro y giroscopio) para alertar tirones violentos o forcejeo (antirrobo).\n'
                            'Estos sensores operan bajo un servicio en primer plano persistente respetando el uso eficiente de batería.',
                          ),
                          _buildPolicySection(
                            '5. Confidencialidad y Seguridad',
                            'Los datos personales no serán compartidos, comercializados ni cedidos a ninguna empresa, entidad privada o tercero para fines comerciales ni publicitarios.\n\nLa información se transfiere mediante protocolos cifrados (HTTPS / SSL) y solo podrá ser visualizada por los operadores autorizados de la Central de Seguridad Ciudadana o remitida al Ministerio Público o PNP si media investigación judicial.',
                          ),
                          _buildPolicySection(
                            '6. Compromiso de Buen Uso y Sanciones',
                            'El usuario se compromete formalmente a utilizar la aplicación de manera responsable y veraz. Queda estrictamente prohibida la emisión de alertas falsas, bromas o reportes malintencionados.\n\nEl uso negligente o doloso que movilice innecesariamente a las fuerzas de seguridad podrá acarrear la cancelación definitiva de la cuenta, así como las sanciones administrativas y penales previstas en el marco legal peruano.',
                          ),
                          _buildPolicySection(
                            '7. Ejercicio de Derechos ARCO',
                            'El titular de los datos personales puede ejercer en cualquier momento sus derechos de Acceso, Rectificación, Cancelación y Oposición (ARCO) comunicándose con los canales oficiales de soporte de la Central de Seguridad Ciudadana.',
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 14),
                const Divider(color: AppColors.border, height: 1),
                const SizedBox(height: 14),

                // Botones de acción
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(dialogCtx).pop(),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.border),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: Text(
                          'CERRAR',
                          style: GoogleFonts.inter(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _acceptTerms = true;
                          });
                          Navigator.of(dialogCtx).pop();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryRed,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: Text(
                          'ACEPTAR POLÍTICA',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPolicySection(String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.inter(
              color: AppColors.primaryRed,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            style: GoogleFonts.inter(
              color: AppColors.textSecondary,
              fontSize: 11.5,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  void _showError(String message, {bool isSuccess = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            color: Colors.white,
            fontSize: 13,
          ),
        ),
        backgroundColor: isSuccess ? AppColors.accentGreen : AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _buildFieldLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: RichText(
        text: TextSpan(
          text: text.replaceAll('*', '').trim(),
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
            letterSpacing: 0.9,
          ),
          children: [
            if (text.contains('*'))
              const TextSpan(
                text: ' *',
                style: TextStyle(
                  color: AppColors.primaryRed,
                  fontWeight: FontWeight.bold,
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back, size: 20, color: AppColors.textPrimary),
                      onPressed: () => Navigator.of(context).pop(),
                      padding: EdgeInsets.zero,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: const Color(0xFF161E2C),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.primaryRed.withValues(alpha: 0.5)),
                    ),
                    child: const Icon(
                      Icons.shield_outlined,
                      size: 18,
                      color: AppColors.primaryRed,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'ALERTA CIUDADANA',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),

            // Main scrollable form
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'CREAR CUENTA',
                      style: GoogleFonts.inter(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: AppColors.textPrimary,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: AppColors.primaryRed,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Registro civil de seguridad ciudadana encriptada',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // DNI and DV Row
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildFieldLabel('DNI *'),
                              TextField(
                                controller: _dniController,
                                keyboardType: TextInputType.number,
                                maxLength: 8,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(8),
                                ],
                                onChanged: _onDniChanged,
                                style: const TextStyle(
                                    fontSize: 14, color: AppColors.textPrimary),
                                decoration: const InputDecoration(
                                  hintText: '8 dígitos',
                                  counterText: '',
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          flex: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildFieldLabel('DV *'),
                              TextField(
                                controller: _dvController,
                                keyboardType: TextInputType.text,
                                textAlign: TextAlign.center,
                                maxLength: 1,
                                textCapitalization: TextCapitalization.characters,
                                inputFormatters: [
                                  LengthLimitingTextInputFormatter(1),
                                ],
                                style: const TextStyle(
                                    fontSize: 14, color: AppColors.textPrimary),
                                decoration: const InputDecoration(
                                  hintText: '0',
                                  counterText: '',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 18),

                    // Nombres
                    _buildFieldLabel('NOMBRES *'),
                    TextField(
                      controller: _firstNameController,
                      textCapitalization: TextCapitalization.characters,
                      style: const TextStyle(
                          fontSize: 14, color: AppColors.textPrimary),
                      decoration: const InputDecoration(
                        hintText: 'Ej. JUAN CARLOS',
                      ),
                    ),

                    const SizedBox(height: 18),

                    // Apellidos
                    _buildFieldLabel('APELLIDOS *'),
                    TextField(
                      controller: _lastNameController,
                      textCapitalization: TextCapitalization.characters,
                      style: const TextStyle(
                          fontSize: 14, color: AppColors.textPrimary),
                      decoration: const InputDecoration(
                        hintText: 'Ej. PÉREZ MENDOZA',
                      ),
                    ),

                    const SizedBox(height: 18),

                    // Nro Celular
                    _buildFieldLabel('NRO. CELULAR *'),
                    TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
                      decoration: const InputDecoration(
                        hintText: '+51 999 999 999',
                      ),
                    ),

                    const SizedBox(height: 18),

                    // Contraseña
                    _buildFieldLabel('CONTRASEÑA *'),
                    TextField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      onChanged: (_) {
                        if (_confirmPasswordController.text.isNotEmpty) {
                          setState(() {});
                        }
                      },
                      style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
                      decoration: InputDecoration(
                        hintText: '••••••••',
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                            color: AppColors.textMuted,
                            size: 18,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),
                      ),
                    ),

                    const SizedBox(height: 18),

                    // Confirmar Contraseña
                    _buildFieldLabel('CONFIRMAR CONTRASEÑA *'),
                    TextField(
                      controller: _confirmPasswordController,
                      obscureText: _obscureConfirmPassword,
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
                      decoration: InputDecoration(
                        hintText: '••••••••',
                        errorText: (_confirmPasswordController.text.isNotEmpty &&
                                _confirmPasswordController.text != _passwordController.text)
                            ? 'Contraseña incorrecta'
                            : null,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureConfirmPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                            color: AppColors.textMuted,
                            size: 18,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscureConfirmPassword = !_obscureConfirmPassword;
                            });
                          },
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Secret PIN Field
                    _buildFieldLabel('PIN SECRETO DE SEGURIDAD (4 DÍGITOS) *'),
                    TextField(
                      controller: _pinController,
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                      obscureText: true,
                      obscuringCharacter: '•',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        letterSpacing: 6,
                      ),
                      decoration: const InputDecoration(
                        hintText: '4 dígitos no predecibles',
                        counterText: '',
                        prefixIcon: Icon(
                          Icons.pin_outlined,
                          color: AppColors.accentOrange,
                          size: 20,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Por seguridad, evita secuencias (1234), números repetidos (0000) o tu año de nacimiento.',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: AppColors.textMuted,
                        fontStyle: FontStyle.italic,
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Privacy Terms Checkbox
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: Checkbox(
                            value: _acceptTerms,
                            activeColor: AppColors.primaryRed,
                            checkColor: Colors.white,
                            side: const BorderSide(color: AppColors.primaryRed, width: 1.5),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                            onChanged: (val) {
                              setState(() {
                                _acceptTerms = val ?? false;
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              text: 'Acepto la ',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                                height: 1.4,
                              ),
                              children: [
                                TextSpan(
                                  text: 'Política de Privacidad',
                                  style: GoogleFonts.inter(
                                    color: AppColors.primaryRed,
                                    fontWeight: FontWeight.w600,
                                    decoration: TextDecoration.underline,
                                    decorationColor: AppColors.primaryRed,
                                  ),
                                  recognizer: TapGestureRecognizer()..onTap = _showPrivacyPolicyDialog,
                                ),
                                TextSpan(
                                  text: ' y al tratamiento de mis datos personales',
                                  recognizer: TapGestureRecognizer()
                                    ..onTap = () {
                                      setState(() {
                                        _acceptTerms = !_acceptTerms;
                                      });
                                    },
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 26),

                    // Register Button
                    ElevatedButton(
                      onPressed: _isLoading ? null : _onRegister,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryRed,
                        disabledBackgroundColor: AppColors.surfaceElevated,
                        disabledForegroundColor: AppColors.textDisabled,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 6,
                        shadowColor: AppColors.primaryRed.withValues(alpha: 0.5),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.2,
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.shield_outlined, size: 20, color: Colors.white),
                                const SizedBox(width: 8),
                                Text(
                                  'REGISTRARME',
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.2,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                    ),

                    const SizedBox(height: 16),

                    // Already have account
                    Center(
                      child: GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: RichText(
                          text: TextSpan(
                            text: '¿Ya tienes cuenta? ',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                            children: [
                              TextSpan(
                                text: 'Iniciar Sesión',
                                style: GoogleFonts.inter(
                                  color: AppColors.primaryRed,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
