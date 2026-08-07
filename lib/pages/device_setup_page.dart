import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:app_settings/app_settings.dart';
import '../services/supabase_service.dart';

class DeviceSetupPage extends StatefulWidget {
  const DeviceSetupPage({Key? key}) : super(key: key);

  @override
  State<DeviceSetupPage> createState() => _DeviceSetupPageState();
}

class _DeviceSetupPageState extends State<DeviceSetupPage>
    with TickerProviderStateMixin {
  final SupabaseService _supabaseService = SupabaseService();

  // Wizard state
  int _currentStep = 0;
  bool _isCheckingConnection = false;
  bool _isSendingCredentials = false;
  bool _isConnected = false;

  // WiFi data
  List<String> _availableNetworks = [];
  String? _selectedNetwork;
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _manualSsidController = TextEditingController();
  bool _obscurePassword = true;
  bool _useManualSsid = false;

  // Animations
  late AnimationController _pulseController;
  late AnimationController _checkController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _checkAnimation;

  // Page controller for smooth transitions
  late PageController _pageController;

  // Auto-check timer
  Timer? _autoCheckTimer;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _checkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _checkAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _checkController, curve: Curves.elasticOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _checkController.dispose();
    _pageController.dispose();
    _passwordController.dispose();
    _manualSsidController.dispose();
    _autoCheckTimer?.cancel();
    super.dispose();
  }

  // ============================================================
  // STEP NAVIGATION
  // ============================================================

  void _goToStep(int step) {
    setState(() => _currentStep = step);
    _pageController.animateToPage(
      step,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  // ============================================================
  // NETWORK OPERATIONS
  // ============================================================

  Future<void> _checkDeviceConnection() async {
    setState(() => _isCheckingConnection = true);

    try {
      final response = await http
          .get(Uri.parse('http://192.168.4.1/scan'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final networks = List<String>.from(data['networks'] ?? []);

        setState(() {
          _availableNetworks = networks;
          _isCheckingConnection = false;
          _isConnected = true;
        });

        // Move to network selection step
        _goToStep(2);
      } else {
        setState(() => _isCheckingConnection = false);
        _showError('Device responded but returned an error. Please try again.');
      }
    } catch (e) {
      setState(() => _isCheckingConnection = false);
      _showError(
          'Could not reach the Solak device. Make sure you are connected to the "Solak_Setup" Wi-Fi network.');
    }
  }

  Future<void> _rescanNetworks() async {
    setState(() => _isCheckingConnection = true);
    try {
      final response = await http
          .get(Uri.parse('http://192.168.4.1/rescan'))
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final networks = List<String>.from(data['networks'] ?? []);
        setState(() {
          _availableNetworks = networks;
          _isCheckingConnection = false;
        });
      } else {
        setState(() => _isCheckingConnection = false);
      }
    } catch (e) {
      setState(() => _isCheckingConnection = false);
      _showError('Failed to refresh networks. Please try again.');
    }
  }

  Future<void> _sendCredentials() async {
    final ssid =
        _useManualSsid ? _manualSsidController.text : _selectedNetwork;
    final password = _passwordController.text;

    if (ssid == null || ssid.isEmpty) {
      _showError('Please select or enter a Wi-Fi network name.');
      return;
    }

    setState(() => _isSendingCredentials = true);

    // Get the user ID
    final userId = _supabaseService.getCurrentUser()?.id ?? '';

    try {
      // 1. Send the credentials to the device
      final response = await http
          .post(
            Uri.parse('http://192.168.4.1/connect'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'ssid': ssid,
              'pass': password,
              'user_id': userId,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        setState(() => _isSendingCredentials = false);
        _showError('Device rejected the credentials. Please try again.');
        return;
      }

      // 2. Poll the device to see if it successfully connected to the router
      // We will check up to 15 times (15 seconds)
      bool connected = false;
      for (int i = 0; i < 15; i++) {
        await Future.delayed(const Duration(seconds: 1));
        
        try {
          final statusRes = await http
              .get(Uri.parse('http://192.168.4.1/status'))
              .timeout(const Duration(seconds: 2));
              
          if (statusRes.statusCode == 200) {
            final data = json.decode(statusRes.body);
            if (data['status'] == 'connected') {
              connected = true;
              break;
            }
          }
        } catch (_) {
          // If polling fails, the device might have rebooted or dropped the AP
          // We will just keep trying until the 15 attempts run out
        }
      }

      setState(() => _isSendingCredentials = false);

      if (connected) {
        _goToStep(4); // Success step
        _checkController.forward();
      } else {
        _showError('Device failed to connect to "$ssid". Please check the password and try again.');
      }
    } catch (e) {
      setState(() => _isSendingCredentials = false);
      _showError('Could not send credentials to the device. Ensure you are connected to "Solak_Setup".');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.manrope(fontSize: 14)),
        backgroundColor: const Color(0xFFBA1A1A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  // ============================================================
  // UI BUILDING
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0F1813) : const Color(0xFFF1FCF1);
    final cardColor =
        isDark ? const Color(0xFF1A2820) : Colors.white.withOpacity(0.85);
    final textColor =
        isDark ? const Color(0xFFE0EAE1) : const Color(0xFF141E17);
    final subtextColor =
        isDark ? const Color(0xFF8A9E90) : const Color(0xFF6B7F72);
    final accentColor = const Color(0xFF34D399);

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar
            _buildTopBar(isDark, textColor),

            // Progress indicator
            _buildProgressBar(accentColor, isDark),

            // Pages
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildWelcomeStep(
                      isDark, cardColor, textColor, subtextColor, accentColor),
                  _buildConnectStep(
                      isDark, cardColor, textColor, subtextColor, accentColor),
                  _buildSelectNetworkStep(
                      isDark, cardColor, textColor, subtextColor, accentColor),
                  _buildPasswordStep(
                      isDark, cardColor, textColor, subtextColor, accentColor),
                  _buildSuccessStep(
                      isDark, cardColor, textColor, subtextColor, accentColor),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(bool isDark, Color textColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withOpacity(0.08)
                    : Colors.black.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.arrow_back_ios_new,
                  size: 18, color: textColor.withOpacity(0.7)),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Device Setup',
            style: GoogleFonts.manrope(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: textColor,
            ),
          ),
          const Spacer(),
          Text(
            'Step ${_currentStep + 1} of 5',
            style: GoogleFonts.manrope(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: textColor.withOpacity(0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar(Color accentColor, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      child: Row(
        children: List.generate(5, (index) {
          final isActive = index <= _currentStep;
          final isCurrent = index == _currentStep;
          return Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeInOut,
              height: isCurrent ? 5 : 3,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: isActive
                    ? accentColor
                    : (isDark
                        ? Colors.white.withOpacity(0.1)
                        : Colors.black.withOpacity(0.08)),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ============================================================
  // STEP 0: WELCOME
  // ============================================================

  Widget _buildWelcomeStep(bool isDark, Color cardColor, Color textColor,
      Color subtextColor, Color accentColor) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 32),

          // Animated device icon
          ScaleTransition(
            scale: _pulseAnimation,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    accentColor.withOpacity(0.15),
                    accentColor.withOpacity(0.05),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Center(
                child: Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accentColor.withOpacity(0.12),
                    border: Border.all(
                        color: accentColor.withOpacity(0.3), width: 2),
                  ),
                  child: Icon(Icons.router_outlined,
                      size: 42, color: accentColor),
                ),
              ),
            ),
          ),

          const SizedBox(height: 32),

          Text(
            'Set Up Your\nSolak Device',
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: textColor,
              height: 1.2,
            ),
          ),

          const SizedBox(height: 12),

          Text(
            'Connect your solar-powered plant monitor\nto Wi-Fi in just a few simple steps.',
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
              fontSize: 15,
              fontWeight: FontWeight.w400,
              color: subtextColor,
              height: 1.5,
            ),
          ),

          const SizedBox(height: 40),

          // What you'll need section
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark
                    ? Colors.white.withOpacity(0.06)
                    : Colors.black.withOpacity(0.05),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'What you\'ll need:',
                  style: GoogleFonts.manrope(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 16),
                _buildChecklistItem(
                  Icons.power_settings_new,
                  'Your Solak device powered on',
                  textColor,
                  subtextColor,
                  accentColor,
                ),
                const SizedBox(height: 12),
                _buildChecklistItem(
                  Icons.wifi,
                  'Your home Wi-Fi name & password',
                  textColor,
                  subtextColor,
                  accentColor,
                ),
                const SizedBox(height: 12),
                _buildChecklistItem(
                  Icons.phone_android,
                  'This phone (to configure the device)',
                  textColor,
                  subtextColor,
                  accentColor,
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // Start button
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: () => _goToStep(1),
              style: ElevatedButton.styleFrom(
                backgroundColor: accentColor,
                foregroundColor: const Color(0xFF0A1F0F),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Let\'s Get Started',
                    style: GoogleFonts.manrope(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward, size: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChecklistItem(IconData icon, String text, Color textColor,
      Color subtextColor, Color accentColor) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: accentColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: accentColor),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.manrope(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: textColor.withOpacity(0.85),
            ),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // STEP 1: CONNECT TO SOLAK_SETUP
  // ============================================================

  Widget _buildConnectStep(bool isDark, Color cardColor, Color textColor,
      Color subtextColor, Color accentColor) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 20),

          // WiFi icon with animation
          ScaleTransition(
            scale: _pulseAnimation,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accentColor.withOpacity(0.1),
              ),
              child: Icon(Icons.wifi_tethering, size: 52, color: accentColor),
            ),
          ),

          const SizedBox(height: 28),

          Text(
            'Connect to Your Device',
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: textColor,
            ),
          ),

          const SizedBox(height: 10),

          Text(
            'Follow these steps to connect your phone\nto the Solak device\'s Wi-Fi hotspot.',
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
              fontSize: 14,
              color: subtextColor,
              height: 1.5,
            ),
          ),

          const SizedBox(height: 32),

          // Steps
          _buildInstructionStep(
            1,
            'Power On',
            'Make sure your Solak device is powered on.\nWait about 10 seconds for it to boot up.',
            Icons.power_settings_new,
            isDark,
            cardColor,
            textColor,
            subtextColor,
            accentColor,
          ),
          const SizedBox(height: 12),
          _buildInstructionStep(
            2,
            'Open Wi-Fi Settings',
            'Go to your phone\'s Wi-Fi settings and\nconnect to the network named "Solak_Setup".',
            Icons.wifi,
            isDark,
            cardColor,
            textColor,
            subtextColor,
            accentColor,
          ),
          const SizedBox(height: 12),
          _buildInstructionStep(
            3,
            'Stay Connected',
            'If your phone warns "No internet access",\ntap "Stay Connected" — this is expected!',
            Icons.check_circle_outline,
            isDark,
            cardColor,
            textColor,
            subtextColor,
            accentColor,
          ),

          const SizedBox(height: 28),

          // Open WiFi Settings button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: () async {
                // Open device WiFi settings reliably
                try {
                  await AppSettings.openAppSettings(type: AppSettingsType.wifi);
                } catch (_) {
                  _showError('Please open your Wi-Fi settings manually.');
                }
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: accentColor,
                side: BorderSide(color: accentColor.withOpacity(0.4)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.settings, size: 18),
              label: Text(
                'Open Wi-Fi Settings',
                style: GoogleFonts.manrope(
                    fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // I'm connected button
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _isCheckingConnection ? null : _checkDeviceConnection,
              style: ElevatedButton.styleFrom(
                backgroundColor: accentColor,
                foregroundColor: const Color(0xFF0A1F0F),
                disabledBackgroundColor: accentColor.withOpacity(0.4),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: _isCheckingConnection
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Color(0xFF0A1F0F),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Searching for device...',
                          style: GoogleFonts.manrope(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF0A1F0F),
                          ),
                        ),
                      ],
                    )
                  : Text(
                      'I\'m Connected to Solak_Setup',
                      style: GoogleFonts.manrope(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildInstructionStep(
    int number,
    String title,
    String subtitle,
    IconData icon,
    bool isDark,
    Color cardColor,
    Color textColor,
    Color subtextColor,
    Color accentColor,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.06)
              : Colors.black.withOpacity(0.05),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                '$number',
                style: GoogleFonts.manrope(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: accentColor,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.manrope(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: GoogleFonts.manrope(
                    fontSize: 12.5,
                    color: subtextColor,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // STEP 2: SELECT NETWORK
  // ============================================================

  Widget _buildSelectNetworkStep(bool isDark, Color cardColor, Color textColor,
      Color subtextColor, Color accentColor) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),

          // Success badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle, size: 16, color: accentColor),
                const SizedBox(width: 6),
                Text(
                  'Device Connected',
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: accentColor,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          Text(
            'Choose Your\nHome Wi-Fi',
            style: GoogleFonts.manrope(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: textColor,
              height: 1.2,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            'Select the Wi-Fi network your Solak device should connect to for sending plant data.',
            style: GoogleFonts.manrope(
              fontSize: 14,
              color: subtextColor,
              height: 1.5,
            ),
          ),

          const SizedBox(height: 20),

          // Refresh button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Available Networks',
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: textColor.withOpacity(0.7),
                ),
              ),
              GestureDetector(
                onTap: _isCheckingConnection ? null : _rescanNetworks,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _isCheckingConnection
                          ? SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: accentColor,
                              ),
                            )
                          : Icon(Icons.refresh, size: 14, color: accentColor),
                      const SizedBox(width: 4),
                      Text(
                        'Refresh',
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: accentColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Network list
          ..._availableNetworks.map((network) => _buildNetworkTile(
                network,
                isDark,
                cardColor,
                textColor,
                subtextColor,
                accentColor,
              )),

          const SizedBox(height: 16),

          // Manual entry toggle
          GestureDetector(
            onTap: () {
              setState(() {
                _useManualSsid = !_useManualSsid;
                if (_useManualSsid) {
                  _selectedNetwork = null;
                }
              });
            },
            child: Row(
              children: [
                Icon(
                  _useManualSsid
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 18,
                  color: subtextColor,
                ),
                const SizedBox(width: 4),
                Text(
                  _useManualSsid
                      ? 'Hide manual entry'
                      : 'Enter network name manually',
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: subtextColor,
                  ),
                ),
              ],
            ),
          ),

          if (_useManualSsid) ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: _manualSsidController,
              style: GoogleFonts.manrope(fontSize: 15, color: textColor),
              decoration: InputDecoration(
                hintText: 'Wi-Fi network name',
                hintStyle: GoogleFonts.manrope(color: subtextColor),
                prefixIcon:
                    Icon(Icons.wifi, color: subtextColor.withOpacity(0.6)),
                filled: true,
                fillColor: cardColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: isDark
                        ? Colors.white.withOpacity(0.08)
                        : Colors.black.withOpacity(0.06),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: accentColor, width: 1.5),
                ),
              ),
            ),
          ],

          const SizedBox(height: 24),

          // Next button
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed:
                  (_selectedNetwork != null || _useManualSsid) ? () => _goToStep(3) : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: accentColor,
                foregroundColor: const Color(0xFF0A1F0F),
                disabledBackgroundColor:
                    isDark ? Colors.white.withOpacity(0.06) : Colors.grey[200],
                disabledForegroundColor: subtextColor,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: Text(
                'Continue',
                style: GoogleFonts.manrope(
                    fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNetworkTile(String network, bool isDark, Color cardColor,
      Color textColor, Color subtextColor, Color accentColor) {
    final isSelected = _selectedNetwork == network;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedNetwork = network;
          _useManualSsid = false;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? accentColor.withOpacity(0.1) : cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? accentColor.withOpacity(0.5)
                : (isDark
                    ? Colors.white.withOpacity(0.06)
                    : Colors.black.withOpacity(0.05)),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.wifi,
              size: 20,
              color: isSelected ? accentColor : subtextColor,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                network,
                style: GoogleFonts.manrope(
                  fontSize: 15,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? accentColor : textColor,
                ),
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, size: 20, color: accentColor),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // STEP 3: ENTER PASSWORD
  // ============================================================

  Widget _buildPasswordStep(bool isDark, Color cardColor, Color textColor,
      Color subtextColor, Color accentColor) {
    final networkName =
        _useManualSsid ? _manualSsidController.text : (_selectedNetwork ?? '');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),

          // Lock icon
          Center(
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accentColor.withOpacity(0.1),
              ),
              child: Icon(Icons.lock_outline, size: 42, color: accentColor),
            ),
          ),

          const SizedBox(height: 28),

          Center(
            child: Text(
              'Enter Wi-Fi Password',
              style: GoogleFonts.manrope(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: textColor,
              ),
            ),
          ),

          const SizedBox(height: 8),

          Center(
            child: RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: GoogleFonts.manrope(
                    fontSize: 14, color: subtextColor, height: 1.5),
                children: [
                  const TextSpan(text: 'Enter the password for\n'),
                  TextSpan(
                    text: '"$networkName"',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, color: accentColor),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 32),

          // Network name display
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDark
                    ? Colors.white.withOpacity(0.06)
                    : Colors.black.withOpacity(0.05),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.wifi, size: 20, color: accentColor),
                const SizedBox(width: 12),
                Text(
                  networkName,
                  style: GoogleFonts.manrope(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => _goToStep(2),
                  child: Text(
                    'Change',
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: accentColor,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Password field
          TextFormField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            style: GoogleFonts.manrope(fontSize: 15, color: textColor),
            decoration: InputDecoration(
              hintText: 'Wi-Fi Password',
              hintStyle: GoogleFonts.manrope(color: subtextColor),
              prefixIcon:
                  Icon(Icons.lock_outline, color: subtextColor.withOpacity(0.6)),
              suffixIcon: IconButton(
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: subtextColor,
                  size: 20,
                ),
              ),
              filled: true,
              fillColor: cardColor,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: isDark
                      ? Colors.white.withOpacity(0.08)
                      : Colors.black.withOpacity(0.06),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: accentColor, width: 1.5),
              ),
            ),
          ),

          const SizedBox(height: 8),

          Text(
            'Leave empty if the network has no password.',
            style: GoogleFonts.manrope(
              fontSize: 12,
              color: subtextColor.withOpacity(0.7),
            ),
          ),

          const SizedBox(height: 32),

          // Connect button
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _isSendingCredentials ? null : _sendCredentials,
              style: ElevatedButton.styleFrom(
                backgroundColor: accentColor,
                foregroundColor: const Color(0xFF0A1F0F),
                disabledBackgroundColor: accentColor.withOpacity(0.4),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: _isSendingCredentials
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Color(0xFF0A1F0F),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Connecting device...',
                          style: GoogleFonts.manrope(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF0A1F0F),
                          ),
                        ),
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.send, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'Connect Device',
                          style: GoogleFonts.manrope(
                              fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
            ),
          ),

          const SizedBox(height: 16),

          // Back button
          Center(
            child: TextButton(
              onPressed: () => _goToStep(2),
              child: Text(
                '← Back to network selection',
                style: GoogleFonts.manrope(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: subtextColor,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // STEP 4: SUCCESS
  // ============================================================

  Widget _buildSuccessStep(bool isDark, Color cardColor, Color textColor,
      Color subtextColor, Color accentColor) {
    final networkName =
        _useManualSsid ? _manualSsidController.text : (_selectedNetwork ?? '');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 48),

          // Animated check mark
          ScaleTransition(
            scale: _checkAnimation,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accentColor.withOpacity(0.12),
                border:
                    Border.all(color: accentColor.withOpacity(0.3), width: 3),
              ),
              child: Icon(Icons.check_rounded, size: 60, color: accentColor),
            ),
          ),

          const SizedBox(height: 32),

          Text(
            'All Done!',
            style: GoogleFonts.manrope(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: textColor,
            ),
          ),

          const SizedBox(height: 12),

          Text(
            'Your Solak device is now connecting to',
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
              fontSize: 15,
              color: subtextColor,
              height: 1.5,
            ),
          ),
          Text(
            '"$networkName"',
            style: GoogleFonts.manrope(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: accentColor,
            ),
          ),

          const SizedBox(height: 32),

          // Info card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark
                    ? Colors.white.withOpacity(0.06)
                    : Colors.black.withOpacity(0.05),
              ),
            ),
            child: Column(
              children: [
                _buildInfoRow(
                  Icons.timer_outlined,
                  'It may take up to 30 seconds for your device to appear online.',
                  textColor,
                  subtextColor,
                  accentColor,
                ),
                const SizedBox(height: 16),
                _buildInfoRow(
                  Icons.phone_android,
                  'Reconnect your phone to your regular Wi-Fi network now.',
                  textColor,
                  subtextColor,
                  accentColor,
                ),
                const SizedBox(height: 16),
                _buildInfoRow(
                  Icons.eco_outlined,
                  'Your plant data will start appearing on the dashboard automatically.',
                  textColor,
                  subtextColor,
                  accentColor,
                ),
              ],
            ),
          ),

          const SizedBox(height: 36),

          // Go to Dashboard button
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pushReplacementNamed(context, '/status');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: accentColor,
                foregroundColor: const Color(0xFF0A1F0F),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Go to Dashboard',
                    style: GoogleFonts.manrope(
                        fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward, size: 20),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Setup another device
          TextButton(
            onPressed: () {
              // Reset state and go back to step 0
              setState(() {
                _currentStep = 0;
                _selectedNetwork = null;
                _passwordController.clear();
                _manualSsidController.clear();
                _useManualSsid = false;
                _isConnected = false;
                _availableNetworks = [];
              });
              _checkController.reset();
              _pageController.jumpToPage(0);
            },
            child: Text(
              'Set up another device',
              style: GoogleFonts.manrope(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: subtextColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text, Color textColor,
      Color subtextColor, Color accentColor) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: accentColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: accentColor),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.manrope(
              fontSize: 13,
              color: textColor.withOpacity(0.8),
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}
