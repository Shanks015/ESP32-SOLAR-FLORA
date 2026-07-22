import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/supabase_service.dart';
import '../widgets/custom_widgets.dart';
import '../widgets/wifi_config_dialog.dart';

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



  // Telemetry state
  int _batteryPercentage = 85;
  int _previousBatteryPercentage = -1; // -1 means no previous reading yet
  bool _isCharging = false;
  Timer? _telemetryTimer;

  // Device connectivity states
  bool _isDeviceOnline = false;
  String _lastSeenText = 'Never';
  int _sleepInterval = 600; // default to 10 minutes

  // Daily watering schedule states
  bool _dailyWateringEnabled = false;
  String _dailyWateringTime = '08:00:00';

  @override
  void initState() {
    super.initState();



    _loadTelemetry();
    // Poll telemetry & schedule details from Supabase every 5 seconds (real-time)
    _telemetryTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _loadTelemetry();
    });
  }

  @override
  void dispose() {

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
            final newPercentage = telemetry['battery_percentage'] ?? 85;

            // Derive charging state from battery % trend
            if (_previousBatteryPercentage != -1) {
              if (newPercentage > _previousBatteryPercentage) {
                _isCharging = true;  // % went up → charging
              } else if (newPercentage < _previousBatteryPercentage) {
                _isCharging = false; // % went down → discharging
              }
              // If equal, keep previous state (no change)
            }
            _previousBatteryPercentage = newPercentage;
            _batteryPercentage = newPercentage;

            final lastSeenStr = telemetry['created_at'];
            if (lastSeenStr != null) {
              final lastSeen = DateTime.parse(lastSeenStr).toLocal();
              final now = DateTime.now();
              final diff = now.difference(lastSeen);
              
              // ESP32 uploads every 5 seconds or goes to sleep for _sleepInterval seconds.
              // If the sleep interval is > 12 seconds (deep sleep), use _sleepInterval + 60s buffer.
              // Otherwise, if active real-time mode, check within 12 seconds.
              final timeout = _sleepInterval > 12 ? _sleepInterval + 60 : 12;
              _isDeviceOnline = diff.inSeconds <= timeout;
              if (!_isDeviceOnline) {
                _isCharging = false;
              }
              
              if (diff.inSeconds < 60) {
                _lastSeenText = 'Just now';
              } else if (diff.inMinutes < 60) {
                _lastSeenText = '${diff.inMinutes}m ago';
              } else if (diff.inHours < 24) {
                _lastSeenText = '${diff.inHours}h ago';
              } else {
                _lastSeenText = '${diff.inDays}d ago';
              }
            } else {
              _isDeviceOnline = false;
              _isCharging = false;
              _lastSeenText = 'Never';
            }

            if (!_isWatering && (telemetry['motor_active'] ?? false)) {
              _triggerLocalWateringUI();
            }
          });
        } else if (mounted) {
          setState(() {
            _isDeviceOnline = false;
            _isCharging = false;
            _lastSeenText = 'Never';
          });
        }

        // Fetch profiles data for configs and daily schedule
        final profile = await _supabaseService.getProfile(userId);
        if (profile != null && mounted) {
          setState(() {
            _wateringDuration = profile['watering_duration'] ?? 15;
            _dailyWateringEnabled = profile['daily_watering_enabled'] ?? false;
            _dailyWateringTime = profile['daily_watering_time'] ?? '08:00:00';
            _sleepInterval = profile['sleep_interval'] ?? 600;

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

  // --- Daily Watering Schedule Functions ---

  Future<void> _toggleDailyWatering(bool value) async {
    setState(() {
      _dailyWateringEnabled = value;
    });
    try {
      final userId = _supabaseService.getCurrentUser()?.id;
      if (userId != null) {
        await _supabaseService.updateProfile({
          'daily_watering_enabled': value,
        });
      }
    } catch (e) {
      print('Error toggling daily schedule: $e');
    }
  }

  Future<void> _selectDailyWateringTime() async {
    int initialHour = 8;
    int initialMinute = 0;
    try {
      final parts = _dailyWateringTime.split(':');
      initialHour = int.parse(parts[0]);
      initialMinute = int.parse(parts[1]);
    } catch (_) {}

    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initialHour, minute: initialMinute),
    );

    if (picked != null) {
      final formattedTime = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}:00';
      setState(() {
        _dailyWateringTime = formattedTime;
      });
      try {
        final userId = _supabaseService.getCurrentUser()?.id;
        if (userId != null) {
          await _supabaseService.updateProfile({
            'daily_watering_time': formattedTime,
          });
        }
      } catch (e) {
        print('Error saving daily watering time: $e');
      }
    }
  }

  String _formatTimeString(String timeStr) {
    try {
      final parts = timeStr.split(':');
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);
      final ampm = hour >= 12 ? 'PM' : 'AM';
      final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
      return '${displayHour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')} $ampm';
    } catch (_) {
      return timeStr;
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
      onTap: _isDeviceOnline ? () => _setDelayTimer(minutes) : null,
      borderRadius: BorderRadius.circular(12),
      child: Opacity(
        opacity: _isDeviceOnline ? 1.0 : 0.5,
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color scaffoldBg = isDark ? const Color(0xFF0F1813) : const Color(0xFFF1FCF1);
    final Color cardColor = isDark ? const Color(0xFF16221A) : Colors.white;
    final Color borderColor = isDark ? const Color(0xFF2A3D31) : const Color(0xFFDAE6DB);
    final Color textMain = isDark ? const Color(0xFFE0EAE1) : const Color(0xFF141E17);
    final Color textSecondary = isDark ? const Color(0xFF8B9B90) : const Color(0xFF424845);
    final Color primaryColor = isDark ? const Color(0xFFB6CBC2) : const Color(0xFF4F635B);
    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: const CustomAppBar(title: 'Solak'),
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
                          const SizedBox(height: 12),
                          
                          // Connection Status badge
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _isDeviceOnline ? const Color(0xFF41B883) : Colors.grey,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _isDeviceOnline
                                    ? 'Device Online'
                                    : 'Device Offline (Last seen: $_lastSeenText)',
                                style: GoogleFonts.manrope(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: _isDeviceOnline ? const Color(0xFF41B883) : textSecondary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Offline Banner Alert
                          if (!_isDeviceOnline) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFDAD6),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFFFB4AB)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.warning_amber_rounded, color: Color(0xFF410002)),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          'Device is offline. Controls are disabled until the device wakes up and reconnects.',
                                          style: GoogleFonts.manrope(
                                            fontSize: 12,
                                            color: const Color(0xFF410002),
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  InkWell(
                                    onTap: () {
                                      showDialog(
                                        context: context,
                                        builder: (context) => const WifiConfigDialog(),
                                      );
                                    },
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.bluetooth, size: 16, color: Color(0xFF410002)),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Configure WiFi via Bluetooth',
                                          style: GoogleFonts.manrope(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w800,
                                            color: const Color(0xFF410002),
                                            decoration: TextDecoration.underline,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],

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
                                children: [
                                  Center(
                                    child: ClipOval(
                                      child: Image.network(
                                        'https://images.unsplash.com/photo-1463936575829-25148e1db1b8?q=80&w=300&auto=format&fit=crop',
                                        width: 220,
                                        height: 220,
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, error, stackTrace) {
                                          return Container(
                                            width: 220,
                                            height: 220,
                                            decoration: const BoxDecoration(
                                              gradient: LinearGradient(
                                                colors: [
                                                  Color(0xFFE8F5E9),
                                                  Color(0xFFC8E6C9),
                                                ],
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                              ),
                                            ),
                                            child: const Icon(
                                              Icons.local_florist,
                                              size: 80,
                                              color: Color(0xFF4F635B),
                                            ),
                                          );
                                        },
                                        loadingBuilder: (context, child, loadingProgress) {
                                          if (loadingProgress == null) return child;
                                          return Container(
                                            width: 220,
                                            height: 220,
                                            color: isDark ? const Color(0xFF16221A) : const Color(0xFFF1FCF1),
                                            child: const Center(
                                              child: CircularProgressIndicator(
                                                valueColor: AlwaysStoppedAnimation(Color(0xFF4F635B)),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                  // Watering Overlay
                                  if (_isWatering)
                                    Positioned.fill(
                                      child: AnimatedOpacity(
                                        duration: const Duration(milliseconds: 300),
                                        opacity: _isWatering ? 1.0 : 0.0,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: const Color(0xFF4F6074).withOpacity(0.85),
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
                            onPressed: (_isWatering || !_isDeviceOnline) ? null : _startWatering,
                            icon: const Icon(Icons.water_drop, size: 18),
                            label: Text(
                              _isWatering 
                                  ? 'WATERING...' 
                                  : (!_isDeviceOnline ? 'DEVICE OFFLINE' : 'WATER NOW'),
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
                                        onChanged: _isDeviceOnline ? (val) {
                                          if (val != null) {
                                            _updateWateringDuration(val);
                                          }
                                        } : null,
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
                                        onPressed: _isDeviceOnline ? _cancelDelayTimer : null,
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

                          // --- Daily Watering Schedule Card ---
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
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(Icons.alarm, color: primaryColor),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Daily Schedule',
                                          style: GoogleFonts.manrope(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                            color: textMain,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Switch(
                                      value: _dailyWateringEnabled,
                                      onChanged: _isDeviceOnline ? _toggleDailyWatering : null,
                                      activeColor: primaryColor,
                                      activeTrackColor: isDark ? const Color(0xFF1E3226) : const Color(0xFFDFEBE0),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Automatically water your plant at this time every day:',
                                  style: GoogleFonts.manrope(
                                    fontSize: 14,
                                    color: textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                InkWell(
                                  onTap: _isDeviceOnline ? _selectDailyWateringTime : null,
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    decoration: BoxDecoration(
                                      color: isDark ? const Color(0xFF16221A) : const Color(0xFFF1FCF1),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: borderColor),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'Scheduled Time',
                                          style: GoogleFonts.manrope(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: textMain,
                                          ),
                                        ),
                                        Row(
                                          children: [
                                            Text(
                                              _formatTimeString(_dailyWateringTime),
                                              style: GoogleFonts.manrope(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w800,
                                                color: primaryColor,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Icon(Icons.edit, size: 16, color: primaryColor),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
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
