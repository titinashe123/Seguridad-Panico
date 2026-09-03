import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/alert_category.dart';
import '../emergency/emergency_countdown_dialog.dart';
import '../reports/new_report_view.dart';

class HomeView extends StatefulWidget {
  final VoidCallback? onNavigateToReports;

  const HomeView({super.key, this.onNavigateToReports});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _triggerDirectSosAlert() {
    EmergencyCountdownDialog.show(
      context,
      alertType: 'ROBO',
      isDirectWhatsAppApi: true,
    );
  }

  void _triggerCategoryEmergencyAlert(String categoryName) {
    if (categoryName.toUpperCase() == 'PERSONALIZADO') {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const NewReportView(initialCategory: 'PERSONALIZADO'),
        ),
      );
      return;
    }

    EmergencyCountdownDialog.show(
      context,
      alertType: categoryName,
      isDirectWhatsAppApi: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final categories = AlertCategory.defaultCategories;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 22.0, vertical: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header with Status and Avatar
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: AppColors.accentGreen,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'SISTEMA EN LÍNEA',
                            style: GoogleFonts.chakraPetch(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textMuted,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Hola, Usuario',
                        style: GoogleFonts.inter(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  // Tactical Avatar
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFFFF6D00),
                        width: 1.8,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFF6D00).withValues(alpha: 0.3),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: Container(
                        color: const Color(0xFF161F2E),
                        child: const Icon(
                          Icons.person_outline_rounded,
                          color: Color(0xFFFF8A65),
                          size: 26,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 28),

              // Central Pulsing Emergency Button
              Center(
                child: GestureDetector(
                  onTap: _triggerDirectSosAlert,
                  child: AnimatedBuilder(
                    animation: _pulseAnimation,
                    builder: (context, child) {
                      return SizedBox(
                        width: 230,
                        height: 230,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Outer ring 1
                            Container(
                              width: 220 * _pulseAnimation.value,
                              height: 220 * _pulseAnimation.value,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.primaryRed.withValues(
                                    alpha: 0.15 * (2.0 - _pulseAnimation.value),
                                  ),
                                  width: 1.5,
                                ),
                              ),
                            ),
                            // Outer ring 2
                            Container(
                              width: 185 * _pulseAnimation.value,
                              height: 185 * _pulseAnimation.value,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.primaryRed.withValues(
                                    alpha: 0.3 * (2.0 - _pulseAnimation.value),
                                  ),
                                  width: 1.5,
                                ),
                              ),
                            ),
                            // Inner Main Core Button
                            Container(
                              width: 148,
                              height: 148,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: const RadialGradient(
                                  colors: [
                                    Color(0xFFFF5252),
                                    Color(0xFFFF3B30),
                                    Color(0xFFC62828),
                                  ],
                                  stops: [0.2, 0.7, 1.0],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.primaryRed.withValues(alpha: 0.55),
                                    blurRadius: 30,
                                    spreadRadius: 6,
                                  ),
                                ],
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white.withValues(alpha: 0.8),
                                        width: 1.8,
                                      ),
                                    ),
                                    child: const Center(
                                      child: Icon(
                                        Icons.priority_high_rounded,
                                        size: 20,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'REPORTAR\nEMERGENCIA',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white,
                                      letterSpacing: 0.8,
                                      height: 1.2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Categories Header Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'CATEGORÍAS DE ALERTA',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textSecondary,
                      letterSpacing: 1.0,
                    ),
                  ),
                  Text(
                    'SELECCIONE UNA',
                    style: GoogleFonts.chakraPetch(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMuted,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              // 2x3 Grid of Categories
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: categories.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.7,
                ),
                itemBuilder: (context, index) {
                  final cat = categories[index];
                  return InkWell(
                    onTap: () => _triggerCategoryEmergencyAlert(cat.name),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.border,
                          width: 1.2,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Icon(
                                cat.icon,
                                color: cat.iconColor,
                                size: 22,
                              ),
                              const Icon(
                                Icons.north_east_rounded,
                                color: AppColors.textMuted,
                                size: 16,
                              ),
                            ],
                          ),
                          Text(
                            cat.name,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
