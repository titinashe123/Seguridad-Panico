import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/services/whatsapp_api_service.dart';
import '../../../data/services/location_tracking_service.dart';
import '../../../data/services/session_service.dart';
import '../../../data/services/gps_location_service.dart';
import '../../../data/services/hardware_trigger_service.dart';
import '../../../data/services/biometric_auth_service.dart';
import '../reports/new_report_view.dart';

class EmergencyCountdownDialog extends StatefulWidget {
  final String alertType;
  final bool isDirectWhatsAppApi;
  final String source;

  const EmergencyCountdownDialog({
    super.key,
    this.alertType = 'ROBO',
    this.isDirectWhatsAppApi = true,
    this.source = 'BOTÓN PRINCIPAL',
  });

  static bool _isOpen = false;

  static Future<void> show(
    BuildContext context, {
    String alertType = 'ROBO',
    bool isDirectWhatsAppApi = true,
    String source = 'BOTÓN PRINCIPAL',
  }) async {
    // Si el usuario no ha iniciado sesión, no permitir mostrar el diálogo de emergencia
    final loggedIn = await SessionService.isLoggedIn();
    if (!loggedIn) return;
    if (!context.mounted) return;

    if (_isOpen) return;
    _isOpen = true;
    try {
      await showDialog(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: 0.85),
        builder: (_) => EmergencyCountdownDialog(
          alertType: alertType,
          isDirectWhatsAppApi: isDirectWhatsAppApi,
          source: source,
        ),
      );
    } finally {
      _isOpen = false;
      HardwareTriggerService().resetEmergencyState();
    }
  }

  @override
  State<EmergencyCountdownDialog> createState() => _EmergencyCountdownDialogState();
}

