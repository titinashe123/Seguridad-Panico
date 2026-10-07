import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/services/app_lock_service.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/dni_pdf417_service.dart';
import '../../../data/services/reniec_service.dart';
import '../navigation/main_layout_view.dart';

class RegisterView extends StatefulWidget {
  const RegisterView({super.key});

  @override
  State<RegisterView> createState() => _RegisterViewState();
}

/// Estado de la validación de identidad RENIEC en el formulario.
enum _ReniecUiState {
  idle,
  loading,
  waitingNames,
  verified,
  mismatch,
  invalidFormat,
  notFound,
  networkError,
  serviceError,
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
  bool _acceptTerms = true;
  bool _isLoading = false;

  // Validación RENIEC (HU-IDENTIDAD-01)
  Timer? _dniDebounce;
  _ReniecUiState _reniecState = _ReniecUiState.idle;
  ReniecIdentity? _reniecIdentity;
  String _reniecMessage = '';

  bool get _identityVerified => _reniecState == _ReniecUiState.verified;

  @override
  void dispose() {
    _dniDebounce?.cancel();
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

  // ---------------------------------------------------------------------------
  // Validación de identidad RENIEC
  // ---------------------------------------------------------------------------

  /// Disparado al escribir en el campo DNI: debounce de 700 ms y consulta
  /// automática cuando se completan los 8 dígitos (tiempo real).
  void _onDniChanged(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits != value) {
      _dniController.value = TextEditingValue(
        text: digits,
        selection: TextSelection.collapsed(offset: digits.length),
      );
    }

    _dniDebounce?.cancel();
    setState(() {
      _reniecState = _ReniecUiState.idle;
      _reniecMessage = '';
      _reniecIdentity = null;
    });

    if (digits.length != 8) return;

    _dniDebounce = Timer(const Duration(milliseconds: 700), _consultReniec);
  }

  /// Consulta la identidad oficial y contrasta/aplica los datos.
  Future<void> _consultReniec() async {
    final dni = _dniController.text.trim();

    if (!ReniecService.isValidDniFormat(dni)) {
      setState(() {
        _reniecState = _ReniecUiState.invalidFormat;
        _reniecMessage = 'DNI inválido: debe contener exactamente 8 dígitos.';
      });
      return;
    }

    setState(() {
      _reniecState = _ReniecUiState.loading;
      _reniecMessage = 'Consultando RENIEC...';
    });

    final result = await ReniecService.lookup(dni);
    if (!mounted) return;

    if (!result.isSuccess || result.identity == null) {
      setState(() {
        _reniecState = _mapLookupError(result.status);
        _reniecMessage = result.message.isNotEmpty
            ? result.message
            : 'No se pudo validar el DNI con RENIEC.';
        _reniecIdentity = null;
      });
      return;
    }

    final identity = result.identity!;

    // Validación ciega: los datos de RENIEC se guardan SÓLO en memoria para
    // contrastarlos. NUNCA se autocompletan NOMBRES/APELLIDOS (privacidad).
    setState(() {
      _reniecIdentity = identity;
      if (identity.dv != null &&
          identity.dv!.isNotEmpty &&
          _dvController.text.trim().isEmpty) {
        _dvController.text = identity.dv!;
      }
    });

    _revalidateNames();
  }

  _ReniecUiState _mapLookupError(ReniecLookupStatus status) {
    switch (status) {
      case ReniecLookupStatus.invalidFormat:
        return _ReniecUiState.invalidFormat;
      case ReniecLookupStatus.notFound:
        return _ReniecUiState.notFound;
      case ReniecLookupStatus.networkError:
        return _ReniecUiState.networkError;
      default:
        return _ReniecUiState.serviceError;
    }
  }

  /// Contraste estricto de NOMBRES/APELLIDOS contra la identidad oficial
  /// (se ejecuta en tiempo real al editar los campos). Los datos de RENIEC
  /// se comparan de forma ciega: no se muestran ni se copian al formulario.
  void _revalidateNames() {
    final identity = _reniecIdentity;
    if (identity == null) return;

    final nombres = _firstNameController.text;
    final apellidos = _lastNameController.text;

    // Identidad consultada, a la espera de que el ciudadano escriba sus datos
    if (nombres.isEmpty || apellidos.isEmpty) {
      setState(() {
        _reniecState = _ReniecUiState.waitingNames;
        _reniecMessage =
            'DNI consultado. Escribe tus nombres y apellidos tal como figuran en RENIEC.';
      });
      return;
    }

    final matches = ReniecService.matchesIdentity(
      identity: identity,
      nombres: nombres,
      apellidos: apellidos,
    );

    setState(() {
      _reniecState = matches ? _ReniecUiState.verified : _ReniecUiState.mismatch;
      _reniecMessage = matches
          ? 'Identidad verificada con RENIEC.'
          : 'Los datos no coinciden con los registros del DNI.';
    });
  }

