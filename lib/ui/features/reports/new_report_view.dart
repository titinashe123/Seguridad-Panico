import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_theme.dart';

class NewReportView extends StatefulWidget {
  final String initialCategory;

  const NewReportView({
    super.key,
    this.initialCategory = 'ROBO',
  });

  @override
  State<NewReportView> createState() => _NewReportViewState();
}

class _NewReportViewState extends State<NewReportView> {
  final _descriptionController = TextEditingController();
  final String _currentAddress = 'Av. de la Constitución 145';
  double _lat = -12.04637;
  double _lon = -77.02987;
  bool _isRefreshingGps = false;

  final List<String> _evidenceList = [
    'placeholder_doc',
    'night_photo',
  ];

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  void _refreshLocation() async {
    setState(() {
      _isRefreshingGps = true;
    });
    await Future.delayed(const Duration(milliseconds: 600));
    if (mounted) {
      setState(() {
        _lat = -12.04637 + (DateTime.now().millisecond % 50) * 0.00001;
        _lon = -77.02987 + (DateTime.now().second % 50) * 0.00001;
        _isRefreshingGps = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Coordenadas GPS actualizadas con precisión militar.'),
          backgroundColor: AppColors.surfaceVariant,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _addEvidence() {
    setState(() {
      _evidenceList.add('new_evidence_${_evidenceList.length + 1}');
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Evidencia adjuntada al reporte.'),
        backgroundColor: AppColors.surfaceVariant,
        duration: Duration(seconds: 1),
      ),
    );
  }

  void _sendReportViaWhatsApp() {
    showDialog(
      context: context,
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
          'El reporte fue enviado con éxito a la Central de Video Vigilancia.',
          style: GoogleFonts.inter(fontSize: 14, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pop();
            },
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
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
                  Text(
                    'NUEVO REPORTE',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  // Category Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF201614),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFFFF6D00),
                        width: 1.2,
                      ),
                    ),
                    child: Text(
                      widget.initialCategory,
                      style: GoogleFonts.chakraPetch(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFFFF6D00),
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Form content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Incident Details
                    Text(
                      'DETALLES DEL INCIDENTE',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textSecondary,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      height: 140,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: TextField(
                        controller: _descriptionController,
                        maxLines: null,
                        expands: true,
                        textAlignVertical: TextAlignVertical.top,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: AppColors.textPrimary,
                        ),
                        decoration: InputDecoration(
                          hintText:
                              'Describe la situación... (ej. sospechoso con abrigo negro huyendo hacia el norte)',
                          hintStyle: GoogleFonts.inter(
                            fontSize: 13,
                            color: AppColors.textMuted,
                            height: 1.4,
                          ),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: const EdgeInsets.all(16),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Add Evidence
                    Text(
                      'AGREGAR EVIDENCIA (FOTO/VIDEO)',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textSecondary,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 80,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          // Add Button
                          InkWell(
                            onTap: _addEvidence,
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: AppColors.border,
                                  width: 1.2,
                                ),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.camera_alt_outlined,
                                    color: Color(0xFFFF6D00),
                                    size: 24,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'AÑADIR',
                                    style: GoogleFonts.inter(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.textSecondary,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),

                          // Evidence Thumbnail 1 (white clean mock sheet)
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.white.withValues(alpha: 0.1),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.insert_drive_file_outlined,
                                color: Color(0xFF64748B),
                                size: 28,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),

                          // Evidence Thumbnail 2 (night road tactical photo preview)
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              color: const Color(0xFF1B2230),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppColors.border),
                              gradient: const LinearGradient(
                                colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            child: Stack(
                              children: [
                                const Center(
                                  child: Icon(
                                    Icons.car_crash_rounded,
                                    color: Color(0xFF94A3B8),
                                    size: 32,
                                  ),
                                ),
                                Positioned(
                                  bottom: 4,
                                  left: 4,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.7),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'CAM-01',
                                      style: TextStyle(fontSize: 8, color: Colors.white70),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 28),

                    // Current GPS Location Card
                    Text(
                      'UBICACIÓN ACTUAL GPS',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textSecondary,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          // GPS Radar Icon
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF0D2520),
                              border: Border.all(
                                color: AppColors.accentGreen.withValues(alpha: 0.5),
                              ),
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.my_location,
                                color: AppColors.accentGreen,
                                size: 18,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _currentAddress,
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Lat: ${_lat.toStringAsFixed(5)}, Lon: ${_lon.toStringAsFixed(5)}',
                                  style: GoogleFonts.chakraPetch(
                                    fontSize: 11,
                                    color: AppColors.textSecondary,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: _isRefreshingGps ? null : _refreshLocation,
                            icon: _isRefreshingGps
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Color(0xFFFF6D00),
                                    ),
                                  )
                                : const Icon(
                                    Icons.refresh_rounded,
                                    color: Color(0xFFFF6D00),
                                    size: 22,
                                  ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),

                    // WhatsApp Action Button
                    ElevatedButton(
                      onPressed: _sendReportViaWhatsApp,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accentGreen,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 8,
                        shadowColor: AppColors.accentGreen.withValues(alpha: 0.4),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 26,
                            height: 26,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.chat_bubble_outline_rounded,
                                color: AppColors.accentGreen,
                                size: 16,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'ENVIAR REPORTE VÍA WHATSAPP',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 48),
                  ],
                ),
              ),
            ),

            // Footer note
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: const BoxDecoration(
                color: Color(0xFF0F141E),
                border: Border(
                  top: BorderSide(color: AppColors.borderSubtle),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.cell_tower_rounded,
                    color: Color(0xFFFF6D00),
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'El mensaje será enviado automáticamente a la Central de Cámaras para despacho inmediato.',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
