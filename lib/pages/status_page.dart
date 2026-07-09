import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/supabase_service.dart';
import '../widgets/custom_widgets.dart';

class StatusPage extends StatefulWidget {
  const StatusPage({Key? key}) : super(key: key);

  @override
  State<StatusPage> createState() => _StatusPageState();
}

class _StatusPageState extends State<StatusPage> with TickerProviderStateMixin {
  final SupabaseService _supabaseService = SupabaseService();
  
  // Watering pump state
  bool _isWatering = false;
  double _waterProgress = 0.0;
  Timer? _wateringTimer;
  int _wateringDuration = 15; // Pump run duration (in seconds, default 15)

  // Scheduling states
  DateTime? _scheduledWateringTime;
  Timer? _countdownTimer;
  Duration _remainingTime = Duration.zero;
  int _timerTotalSeconds = 60; // Total countdown duration

  // Pulse animation for solar glow
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  // Flow animation for connector line
  late final AnimationController _flowController;
  late final Animation<double> _flowAnimation;

  // Telemetry state
  int _batteryPercentage = 85;
  bool _isCharging = true;
  Timer? _telemetryTimer;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.9, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _flowController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();

    _flowAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(_flowController);

    _loadTelemetry();
    // Poll telemetry & schedule details from Supabase every 5 seconds
    _telemetryTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _loadTelemetry();
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _flowController.dispose();
    _wateringTimer?.cancel();
    _countdownTimer?.cancel();
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
            _batteryPercentage = telemetry['battery_percentage'] ?? 85;
            _isCharging = telemetry['is_charging'] ?? true;
            if (!_isWatering && (telemetry['motor_active'] ?? false)) {
              _triggerLocalWateringUI();
            }
          });
        }

        // Fetch profiles data for timer configs
        final profile = await _supabaseService.getProfile(userId);
        if (profile != null && mounted) {
          setState(() {
            _wateringDuration = profile['watering_duration'] ?? 15;
            final scheduledTimeStr = profile['scheduled_watering_time'];
            if (scheduledTimeStr != null) {
              final target = DateTime.parse(scheduledTimeStr);
              if (_scheduledWateringTime == null || !_scheduledWateringTime!.isAtSameMomentAs(target)) {
                _scheduledWateringTime = target;
                _startLocalCountdown(target);
              }
            } else {
              if (_scheduledWateringTime != null) {
                _scheduledWateringTime = null;
                _countdownTimer?.cancel();
                _remainingTime = Duration.zero;
              }
            }
          });
        }
      }
    } catch (e) {
      print('Error loading telemetry/profile: $e');
    }
  }

  // Taps into profiles to toggle motor_active = true
  Future<void> _startWatering() async {
    if (_isWatering) return;

    _triggerLocalWateringUI();

    try {
      final userId = _supabaseService.getCurrentUser()?.id;
      if (userId != null) {
        await _supabaseService.updateProfile({'motor_active': true});
      }
    } catch (e) {
      print('Error starting pump command: $e');
    }
  }

  void _triggerLocalWateringUI() {
    if (_isWatering) return;

    setState(() {
      _isWatering = true;
      _waterProgress = 0.0;
    });

    // Run dynamic duration timer based on _wateringDuration setting
    final int stepMs = (_wateringDuration * 10).clamp(10, 1000); // 100 steps total
    _wateringTimer = Timer.periodic(Duration(milliseconds: stepMs), (timer) async {
      if (_waterProgress >= 1.0) {
        timer.cancel();
        if (mounted) {
          setState(() {
            _isWatering = false;
          });
        }
        try {
          final userId = _supabaseService.getCurrentUser()?.id;
          if (userId != null) {
            await _supabaseService.updateProfile({'motor_active': false});
          }
        } catch (e) {
          print('Error stopping pump command: $e');
        }
      } else {
        if (mounted) {
          setState(() {
            _waterProgress += 0.01;
          });
        }
      }
    });
  }

  // --- Scheduled Delay Timer Functions ---

  void _startLocalCountdown(DateTime targetTime) {
    _countdownTimer?.cancel();
    
    final initialDifference = targetTime.difference(DateTime.now());
    if (initialDifference.isNegative) {
      // The scheduled time passed while app was closed, trigger pump immediately
      _clearDbTimer();
      _startWatering();
      return;
    }

    setState(() {
      _remainingTime = initialDifference;
      _timerTotalSeconds = initialDifference.inSeconds.clamp(1, 86400);
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      final now = DateTime.now();
      if (now.isAfter(targetTime)) {
        timer.cancel();
        setState(() {
          _scheduledWateringTime = null;
          _remainingTime = Duration.zero;
        });
        await _clearDbTimer();
        await _startWatering(); // Start watering automatically!
      } else {
        if (mounted) {
          setState(() {
            _remainingTime = targetTime.difference(now);
          });
        }
      }
    });
  }

  Future<void> _setDelayTimer(int minutesDelay) async {
    final targetTime = DateTime.now().add(Duration(minutes: minutesDelay));
    setState(() {
      _scheduledWateringTime = targetTime;
      _timerTotalSeconds = minutesDelay * 60;
    });

    try {
      final userId = _supabaseService.getCurrentUser()?.id;
      if (userId != null) {
        await _supabaseService.updateProfile({
          'scheduled_watering_time': targetTime.toIso8601String(),
        });
      }
    } catch (e) {
      print('Error saving scheduled time: $e');
    }

    _startLocalCountdown(targetTime);
  }

  Future<void> _cancelDelayTimer() async {
    _countdownTimer?.cancel();
    setState(() {
      _scheduledWateringTime = null;
      _remainingTime = Duration.zero;
    });
    await _clearDbTimer();
  }

  Future<void> _clearDbTimer() async {
    try {
      final userId = _supabaseService.getCurrentUser()?.id;
      if (userId != null) {
        await _supabaseService.updateProfile({
          'scheduled_watering_time': null,
        });
      }
    } catch (e) {
      print('Error clearing timer in database: $e');
    }
  }

  Future<void> _updateWateringDuration(int seconds) async {
    setState(() {
      _wateringDuration = seconds;
    });
    try {
      final userId = _supabaseService.getCurrentUser()?.id;
      if (userId != null) {
        await _supabaseService.updateProfile({
          'watering_duration': seconds,
        });
      }
    } catch (e) {
      print('Error saving run duration: $e');
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  double _getCountdownProgress() {
    if (_timerTotalSeconds <= 0) return 0.0;
    final elapsed = _timerTotalSeconds - _remainingTime.inSeconds;
    return (elapsed / _timerTotalSeconds).clamp(0.0, 1.0);
  }

  Widget _buildTimerOption(int minutes, String label) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: () => _setDelayTimer(minutes),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E3226) : const Color(0xFFDFEBE0),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: GoogleFonts.manrope(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF4F635B),
          ),
        ),
      ),
    );
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
      appBar: const CustomAppBar(title: 'Solar Flora'),
      body: AmbientShaderBackground(
        isCharging: _isCharging,
        child: Stack(
          children: [
            SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const SizedBox(height: 24),
                          // Hero succulent card
                          Center(
                            child: Container(
                              width: 240,
                              height: 240,
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
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  // Succulent Image
                                  Image.network(
                                    'https://lh3.googleusercontent.com/aida/AP1WRLtDT9qJGUFJX8hoSga06y9T98JkOMMpzbcJL-p-41LuuLdzJ3pZOSpe5HjVpuAlZm58HLWyXTyTbsRR0qnwnTuJmDrIr9Vk-WYRHSAaOechtx8Wjk8GCFpm8vFAKkSNF5Zv6pAS9pXQY3PQESYWhKofvYvs84dVysNFUQNNV-sFRcbeVSLaE2PN5YtQRSCJBEuCRIzv4R4f2doSlyWpC9QxWXbR1pyvo0EWZsvUGgvHzMgex4ytRP4tqg0',
                                    width: 170,
                                    height: 170,
                                    fit: BoxFit.contain,
                                    errorBuilder: (context, error, stackTrace) =>
                                        Icon(Icons.spa, size: 70, color: primaryColor),
                                  ),

                                  // Watering Overlay State
                                  if (_isWatering)
                                    Container(
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: (isDark ? const Color(0xFF0F1813) : const Color(0xFFF1FCF1)).withOpacity(0.5),
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(120),
                                        child: BackdropFilter(
                                          filter: ColorFilter.mode(
                                            Colors.white.withOpacity(0.1),
                                            BlendMode.srcOver,
                                          ),
                                          child: Center(
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(
                                                  Icons.water_drop,
                                                  size: 42,
                                                  color: Color(0xFF4F6074),
                                                ),
                                                const SizedBox(height: 12),
                                                SizedBox(
                                                  width: 120,
                                                  height: 6,
                                                  child: ClipRRect(
                                                    borderRadius: BorderRadius.circular(3),
                                                    child: LinearProgressIndicator(
                                                      value: _waterProgress,
                                                      backgroundColor: isDark ? const Color(0xFF2A3D31) : const Color(0xFFE1E3DD),
                                                      valueColor: const AlwaysStoppedAnimation(Color(0xFF4F6074)),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(height: 8),
                                                Text(
                                                  'Hydrating...',
                                                  style: GoogleFonts.manrope(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                    color: textMain,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 36),

                          // Water Button
                          ElevatedButton.icon(
                            onPressed: _isWatering ? null : _startWatering,
                            icon: const Icon(Icons.water_drop, size: 18),
                            label: Text(
                              _isWatering ? 'WATERING...' : 'WATER NOW',
                              style: GoogleFonts.manrope(
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.8,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryColor,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 16),
                            ),
                          ),
                          const SizedBox(height: 24),

                          // --- Watering Timer Card ---
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(20.0),
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
                                    Icon(Icons.timer_outlined, color: primaryColor),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Watering Timer',
                                      style: GoogleFonts.manrope(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: textMain,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                if (_scheduledWateringTime == null) ...[
                                  Text(
                                    'Set a delay start timer for watering:',
                                    style: GoogleFonts.manrope(
                                      fontSize: 14,
                                      color: textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      _buildTimerOption(1, '1 Min'),
                                      _buildTimerOption(5, '5 Min'),
                                      _buildTimerOption(10, '10 Min'),
                                      _buildTimerOption(30, '30 Min'),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  Divider(color: borderColor),
                                  const SizedBox(height: 12),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Pump Run Duration:',
                                        style: GoogleFonts.manrope(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: textMain,
                                        ),
                                      ),
                                      DropdownButton<int>(
                                        value: _wateringDuration,
                                        dropdownColor: isDark ? const Color(0xFF16221A) : Colors.white,
                                        style: GoogleFonts.manrope(
                                          color: textMain,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        underline: Container(),
                                        items: const [
                                          DropdownMenuItem(value: 10, child: Text('10s')),
                                          DropdownMenuItem(value: 15, child: Text('15s')),
                                          DropdownMenuItem(value: 30, child: Text('30s')),
                                          DropdownMenuItem(value: 60, child: Text('1m')),
                                          DropdownMenuItem(value: 120, child: Text('2m')),
                                        ],
                                        onChanged: (val) {
                                          if (val != null) {
                                            _updateWateringDuration(val);
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                ] else ...[
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Next watering scheduled in:',
                                            style: GoogleFonts.manrope(
                                              fontSize: 13,
                                              color: textSecondary,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            _formatDuration(_remainingTime),
                                            style: GoogleFonts.manrope(
                                              fontSize: 24,
                                              fontWeight: FontWeight.w700,
                                              color: const Color(0xFFBA1A1A),
                                            ),
                                          ),
                                        ],
                                      ),
                                      OutlinedButton.icon(
                                        onPressed: _cancelDelayTimer,
                                        icon: const Icon(Icons.cancel, size: 16),
                                        label: Text(
                                          'Cancel',
                                          style: GoogleFonts.manrope(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: const Color(0xFFBA1A1A),
                                          side: const BorderSide(color: Color(0xFFBA1A1A)),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: _getCountdownProgress(),
                                      backgroundColor: isDark ? const Color(0xFF2A3D31) : const Color(0xFFE1E3DD),
                                      valueColor: AlwaysStoppedAnimation(primaryColor),
                                      minHeight: 6,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Indicators Section (Power Flow)
                          Container(
                            padding: const EdgeInsets.all(20.0),
                            decoration: BoxDecoration(
                              color: cardColor,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: borderColor),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                // Solar panel widget
                                Column(
                                  children: [
                                    Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        ScaleTransition(
                                          scale: _pulseAnimation,
                                          child: Container(
                                            width: 48,
                                            height: 48,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: isDark ? const Color(0xFF25394B) : const Color(0xFFD0E1F9),
                                            ),
                                          ),
                                        ),
                                        Icon(
                                          Icons.wb_sunny,
                                          color: isDark ? const Color(0xFF8B9B90) : const Color(0xFF4F6074),
                                          size: 28,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'SOLAR',
                                      style: GoogleFonts.manrope(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: textSecondary,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ],
                                ),

                                // Animated flow connector
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
                                        return FractionallySizedBox(
                                          alignment: Alignment.centerLeft,
                                          widthFactor: 1.0,
                                          child: LayoutBuilder(
                                            builder: (context, constraints) {
                                              return CustomPaint(
                                                painter: _FlowLinePainter(
                                                  progress: _flowAnimation.value,
                                                  color: flowLineColor,
                                                ),
                                              );
                                            },
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ),

                                // Battery Widget
                                Column(
                                  children: [
                                    Container(
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: isDark ? const Color(0xFF1E3226) : const Color(0xFFDFEBE0),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(0.02),
                                            blurRadius: 4,
                                          ),
                                        ],
                                      ),
                                      child: Center(
                                        child: Container(
                                          width: 14,
                                          height: 24,
                                          decoration: BoxDecoration(
                                            border: Border.all(color: textSecondary, width: 1.5),
                                            borderRadius: BorderRadius.circular(2),
                                          ),
                                          padding: const EdgeInsets.all(1.5),
                                          child: Align(
                                            alignment: Alignment.bottomCenter,
                                            child: Container(
                                              width: double.infinity,
                                              height: 18 * (_batteryPercentage / 100.0),
                                              decoration: BoxDecoration(
                                                color: flowLineColor,
                                                borderRadius: BorderRadius.circular(0.5),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'BATTERY',
                                      style: GoogleFonts.manrope(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: textSecondary,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Navigation Bar
                  const CustomNavBar(activeIndex: 0),
                ],
              ),
            ),
          ],
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