import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/supabase_service.dart';
import '../widgets/custom_widgets.dart';

class EnergyPage extends StatefulWidget {
  const EnergyPage({Key? key}) : super(key: key);

  @override
  State<EnergyPage> createState() => _EnergyPageState();
}

class _EnergyPageState extends State<EnergyPage> with TickerProviderStateMixin {
  final SupabaseService _supabaseService = SupabaseService();
  int _batteryPercentage = 82;
  bool _isCharging = true;
  Timer? _telemetryTimer;

  // Pulse animation for charge indicator
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  // Flow animation for power flow connection
  late final AnimationController _flowController;
  late final Animation<double> _flowAnimation;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _flowController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();

    _flowAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(_flowController);

    _loadTelemetry();
    // Poll telemetry data every 5 seconds
    _telemetryTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _loadTelemetry();
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _flowController.dispose();
    _telemetryTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadTelemetry() async {
    try {
      final userId = _supabaseService.getCurrentUser()?.id;
      if (userId != null) {
        final telemetry = await _supabaseService.getLatestTelemetry(userId);
        if (telemetry != null && mounted) {
          setState(() {
            _batteryPercentage = telemetry['battery_percentage'] ?? 82;
            _isCharging = telemetry['is_charging'] ?? true;
          });
        }
      }
    } catch (e) {
      print('Error loading telemetry: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    
    final Color scaffoldBg = isDark ? const Color(0xFF0F1813) : const Color(0xFFF1FCF1);
    final Color cardColor = isDark ? const Color(0xFF16221A) : Colors.white.withOpacity(0.7);
    final Color borderColor = isDark ? const Color(0xFF2A3D31) : Colors.white.withOpacity(0.5);
    final Color textMain = isDark ? const Color(0xFFE0EAE1) : const Color(0xFF141E17);
    final Color textSecondary = isDark ? const Color(0xFF8B9B90) : const Color(0xFF424845);
    
    final Color primaryColor = const Color(0xFF4F635B);
    final Color flowLineColor = isDark ? const Color(0xFF7AA58B) : const Color(0xFF4F635B);

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: const CustomAppBar(title: 'Solak'),
      body: AmbientShaderBackground(
        isCharging: _isCharging,
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                  child: Column(
                    children: [
                      const SizedBox(height: 24),
                      // Battery Status Circle
                      Center(
                        child: ScaleTransition(
                          scale: _pulseAnimation,
                          child: Container(
                            width: 180,
                            height: 180,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: cardColor,
                              border: Border.all(color: borderColor),
                              boxShadow: [
                                BoxShadow(
                                  color: primaryColor.withOpacity(isDark ? 0.2 : 0.08),
                                  blurRadius: 20,
                                  spreadRadius: 5,
                                ),
                              ],
                            ),
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '$_batteryPercentage%',
                                    style: GoogleFonts.manrope(
                                      fontSize: 40,
                                      fontWeight: FontWeight.w700,
                                      color: primaryColor,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _isCharging ? 'Charging' : 'Discharging',
                                    style: GoogleFonts.manrope(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: primaryColor,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Description
                      Text(
                        'Sufficient energy stored. System operating optimally on solar input.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.manrope(
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                          color: textSecondary,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 36),

                      // Power Flow section
                      Container(
                        padding: const EdgeInsets.all(16.0),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF16221A) : Colors.white.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: borderColor),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // Solar Panel Icon
                            Column(
                              children: [
                                Container(
                                  width: 54,
                                  height: 54,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isDark ? const Color(0xFF1E3226) : const Color(0xFFDFEBE0),
                                  ),
                                  child: Icon(
                                    Icons.solar_power,
                                    color: flowLineColor,
                                    size: 28,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Panel',
                                  style: GoogleFonts.manrope(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: textSecondary,
                                  ),
                                ),
                              ],
                            ),

                            // Flow Line
                            Expanded(
                              child: Container(
                                height: 4,
                                margin: const EdgeInsets.symmetric(horizontal: 16),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF2A3D31) : const Color(0xFFDAE6DB),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                                child: AnimatedBuilder(
                                  animation: _flowAnimation,
                                  builder: (context, child) {
                                    return CustomPaint(
                                      painter: _FlowLinePainter(
                                        progress: _flowAnimation.value,
                                        color: flowLineColor,
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),

                            // Battery Icon
                            Column(
                              children: [
                                Container(
                                  width: 54,
                                  height: 54,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isDark ? const Color(0xFF1E3226) : const Color(0xFFDFEBE0),
                                  ),
                                  child: Icon(
                                    _isCharging ? Icons.battery_charging_full : Icons.battery_full,
                                    color: flowLineColor,
                                    size: 28,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Battery',
                                  style: GoogleFonts.manrope(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Real-time Data Cards
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(16.0),
                              decoration: BoxDecoration(
                                color: cardColor,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: borderColor),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.wb_sunny, size: 18, color: flowLineColor),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Solar Input',
                                        style: GoogleFonts.manrope(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: flowLineColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.baseline,
                                    textBaseline: TextBaseline.alphabetic,
                                    children: [
                                      Text(
                                        '34',
                                        style: GoogleFonts.manrope(
                                          fontSize: 28,
                                          fontWeight: FontWeight.w700,
                                          color: textMain,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'W',
                                        style: GoogleFonts.manrope(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          color: textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(16.0),
                              decoration: BoxDecoration(
                                color: cardColor,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: borderColor),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.bolt, size: 18, color: Color(0xFF4F6074)),
                                      const SizedBox(width: 6),
                                      Text(
                                        'System Load',
                                        style: GoogleFonts.manrope(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: const Color(0xFF4F6074),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.baseline,
                                    textBaseline: TextBaseline.alphabetic,
                                    children: [
                                      Text(
                                        '12',
                                        style: GoogleFonts.manrope(
                                          fontSize: 28,
                                          fontWeight: FontWeight.w700,
                                          color: textMain,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'W',
                                        style: GoogleFonts.manrope(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          color: textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Info Details Card
                      Container(
                        padding: const EdgeInsets.all(16.0),
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: borderColor),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.favorite, size: 18, color: flowLineColor),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Battery Health',
                                      style: GoogleFonts.manrope(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: textMain,
                                      ),
                                    ),
                                  ],
                                ),
                                Text(
                                  'Excellent (98%)',
                                  style: GoogleFonts.manrope(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: flowLineColor,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Divider(color: borderColor),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.hourglass_empty, size: 18, color: flowLineColor),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Est. Time to Full',
                                      style: GoogleFonts.manrope(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: textMain,
                                      ),
                                    ),
                                  ],
                                ),
                                Text(
                                  '2h 15m',
                                  style: GoogleFonts.manrope(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
              const CustomNavBar(activeIndex: 1),
            ],
          ),
        ),
      ),
    );
  }
}

class _FlowLinePainter extends CustomPainter {
  final double progress;
  final Color color;

  _FlowLinePainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round;

    final double startX = size.width * progress;
    final double dashWidth = 12.0;

    canvas.drawLine(
      Offset(startX % size.width, size.height / 2),
      Offset((startX + dashWidth) % size.width, size.height / 2),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _FlowLinePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}