class _EmergencyCountdownDialogState extends State<EmergencyCountdownDialog>
    with SingleTickerProviderStateMixin {
  int _secondsLeft = 5;
  Timer? _timer;
  final _pinController = TextEditingController();
  late AnimationController _pulseController;
  bool _canUseBiometrics = false;
  bool _hasTriggeredSend = false;
  Position? _preFetchedPosition;
  Future<Position?>? _locationFuture;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    // Iniciar pre-fijación satelital GPS inmediatamente desde el segundo 0
    _locationFuture = GpsLocationService.getCurrentLocation().then((pos) {
      if (mounted && pos != null) {
        setState(() {
          _preFetchedPosition = pos;
        });
      } else {
        _preFetchedPosition = pos;
      }
      return pos;
    }).catchError((_) => null);

    _checkBiometrics();
    _startTimer();
  }

  Future<void> _checkBiometrics() async {
    final ready = await BiometricAuthService.isBiometricsReady();
    final enabled = await BiometricAuthService.isBiometricsEnabled();
    if (mounted) {
      setState(() {
        _canUseBiometrics = ready && enabled;
      });
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsLeft > 1) {
        setState(() {
          _secondsLeft--;
        });
      } else {
        _timer?.cancel();
        _onAutoSend();
      }
    });
  }

  void _onAutoSend() async {
    if (_hasTriggeredSend) return;
    _hasTriggeredSend = true;
    _timer?.cancel();
    final parentContext = context;
    Navigator.of(parentContext).pop();

    final isRobo = widget.alertType.trim().toUpperCase() == 'ROBO';
    final isSecuestro = widget.alertType.trim().toUpperCase() == 'SECUESTRO';
    final hasLiveTracking = isRobo || isSecuestro;

    // 1. Obtener la posición satelital (pre-fijada durante los 5 segundos de cuenta regresiva)
    Position? position = _preFetchedPosition;
    if (position == null && _locationFuture != null) {
      try {
        position = await _locationFuture!.timeout(const Duration(seconds: 2));
      } catch (_) {}
    }
    position ??= await GpsLocationService.getCurrentLocation();

    // 2. Si no hay GPS en vivo, usar la última ubicación real persistida por el dispositivo
    final cached = await GpsLocationService.getCachedRealCoordinates();
    final double lat = position?.latitude ?? (cached?['lat'] as double?) ?? -13.71450;
    final double lon = position?.longitude ?? (cached?['lon'] as double?) ?? -76.20320;

    String address = (cached?['address'] as String?) ?? 'Pisco, Ica - Ubicación móvil';
    if (position != null) {
      final realStreet = await GpsLocationService.getAddressFromCoordinates(lat, lon);
      address = realStreet != null
          ? '$realStreet (±${position.accuracy.toStringAsFixed(1)}m)'
          : 'Ubicación móvil GPS (±${position.accuracy.toStringAsFixed(1)}m)';
    }

    // 3. Encendido instantáneo del rastreo GPS en vivo con la posición real
    if (hasLiveTracking) {
      final provisionalId = 'ALT-${DateTime.now().millisecondsSinceEpoch}';
      LocationTrackingService().startTracking(
        alertId: provisionalId,
        initialLat: lat,
        initialLon: lon,
      );
    }

    if (widget.isDirectWhatsAppApi) {
      // Envío automático vía API sin abrir el formulario ni la app de WhatsApp
      final alertId = await WhatsAppApiService.sendAutomatedEmergencyAlert(
        category: widget.alertType,
        source: widget.source,
        recipientNumber: WhatsAppApiService.defaultEmergencyRecipient,
        lat: lat,
        lon: lon,
        address: address,
      );

      if (hasLiveTracking && alertId != null) {
        LocationTrackingService().updateAlertId(alertId);
      }

      if (parentContext.mounted) {
        showDialog(
          context: parentContext,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: AppColors.accentGreen, width: 1.5),
            ),
            title: Row(
              children: [
                const Icon(Icons.check_circle, color: AppColors.accentGreen, size: 24),
                const SizedBox(width: 8),
                Text(
                  'Reporte Enviado',
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            content: Text(
              hasLiveTracking
                  ? 'El reporte fue enviado con éxito a la Central de Video Vigilancia.\n\n🔴 SEGUIMIENTO EN VIVO ACTIVADO:\nSe inició el rastreo GPS en tiempo real para seguir tu desplazamiento.'
                  : 'El reporte fue enviado con éxito a la Central de Video Vigilancia.',
              style: GoogleFonts.inter(fontSize: 14, color: AppColors.textSecondary),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(
                  'ENTENDIDO',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.bold,
                    color: AppColors.accentGreen,
                  ),
                ),
              ),
            ],
          ),
        );
      }
    } else {
      // Flujo opcional hacia el formulario detallado de reporte
      if (parentContext.mounted) {
        Navigator.of(parentContext).push(
          MaterialPageRoute(
            builder: (_) => NewReportView(initialCategory: widget.alertType),
          ),
        );
      }
    }
  }

  void _onCancel() async {
    final enteredPin = _pinController.text.trim();
    if (enteredPin.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Ingrese su PIN secreto de 4 dígitos para cancelar.',
            style: GoogleFonts.inter(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
      return;
    }

    final isValid = await SessionService.verifySecretPin(enteredPin);
    if (!isValid) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'PIN secreto incorrecto. No se puede cancelar la alerta.',
            style: GoogleFonts.inter(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
      return;
    }

    _timer?.cancel();
    LocationTrackingService().stopTracking();
    HardwareTriggerService().cancelEmergency();
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Alerta cancelada por el usuario con PIN secreto.',
          style: GoogleFonts.inter(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        backgroundColor: const Color(0xFF1E293B),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  void _onBiometricCancel() async {
    final authenticated = await BiometricAuthService.authenticate(
      reason: 'Coloca tu huella digital para cancelar la alerta de emergencia',
    );

    if (authenticated) {
      _timer?.cancel();
      LocationTrackingService().stopTracking();
      HardwareTriggerService().cancelEmergency();
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Alerta cancelada con huella digital.',
            style: GoogleFonts.inter(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          backgroundColor: const Color(0xFF1E293B),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pinController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '⚠️ Debe ingresar su PIN secreto de 4 dígitos para cancelar la alerta.',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            backgroundColor: AppColors.primaryRed,
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
      },
      child: Center(
        child: SingleChildScrollView(
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: Container(
            padding: const EdgeInsets.all(24.0),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.primaryRed,
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryRed.withValues(alpha: 0.25),
                  blurRadius: 28,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Warning Header
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFF221A22),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppColors.primaryRed.withValues(alpha: 0.4),
                        ),
                      ),
                      child: const Icon(
                        Icons.warning_amber_rounded,
                        color: AppColors.primaryRed,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.warning_rounded,
                                size: 13,
                                color: Color(0xFFFF9800),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  'ALERTA DE ${widget.alertType}',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFFFF9800),
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'DETECTADO',
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: AppColors.primaryRed,
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Se enviará un reporte automático en:',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 28),

                // Giant Circular Countdown
                AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    final scale = 1.0 + (_pulseController.value * 0.04);
                    return Transform.scale(
                      scale: scale,
                      child: Container(
                        width: 110,
                        height: 110,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF0F1520),
                          border: Border.all(
                            color: AppColors.primaryRed,
                            width: 3.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primaryRed.withValues(
                                alpha: 0.3 + (_pulseController.value * 0.25),
                              ),
                              blurRadius: 20,
                              spreadRadius: 3,
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            '0$_secondsLeft',
                            style: GoogleFonts.chakraPetch(
                              fontSize: 40,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 28),

                // Cancel PIN input
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'CÓDIGO PARA CANCELAR ALERTA',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _pinController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  obscureText: true,
                  obscuringCharacter: '•',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 6,
                    color: Colors.white,
                  ),
                  decoration: InputDecoration(
                    hintText: '----- [TECLADO NUMÉRICO]',
                    hintStyle: GoogleFonts.inter(
                      fontSize: 12,
                      letterSpacing: 1.0,
                      color: AppColors.textMuted,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                  ),
                ),

                const SizedBox(height: 18),

                // Botón de Cancelación con Huella Digital
                if (_canUseBiometrics) ...[
                  ElevatedButton.icon(
                    onPressed: _onBiometricCancel,
                    icon: const Icon(Icons.fingerprint, color: Colors.white, size: 24),
                    label: Text(
                      'CANCELAR CON HUELLA',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accentBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 4,
                      shadowColor: AppColors.accentBlue.withValues(alpha: 0.4),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],

                // Cancel Button (Green)
                ElevatedButton(
                  onPressed: _onCancel,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accentGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 4,
                    shadowColor: AppColors.accentGreen.withValues(alpha: 0.4),
                  ),
                  child: Text(
                    'CANCELAR CON PIN',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Send Now Button (Outline Red)
                OutlinedButton(
                  onPressed: _onAutoSend,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    side: const BorderSide(color: AppColors.primaryRed, width: 1.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    'ENVIAR AHORA',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primaryRed,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
}
