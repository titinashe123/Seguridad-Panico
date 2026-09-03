import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_theme.dart';
import '../home/home_view.dart';
import '../reports/new_report_view.dart';
import '../auth/login_view.dart';

class MainLayoutView extends StatefulWidget {
  const MainLayoutView({super.key});

  @override
  State<MainLayoutView> createState() => _MainLayoutViewState();
}

class _MainLayoutViewState extends State<MainLayoutView> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final screens = [
      HomeView(
        onNavigateToReports: () {
          setState(() {
            _currentIndex = 1;
          });
        },
      ),
      const _ReportsListView(),
      const _ProfileView(),
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(
            top: BorderSide(color: AppColors.border, width: 1.0),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          backgroundColor: AppColors.surface,
          selectedItemColor: AppColors.primaryRed,
          unselectedItemColor: AppColors.textMuted,
          type: BottomNavigationBarType.fixed,
          selectedLabelStyle: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
          unselectedLabelStyle: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
          items: const [
            BottomNavigationBarItem(
              icon: Padding(
                padding: EdgeInsets.only(bottom: 4.0),
                child: Icon(Icons.cancel_outlined, size: 22),
              ),
              label: 'Inicio',
            ),
            BottomNavigationBarItem(
              icon: Padding(
                padding: EdgeInsets.only(bottom: 4.0),
                child: Icon(Icons.segment_rounded, size: 22),
              ),
              label: 'Reportes',
            ),
            BottomNavigationBarItem(
              icon: Padding(
                padding: EdgeInsets.only(bottom: 4.0),
                child: Icon(Icons.person_outline_rounded, size: 22),
              ),
              label: 'Perfil',
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportsListView extends StatelessWidget {
  const _ReportsListView();

  @override
  Widget build(BuildContext context) {
    final sampleReports = [
      {
        'id': 'REP-9042',
        'type': 'ROBO',
        'desc': 'Sujeto sospechoso forzando cerradura en Jr. Bolognesi',
        'time': 'Hace 12 min',
        'status': 'ENVIADO',
        'badgeColor': AppColors.primaryRed,
        'statusColor': AppColors.accentGreen,
      },
      {
        'id': 'REP-9039',
        'type': 'ACCIDENTE',
        'desc': 'Colisión vehicular leve entre dos automóviles en cruce',
        'time': 'Hace 1 hora',
        'status': 'ENVIADO',
        'badgeColor': const Color(0xFFFF8A65),
        'statusColor': AppColors.accentGreen,
      },
      {
        'id': 'REP-9021',
        'type': 'GRESCA',
        'desc': 'Altercado en vía pública frente al parque central',
        'time': 'Ayer 22:40',
        'status': 'ENVIADO',
        'badgeColor': const Color(0xFFFF7043),
        'statusColor': AppColors.accentGreen,
      },
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Text(
          'HISTORIAL DE REPORTES',
          style: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            color: Colors.white,
          ),
        ),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline, color: AppColors.primaryRed),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const NewReportView()),
              );
            },
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: sampleReports.length,
        itemBuilder: (context, index) {
          final item = sampleReports[index];
          final badgeColor = item['badgeColor'] as Color;
          final statusColor = item['statusColor'] as Color;

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF22161A),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: badgeColor.withValues(alpha: 0.5)),
                      ),
                      child: Text(
                        item['type'] as String,
                        style: GoogleFonts.chakraPetch(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: badgeColor,
                        ),
                      ),
                    ),
                    Text(
                      item['time'] as String,
                      style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  item['desc'] as String,
                  style: GoogleFonts.inter(fontSize: 13, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      item['id'] as String,
                      style: GoogleFonts.chakraPetch(fontSize: 10, color: AppColors.textMuted),
                    ),
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: statusColor,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          item['status'] as String,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: statusColor,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ProfileView extends StatelessWidget {
  const _ProfileView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Text(
          'PERFIL CIUDADANO',
          style: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            color: Colors.white,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Center(
              child: Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.surface,
                  border: Border.all(color: AppColors.accentOrange, width: 2),
                ),
                child: const Icon(
                  Icons.person,
                  size: 52,
                  color: AppColors.accentOrange,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Carlos Mendoza Ruiz',
              style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'DNI: 12345678 • Registro Civil Activo',
              style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 24),
            _buildProfileTile(Icons.verified_outlined, 'Estado de Verificación', 'Validado RENIEC'),
            _buildProfileTile(Icons.phone_outlined, 'Teléfono Enlazado', '+51 999 999 999'),
            _buildProfileTile(Icons.security_outlined, 'Cifrado de Comunicaciones', 'AES-256 Activo'),
            const SizedBox(height: 32),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginView()),
                  (route) => false,
                );
              },
              icon: const Icon(Icons.logout, color: AppColors.primaryRed),
              label: Text(
                'CERRAR SESIÓN',
                style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: AppColors.primaryRed),
              ),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                side: const BorderSide(color: AppColors.primaryRed),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileTile(IconData icon, String title, String subtitle) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.accentOrange, size: 20),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
              Text(subtitle, style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
        ],
      ),
    );
  }
}
