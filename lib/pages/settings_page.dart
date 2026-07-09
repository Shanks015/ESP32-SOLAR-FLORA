import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Required for Clipboard
import 'package:google_fonts/google_fonts.dart';
import '../services/supabase_service.dart';
import '../widgets/custom_widgets.dart';
import '../main.dart'; // Import themeModeNotifier to toggle global theme state

class SettingsPage extends StatefulWidget {
  const SettingsPage({Key? key}) : super(key: key);

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final SupabaseService _supabaseService = SupabaseService();
  Map<String, dynamic>? _profileData;
  bool _isLoading = true;
  String _userId = '';
  int _numberOfPlants = 3;
  bool _darkMode = false;
  bool _notifications = true;
  String _language = 'English';

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final user = _supabaseService.getCurrentUser();
    if (user != null) {
      setState(() {
        _userId = user.id;
      });
      final profile = await _supabaseService.getProfile(user.id);
      if (mounted) {
        setState(() {
          _profileData = profile;
          _isLoading = false;
          if (profile != null) {
            _numberOfPlants = profile['number_of_plants'] ?? 3;
            _darkMode = profile['dark_mode'] ?? false;
            _notifications = profile['notifications'] ?? true;
            _language = profile['language'] ?? 'English';

            // Sync global theme notifier on load
            themeModeNotifier.value = _darkMode ? ThemeMode.dark : ThemeMode.light;
          }
        });
      }
    }
  }

  Future<void> _updateNumberOfPlants() async {
    final controller = TextEditingController(text: _numberOfPlants.toString());
    final newCount = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Number of Plants', style: GoogleFonts.manrope(fontWeight: FontWeight.w600)),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Count',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancel', style: GoogleFonts.manrope(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              final count = int.tryParse(controller.text) ?? _numberOfPlants;
              Navigator.of(context).pop(count);
            },
            child: Text('Update', style: GoogleFonts.manrope(color: const Color(0xFF4F635B), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (newCount != null) {
      setState(() {
        _numberOfPlants = newCount;
      });
      await _supabaseService.updateProfile({'number_of_plants': newCount});
    }
  }

  Future<void> _updateLanguage() async {
    final selectedLanguage = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('Select Language', style: GoogleFonts.manrope(fontWeight: FontWeight.w600)),
        children: ['English', 'Spanish', 'French', 'German'].map((lang) {
          return SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(lang),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6.0),
              child: Text(lang, style: GoogleFonts.manrope(fontSize: 15)),
            ),
          );
        }).toList(),
      ),
    );

    if (selectedLanguage != null) {
      setState(() {
        _language = selectedLanguage;
      });
      await _supabaseService.updateProfile({'language': selectedLanguage});
    }
  }

  Future<void> _toggleDarkMode(bool value) async {
    setState(() {
      _darkMode = value;
    });
    // Toggle the app theme dynamically
    themeModeNotifier.value = value ? ThemeMode.dark : ThemeMode.light;
    await _supabaseService.updateProfile({'dark_mode': value});
  }

  Future<void> _toggleNotifications(bool value) async {
    setState(() {
      _notifications = value;
    });
    await _supabaseService.updateProfile({'notifications': value});
  }

  Future<void> _signOut() async {
    await _supabaseService.signOut();
    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF1FCF1),
        body: Center(child: CircularProgressIndicator(color: Color(0xFF4F635B))),
      );
    }

    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color cardColor = isDark ? const Color(0xFF16221A) : Colors.white;
    final Color borderColor = isDark ? const Color(0xFF2A3D31) : const Color(0xFFDAE6DB);
    final Color primaryLabelColor = isDark ? const Color(0xFFB6CBC2) : const Color(0xFF4F635B);
    final Color textMainColor = isDark ? const Color(0xFFE0EAE1) : const Color(0xFF141E17);
    final Color textSecondaryColor = isDark ? const Color(0xFF8B9B90) : const Color(0xFF424845);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F1813) : const Color(0xFFF1FCF1),
      appBar: const CustomAppBar(title: 'Solar Flora'),
      body: AmbientShaderBackground(
        isCharging: false,
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 24),
                      // Profile Card
                      Container(
                        padding: const EdgeInsets.all(16.0),
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: borderColor),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(isDark ? 0.2 : 0.04),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 64,
                              height: 64,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                image: DecorationImage(
                                  image: NetworkImage(
                                    'https://lh3.googleusercontent.com/aida-public/AB6AXuCPRxeU9qQJDxAq8jYyQkgHxIYDgql8TckEoPY5s7ZxXXByuFuUa73GmV-oWebAOIeWQubKQiOdlYLBrInl9JW7EkTB8KZyEjCI9NWrmF_UKrVLJQeJf-NXL4dy1OcQ3XBfq8K7CJeaY5IYEG2HNUBhp00K9Vx9NiHAHE4c5ecEfTU9QPwGnIeKj_cw4-A2B7CU9B3pdUsEWM4zlEHlxYEiwHEvo1ebbGomYKybWJ0Rz0tqfqDIF15n',
                                  ),
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Plant Caretaker',
                                    style: GoogleFonts.manrope(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      color: textMainColor,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'flora.user@gmail.com',
                                    style: GoogleFonts.manrope(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w400,
                                      color: textSecondaryColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // IoT Configuration Section
                      Text(
                        'IOT HARDWARE CONFIGURATION',
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: primaryLabelColor,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(16.0),
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: borderColor),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'User ID for ESP32 Code',
                              style: GoogleFonts.manrope(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: textSecondaryColor,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Expanded(
                                  child: SelectableText(
                                    _userId,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: textMainColor,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: Icon(Icons.copy, size: 18, color: primaryLabelColor),
                                  onPressed: () {
                                    Clipboard.setData(ClipboardData(text: _userId));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('User ID copied to clipboard!', style: GoogleFonts.manrope()),
                                        duration: const Duration(seconds: 2),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Divider(height: 1, color: borderColor),
                            const SizedBox(height: 12),
                            Text(
                              'Device ID',
                              style: GoogleFonts.manrope(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: textSecondaryColor,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'ESP32_SOLAR_001',
                              style: GoogleFonts.manrope(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: textMainColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // System Configuration Section
                      Text(
                        'SYSTEM CONFIGURATION',
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: primaryLabelColor,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: borderColor),
                        ),
                        child: ListTile(
                          onTap: _updateNumberOfPlants,
                          leading: const Icon(Icons.spa, color: Color(0xFF727875)),
                          title: Text(
                            'Number of Plants',
                            style: GoogleFonts.manrope(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: textMainColor,
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '$_numberOfPlants',
                                style: GoogleFonts.manrope(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  color: textSecondaryColor,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.chevron_right, size: 18, color: Color(0xFF727875)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // App Preferences Section
                      Text(
                        'APP PREFERENCES',
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: primaryLabelColor,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: borderColor),
                        ),
                        child: Column(
                          children: [
                            // Dark Mode Toggle
                            ListTile(
                              leading: const Icon(Icons.dark_mode, color: Color(0xFF727875)),
                              title: Text(
                                'Dark Mode',
                                style: GoogleFonts.manrope(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  color: textMainColor,
                                ),
                              ),
                              trailing: Switch(
                                value: _darkMode,
                                onChanged: _toggleDarkMode,
                                activeColor: const Color(0xFF4F635B),
                                activeTrackColor: const Color(0xFFD1E7DD),
                              ),
                            ),
                            Divider(height: 1, color: borderColor),
                            // Notifications Toggle
                            ListTile(
                              leading: const Icon(Icons.notifications, color: Color(0xFF727875)),
                              title: Text(
                                'Notifications',
                                style: GoogleFonts.manrope(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  color: textMainColor,
                                ),
                              ),
                              trailing: Switch(
                                value: _notifications,
                                onChanged: _toggleNotifications,
                                activeColor: const Color(0xFF4F635B),
                                activeTrackColor: const Color(0xFFD1E7DD),
                              ),
                            ),
                            Divider(height: 1, color: borderColor),
                            // Language
                            ListTile(
                              onTap: _updateLanguage,
                              leading: const Icon(Icons.language, color: Color(0xFF727875)),
                              title: Text(
                                'Language',
                                style: GoogleFonts.manrope(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  color: textMainColor,
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _language,
                                    style: GoogleFonts.manrope(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                      color: textSecondaryColor,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(Icons.chevron_right, size: 18, color: Color(0xFF727875)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 36),

                      // Logout button
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: OutlinedButton.icon(
                          onPressed: _signOut,
                          icon: const Icon(Icons.logout, size: 18),
                          label: Text(
                            'Log Out',
                            style: GoogleFonts.manrope(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFBA1A1A),
                            side: const BorderSide(color: Color(0xFFBA1A1A)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
              const CustomNavBar(activeIndex: 2),
            ],
          ),
        ),
      ),
    );
  }
}