  /// Hook para el futuro escáner PDF417 del reverso del DNI:
  /// payload decodificado -> autocompletado -> consulta RENIEC.
  // ignore: unused_element
  void _onDniBarcodeScanned(String payload) {
    final data = DniPdf417Service.tryParse(payload);
    if (data == null || !data.hasIdentity) {
      _showError('No se pudo leer el código del DNI. Intente nuevamente.');
      return;
    }
    setState(() {
      _dniController.text = data.numeroDocumento ?? '';
      _firstNameController.text = data.nombres ?? '';
      _lastNameController.text = data.apellidos ?? '';
    });
    _consultReniec();
  }

  void _onRegister() async {
    if (_isLoading) return;

    final dni = _dniController.text.trim();
    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final phone = _phoneController.text.trim();
    final password = _passwordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();
    final pin = _pinController.text.trim();

    if (dni.isEmpty || !ReniecService.isValidDniFormat(dni)) {
      _showError('Ingrese un número de DNI válido (8 dígitos).');
      return;
    }
    // Bloqueo de registro sin validación RENIEC o con datos discrepantes
    if (!_identityVerified) {
      if (_reniecState == _ReniecUiState.mismatch) {
        _showError('Los datos no coinciden con los registros del DNI.');
      } else if (_reniecState == _ReniecUiState.waitingNames) {
        _showError(
            'Escribe tus nombres y apellidos tal como figuran en RENIEC.');
      } else {
        _showError(
            'Valida tu identidad: consulta tu DNI en RENIEC antes de continuar.');
      }
      return;
    }
    if (firstName.isEmpty) {
      _showError('Por favor ingrese sus nombres.');
      return;
    }
    if (lastName.isEmpty) {
      _showError('Por favor ingrese sus apellidos.');
      return;
    }
    if (phone.isEmpty || phone.length < 9) {
      _showError('Ingrese un número de celular válido.');
      return;
    }
    if (password.isEmpty || password.length < 6) {
      _showError('La contraseña debe tener al menos 6 caracteres.');
      return;
    }
    if (password != confirmPassword) {
      _showError('Las contraseñas no coinciden.');
      return;
    }
    if (pin.isEmpty || pin.length != 4) {
      _showError('El PIN secreto debe ser de exactamente 4 dígitos.');
      return;
    }
    if (!_acceptTerms) {
      _showError('Debe aceptar las políticas de privacidad para continuar.');
      return;
    }

    setState(() => _isLoading = true);

    // HU-SEG-01: Solicitar código OTP de 6 dígitos vía WhatsApp
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
                            if (!mounted) return;
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
                            AppLockService().markJustLoggedIn();
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

  /// Icono de estado dentro del campo DNI (carga / verificado / error)
  Widget _buildDniSuffixIcon() {
    switch (_reniecState) {
      case _ReniecUiState.loading:
        return const Padding(
          padding: EdgeInsets.only(right: 12),
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.accentBlue,
            ),
          ),
        );
      case _ReniecUiState.verified:
      case _ReniecUiState.waitingNames:
        return const Padding(
          padding: EdgeInsets.only(right: 12),
          child: Icon(Icons.verified_user_rounded,
              color: AppColors.accentGreen, size: 18),
        );
      case _ReniecUiState.idle:
        return const SizedBox.shrink();
      default:
        return const Padding(
          padding: EdgeInsets.only(right: 12),
          child: Icon(Icons.error_outline_rounded,
              color: AppColors.error, size: 18),
        );
    }
  }

  /// Mensaje de estado de la validación RENIEC bajo el campo DNI.
  Widget _buildReniecStatus() {
    if (_reniecState == _ReniecUiState.idle) return const SizedBox.shrink();

    late final Color color;
    late final IconData icon;
    late final String text;

    switch (_reniecState) {
      case _ReniecUiState.loading:
        color = AppColors.accentBlue;
        icon = Icons.sync_rounded;
        text = _reniecMessage;
        break;
      case _ReniecUiState.waitingNames:
        color = AppColors.accentBlue;
        icon = Icons.edit_note_rounded;
        text = _reniecMessage;
        break;
      case _ReniecUiState.verified:
        color = AppColors.accentGreen;
        icon = Icons.verified_user_rounded;
        text = 'Identidad verificada con RENIEC.';
        break;
      case _ReniecUiState.mismatch:
        color = AppColors.error;
        icon = Icons.gpp_bad_rounded;
        text = 'Los datos no coinciden con los registros del DNI.';
        break;
      case _ReniecUiState.invalidFormat:
        color = AppColors.error;
        icon = Icons.badge_rounded;
        text = 'DNI inválido: debe contener exactamente 8 dígitos.';
        break;
      case _ReniecUiState.notFound:
        color = AppColors.error;
        icon = Icons.search_off_rounded;
        text = 'El DNI no existe en los registros de RENIEC.';
        break;
      case _ReniecUiState.networkError:
        color = AppColors.accentOrange;
        icon = Icons.wifi_off_rounded;
        text = _reniecMessage;
        break;
      case _ReniecUiState.serviceError:
        color = AppColors.accentOrange;
        icon = Icons.cloud_off_rounded;
        text = _reniecMessage;
        break;
      case _ReniecUiState.idle:
        return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_reniecState == _ReniecUiState.loading)
            const Padding(
              padding: EdgeInsets.only(top: 1),
              child: SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                    strokeWidth: 1.6, color: AppColors.accentBlue),
              ),
            )
          else
            Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
                height: 1.3,
              ),
            ),
          ),
        ],
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
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  _buildFieldLabel('DNI *'),
                                  Row(
                                    children: [
                                      // Hook del futuro escáner PDF417 (reverso del DNI)
                                      TextButton(
                                        onPressed: () => _showError(
                                            'Escáner PDF417 pendiente de integrar: ver DniPdf417Service.',
                                            isSuccess: true),
                                        style: TextButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6),
                                          minimumSize: Size.zero,
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        child: Text(
                                          'ESCANEAR',
                                          style: GoogleFonts.chakraPetch(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 0.8,
                                            color: AppColors.textMuted,
                                          ),
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: _reniecState ==
                                                _ReniecUiState.loading
                                            ? null
                                            : _consultReniec,
                                        style: TextButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6),
                                          minimumSize: Size.zero,
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        child: Text(
                                          'CONSULTAR RENIEC',
                                          style: GoogleFonts.chakraPetch(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 0.8,
                                            color: AppColors.accentBlue,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
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
                                decoration: InputDecoration(
                                  hintText: '8 dígitos',
                                  counterText: '',
                                  suffixIcon: _buildDniSuffixIcon(),
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
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    fontSize: 14, color: AppColors.textPrimary),
                                decoration: const InputDecoration(
                                  hintText: '0',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    // Estado de la validación RENIEC en tiempo real
                    _buildReniecStatus(),

                    const SizedBox(height: 18),

                    // Nombres (el ciudadano escribe manualmente; se contrasta
                    // de forma estricta y ciega contra RENIEC)
                    _buildFieldLabel('NOMBRES *'),
                    TextField(
                      controller: _firstNameController,
                      textCapitalization: TextCapitalization.characters,
                      onChanged: (_) => _revalidateNames(),
                      style: const TextStyle(
                          fontSize: 14, color: AppColors.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'Ej. JUAN CARLOS',
                        errorText: _reniecState == _ReniecUiState.mismatch
                            ? 'Los datos no coinciden con los registros del DNI'
                            : null,
                      ),
                    ),

                    const SizedBox(height: 18),

                    // Apellidos
                    _buildFieldLabel('APELLIDOS *'),
                    TextField(
                      controller: _lastNameController,
                      textCapitalization: TextCapitalization.characters,
                      onChanged: (_) => _revalidateNames(),
                      style: const TextStyle(
                          fontSize: 14, color: AppColors.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'Ej. PÉREZ MENDOZA',
                        errorText: _reniecState == _ReniecUiState.mismatch
                            ? 'Los datos no coinciden con los registros del DNI'
                            : null,
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
                      style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
                      decoration: InputDecoration(
                        hintText: '••••••••',
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
                        hintText: '4 dígitos (ej. 1234)',
                        counterText: '',
                        prefixIcon: Icon(
                          Icons.pin_outlined,
                          color: AppColors.accentOrange,
                          size: 20,
                        ),
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
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _acceptTerms = !_acceptTerms;
                              });
                            },
                            child: RichText(
                              text: TextSpan(
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
                                  ),
                                  const TextSpan(
                                    text: ' y al tratamiento de mis datos personales',
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 26),

                    // Register Button (habilitado sólo con identidad verificada)
                    ElevatedButton(
                      onPressed:
                          (_isLoading || !_identityVerified) ? null : _onRegister,
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
