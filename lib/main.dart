import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'pages/settings_page.dart';
import 'pages/status_page.dart';
import 'pages/energy_page.dart';
import 'pages/login_page.dart';

import 'package:google_fonts/google_fonts.dart';

// Global notifier for dynamic theme switching (Dark Mode vs Light Mode)
final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier(ThemeMode.light);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase using native config files (google-services.json / GoogleService-Info.plist)
  await Firebase.initializeApp();

  // Load the environment variables file
  await dotenv.load(fileName: ".env");

  // Initialize Supabase with values loaded from environment
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL'] ?? '',
    anonKey: dotenv.env['SUPABASE_ANON_KEY'] ?? '',
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, currentThemeMode, child) {
        return MaterialApp(
          title: 'Solak',
          debugShowCheckedModeBanner: false,
          themeMode: currentThemeMode,
          theme: ThemeData(
            brightness: Brightness.light,
            primaryColor: const Color(0xFF4F635B),
            scaffoldBackgroundColor: const Color(0xFFF1FCF1),
            textTheme: GoogleFonts.manropeTextTheme(
              ThemeData.light().textTheme,
            ).apply(
              bodyColor: const Color(0xFF141E17),
              displayColor: const Color(0xFF141E17),
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.transparent,
              elevation: 0,
              foregroundColor: Color(0xFF4F635B),
            ),
            dividerColor: const Color(0xFFDAE6DB).withOpacity(0.5),
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            primaryColor: const Color(0xFFB6CBC2),
            scaffoldBackgroundColor: const Color(0xFF0F1813),
            textTheme: GoogleFonts.manropeTextTheme(
              ThemeData.dark().textTheme,
            ).apply(
              bodyColor: const Color(0xFFE0EAE1),
              displayColor: const Color(0xFFE0EAE1),
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.transparent,
              elevation: 0,
              foregroundColor: Color(0xFFB6CBC2),
            ),
            dividerColor: const Color(0xFF2A3D31),
          ),
          home: const AuthGate(),
          routes: {
            '/status': (context) => const StatusPage(),
            '/energy': (context) => const EnergyPage(),
            '/settings': (context) => const SettingsPage(),
            '/login': (context) => const LoginPage(),
          },
        );
      },
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<fb_auth.User?>(
      stream: fb_auth.FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(Color(0xFF4F635B)),
              ),
            ),
          );
        }
        if (snapshot.hasData) {
          return const StatusPage();
        }
        return const LoginPage();
      },
    );
  }
}