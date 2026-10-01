import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_theme.dart';
import '../home/home_view.dart';
import '../reports/new_report_view.dart';
import '../auth/login_view.dart';
import '../../../data/services/session_service.dart';
import '../../../data/services/report_storage_service.dart';

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

/// Vista dinámica de historial de reportes reales conectados a la base de datos Supabase
class _ReportsListView extends StatefulWidget {
  const _ReportsListView();

  @override
  State<_ReportsListView> createState() => _ReportsListViewState();
}

class _ReportsListViewState extends State<_ReportsListView> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _reports = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final reports = await ReportStorageService.loadAllReports();
      if (mounted) {
        setState(() {
          _reports = reports;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Error cargando historial de reportes: $e';
          _isLoading = false;
        });
      }
    }
  }

  Color _getBadgeColor(String type) {
    switch (type.toUpperCase()) {
      case 'ROBO':
        return AppColors.primaryRed;
      case 'ACCIDENTE':
        return const Color(0xFFFF8A65);
      case 'INCENDIO':
        return const Color(0xFFFF3D00);
      case 'GRESCA':
        return const Color(0xFFFF7043);
      case 'SECUESTRO':
        return const Color(0xFFD50000);
      case 'PERSONALIZADO':
        return const Color(0xFF00B0FF);
      default:
        return AppColors.accentOrange;
    }
  }

  String _formatDate(String? rawDate) {
    if (rawDate == null) return 'Reciente';
    try {
      final dt = DateTime.parse(rawDate).toLocal();
      final now = DateTime.now();
      final diff = now.difference(dt);

      if (diff.inMinutes < 60) {
        return 'Hace ${diff.inMinutes < 1 ? 1 : diff.inMinutes} min';
      } else if (diff.inHours < 24) {
        return 'Hace ${diff.inHours} h';
      } else {
        return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      }
    } catch (_) {
      return rawDate;
    }
  }

  void _showReportDetails(Map<String, dynamic> item) {
    final typeName = item['tipo_incidencia']?['nombre'] ?? 'EMERGENCIA';
    final idEstado = item['id_estado'];
    final statusName = item['estado_reporte']?['nombre'] ?? (idEstado == 1 ? 'Enviado' : 'No enviado');
    final isSent = idEstado == 1 || statusName.toString().toLowerCase() == 'enviado';
    final statusColor = isSent ? AppColors.accentGreen : AppColors.primaryRed;
    final statusIcon = isSent ? Icons.check_circle : Icons.cloud_off_rounded;
    final dateStr = _formatDate(item['fecha_hora']);
    final desc = item['descripcion'] ?? 'Sin descripción';
    final address = item['direccion_texto'] ?? 'Ubicación móvil GPS';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: _getBadgeColor(typeName), width: 1.5),
        ),
        title: Row(
          children: [
            Icon(Icons.shield, color: _getBadgeColor(typeName), size: 24),
            const SizedBox(width: 8),
            Text(
              'Reporte #REP-${item['id_reporte']}',
              style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _getBadgeColor(typeName).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _getBadgeColor(typeName)),
                ),
                child: Text(
                  typeName,
                  style: GoogleFonts.chakraPetch(fontWeight: FontWeight.bold, color: _getBadgeColor(typeName)),
                ),
              ),
              const SizedBox(height: 12),
              Text('Fecha y Hora:', style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted)),
              Text(dateStr, style: GoogleFonts.inter(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text('Ubicación registrada:', style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted)),
              Text(address, style: GoogleFonts.inter(fontSize: 13, color: Colors.white)),
              const SizedBox(height: 8),
              Text('Estado:', style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted)),
              Row(
                children: [
                  Icon(statusIcon, color: statusColor, size: 14),
                  const SizedBox(width: 4),
                  Text(statusName, style: GoogleFonts.inter(fontSize: 13, color: statusColor, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(color: AppColors.border),
              const SizedBox(height: 8),
              Text('Contenido del Despacho:', style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  desc,
                  style: GoogleFonts.inter(fontSize: 12, color: AppColors.textPrimary),
                ),
              ),
              if (item['fotos'] is List && (item['fotos'] as List).isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Evidencias Fotográficas (${(item['fotos'] as List).length}):',
                  style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: 110,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: (item['fotos'] as List).length,
                    itemBuilder: (ctx, fIdx) {
                      final fItem = (item['fotos'] as List)[fIdx];
                      final dataStr = (fItem is Map ? fItem['data'] : null)?.toString() ?? '';
                      Widget imgChild;
                      if (dataStr.startsWith('data:image')) {
                        try {
                          final b64 = dataStr.split(',').last;
                          imgChild = Image.memory(
                            base64Decode(b64),
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image, color: Colors.grey),
                          );
                        } catch (_) {
                          imgChild = const Icon(Icons.broken_image, color: Colors.grey);
                        }
                      } else {
                        imgChild = const Icon(Icons.image, color: Colors.grey);
                      }

                      return Container(
                        width: 110,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.border),
                          color: AppColors.background,
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: imgChild,
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('CERRAR', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
            icon: const Icon(Icons.refresh, color: AppColors.accentOrange),
            tooltip: 'Actualizar',
            onPressed: _loadReports,
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline, color: AppColors.primaryRed),
            tooltip: 'Nuevo Reporte',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const NewReportView()),
              );
              _loadReports();
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.accentOrange),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.cloud_off_rounded, size: 54, color: AppColors.primaryRed),
                        const SizedBox(height: 16),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(color: Colors.white70, fontSize: 14),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _loadReports,
                          icon: const Icon(Icons.refresh),
                          label: const Text('REINTENTAR'),
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.surfaceVariant),
                        ),
                      ],
                    ),
                  ),
                )
              : _reports.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.surface,
                                border: Border.all(color: AppColors.border),
                              ),
                              child: const Icon(
                                Icons.shield_outlined,
                                size: 48,
                                color: AppColors.textMuted,
                              ),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              'No hay reportes registrados aún',
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Todos los incidentes y alertas de pánico que despaches quedarán registrados aquí de forma permanente.',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      color: AppColors.accentOrange,
                      backgroundColor: AppColors.surface,
                      onRefresh: _loadReports,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _reports.length,
                        itemBuilder: (context, index) {
                          final item = _reports[index];
                          final typeName = item['tipo_incidencia']?['nombre'] ?? 'EMERGENCIA';
                          final idEstado = item['id_estado'];
                          final statusName = item['estado_reporte']?['nombre'] ?? (idEstado == 1 ? 'Enviado' : 'No enviado');
                          final isSent = idEstado == 1 || statusName.toString().toLowerCase() == 'enviado';
                          final statusColor = isSent ? AppColors.accentGreen : AppColors.primaryRed;
                          final badgeColor = _getBadgeColor(typeName);
                          final dateText = _formatDate(item['fecha_hora']);
                          final desc = item['descripcion'] ?? 'Sin descripción';
                          final id = item['id_reporte']?.toString() ?? '${index + 1}';

                          return InkWell(
                            onTap: () => _showReportDetails(item),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSent ? AppColors.border : AppColors.primaryRed.withValues(alpha: 0.4),
                                ),
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
                                          color: badgeColor.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: badgeColor.withValues(alpha: 0.5)),
                                        ),
                                        child: Text(
                                          typeName,
                                          style: GoogleFonts.chakraPetch(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                            color: badgeColor,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        dateText,
                                        style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    desc,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.inter(fontSize: 13, color: AppColors.textPrimary),
                                  ),
                                  if ((item['fotos'] is List && (item['fotos'] as List).isNotEmpty) || desc.contains('📸') || desc.contains('fotografía')) ...[
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        const Icon(Icons.photo_camera_rounded, size: 13, color: AppColors.accentOrange),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Evidencia fotográfica adjunta',
                                          style: GoogleFonts.inter(
                                            fontSize: 11,
                                            color: AppColors.accentOrange,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                  const SizedBox(height: 12),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'REP-$id',
                                        style: GoogleFonts.chakraPetch(fontSize: 10, color: AppColors.textMuted),
                                      ),
                                      Row(
                                        children: [
                                          Container(
                                            width: 7,
                                            height: 7,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: statusColor,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            statusName,
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
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}

/// Vista dinámica de Perfil Ciudadano conectado a la sesión activa y almacenamiento seguro
class _ProfileView extends StatefulWidget {
  const _ProfileView();

  @override
  State<_ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<_ProfileView> {
  Map<String, String> _userData = {
    'dni': '...',
    'name': 'Cargando...',
    'phone': '...',
  };
  String? _jwtToken;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    final user = await SessionService.getUserData();
    final token = await SessionService.getJwtToken();

    if (mounted) {
      setState(() {
        _userData = user;
        _jwtToken = token;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = _userData['name'] ?? 'Ciudadano';
    final dni = _userData['dni'] ?? '12345678';
    final phone = _userData['phone'] ?? '+51 999 999 999';

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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.accentOrange))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                children: [
                  Center(
                    child: Stack(
                      children: [
                        Container(
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
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: AppColors.accentGreen,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.check, size: 14, color: Colors.black),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    name,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.accentGreen.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.accentGreen.withValues(alpha: 0.5)),
                    ),
                    child: Text(
                      'CIUDADANO VERIFICADO',
                      style: GoogleFonts.chakraPetch(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: AppColors.accentGreen,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _buildProfileTile(Icons.badge_outlined, 'Documento Nacional (DNI)', dni),
                  _buildProfileTile(Icons.phone_outlined, 'Teléfono Vinculado (WhatsApp)', phone),
                  _buildProfileTile(
                    Icons.security_rounded,
                    'Seguridad de Sesión',
                    _jwtToken != null ? 'Token JWT 60 días activo (Almacenamiento Seguro)' : 'Sesión activa',
                  ),
                  _buildProfileTile(
                    Icons.lock_clock_outlined,
                    'PIN de Cancelación',
                    '4 dígitos protegidos mediante Hash Bcrypt',
                  ),
                  const SizedBox(height: 32),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await SessionService.clearSession();
                      if (!context.mounted) return;
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
