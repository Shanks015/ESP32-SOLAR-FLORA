import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../services/supabase_service.dart';

class WifiConfigDialog extends StatefulWidget {
  const WifiConfigDialog({Key? key}) : super(key: key);

  @override
  State<WifiConfigDialog> createState() => _WifiConfigDialogState();
}

class _WifiConfigDialogState extends State<WifiConfigDialog> {
  final SupabaseService _supabaseService = SupabaseService();
  // 0 = instructions, 1 = checking, 2 = ready (portal reachable), 3 = not reachable
  int _step = 0;
  bool _isChecking = false;
  Timer? _statusTimer;

  @override
  void dispose() {
    _statusTimer?.cancel();
    super.dispose();
  }

  // Try to reach the device portal to confirm phone is on Solak_Setup network
  Future<void> _checkDeviceReachable() async {
    setState(() { _isChecking = true; _step = 1; });
    try {
      final response = await http
          .get(Uri.parse('http://192.168.4.1/scan'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        setState(() { _step = 2; _isChecking = false; });
        return;
      }
    } catch (_) {}
    setState(() { _step = 3; _isChecking = false; });
  }

  Future<void> _openPortal() async {
    final user = _supabaseService.getCurrentUser();
    final uid = user?.id ?? '';
    final uri = Uri.parse('http://192.168.4.1/?user_id=$uid');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Open http://192.168.4.1 in your browser manually.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF0a0f0a);
    const green = Color(0xFF34d399);
    const cardBg = Color(0xFF16221a);
    const border = Color(0xFF2a3d30);

    return Dialog(
      backgroundColor: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: Color(0xFF2a3d30)),
      ),
      child: Container(
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.wifi_tethering, color: green, size: 22),
                    const SizedBox(width: 10),
                    Text(
                      'Device Wi-Fi Setup',
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey),
                  onPressed: () => Navigator.of(context).pop(),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Connect your Solak device to your home Wi-Fi',
              style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[500]),
            ),
            const SizedBox(height: 20),

            // Step content
            if (_step == 0) ...[
              _buildStepCard(
                cardBg: cardBg,
                border: border,
                steps: const [
                  _StepItem(
                    number: '1',
                    title: 'Power on your Solak device',
                    subtitle: 'Wait ~10 seconds for it to boot up',
                    icon: Icons.power_settings_new,
                  ),
                  _StepItem(
                    number: '2',
                    title: 'Connect to "Solak_Setup" Wi-Fi',
                    subtitle: 'Open your phone\'s Wi-Fi settings and select it',
                    icon: Icons.wifi,
                    highlight: 'Solak_Setup',
                  ),
                  _StepItem(
                    number: '3',
                    title: 'Keep connection if asked',
                    subtitle: '"No internet" warning is normal — tap "Keep"',
                    icon: Icons.info_outline,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _checkDeviceReachable,
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: Text(
                  "I'm Connected to Solak_Setup",
                  style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: green,
                  foregroundColor: bg,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],

            // Checking step
            if (_step == 1) ...[
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: border),
                ),
                child: Column(
                  children: [
                    const CircularProgressIndicator(color: green, strokeWidth: 2),
                    const SizedBox(height: 16),
                    Text(
                      'Checking device connection...',
                      style: GoogleFonts.poppins(color: green, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Make sure you selected Solak_Setup in Wi-Fi settings',
                      style: GoogleFonts.poppins(color: Colors.grey[500], fontSize: 11),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],

            // Device reachable — open portal
            if (_step == 2) ...[
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF0d2a1a),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: green.withOpacity(0.4)),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.check_circle, color: green, size: 40),
                    const SizedBox(height: 12),
                    Text(
                      'Device found!',
                      style: GoogleFonts.poppins(
                        color: green,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Tap below to open the setup page where you can select your home Wi-Fi and enter the password.',
                      style: GoogleFonts.poppins(color: Colors.grey[400], fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _openPortal,
                icon: const Icon(Icons.open_in_browser, size: 18),
                label: Text(
                  'Open Setup Page in Browser',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: green,
                  foregroundColor: bg,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: () => setState(() => _step = 0),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF2a3d30)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  'Back to Instructions',
                  style: GoogleFonts.poppins(color: Colors.grey[400], fontSize: 13),
                ),
              ),
            ],

            // Not reachable
            if (_step == 3) ...[
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF2a1010),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.redAccent.withOpacity(0.4)),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.wifi_off, color: Colors.redAccent, size: 40),
                    const SizedBox(height: 12),
                    Text(
                      'Device not reachable',
                      style: GoogleFonts.poppins(
                        color: Colors.redAccent,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Make sure you have connected your phone to "Solak_Setup" Wi-Fi and tapped "Keep Connection" if prompted.',
                      style: GoogleFonts.poppins(color: Colors.grey[400], fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _checkDeviceReachable,
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(
                  'Try Again',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: green,
                  foregroundColor: bg,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 10),
              // Manual fallback
              OutlinedButton.icon(
                onPressed: _openPortal,
                icon: const Icon(Icons.open_in_browser, size: 16, color: Colors.grey),
                label: Text(
                  'Open http://192.168.4.1 manually',
                  style: GoogleFonts.poppins(color: Colors.grey[400], fontSize: 12),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF2a3d30)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],

            const SizedBox(height: 8),
            Text(
              'The Solak_Setup hotspot shuts off automatically after 10 minutes once connected.',
              style: GoogleFonts.poppins(
                fontSize: 10,
                color: Colors.grey[600],
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepCard({
    required Color cardBg,
    required Color border,
    required List<_StepItem> steps,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: steps.map((s) => _buildStep(s)).toList(),
      ),
    );
  }

  Widget _buildStep(_StepItem item) {
    const green = Color(0xFF34d399);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: green.withOpacity(0.15),
              shape: BoxShape.circle,
              border: Border.all(color: green.withOpacity(0.4)),
            ),
            child: Center(
              child: Text(
                item.number,
                style: GoogleFonts.poppins(
                  color: green,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.subtitle,
                  style: GoogleFonts.poppins(
                    color: Colors.grey[500],
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StepItem {
  final String number;
  final String title;
  final String subtitle;
  final IconData icon;
  final String? highlight;

  const _StepItem({
    required this.number,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.highlight,
  });
}
