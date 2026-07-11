import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class SupabaseService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  // Initialize Supabase (retained for reference, but initialized in main.dart)
  Future<void> initialize() async {
    await Supabase.initialize(
      url: dotenv.env['SUPABASE_URL'] ?? '',
      anonKey: dotenv.env['SUPABASE_ANON_KEY'] ?? '',
    );
  }

  // Google Sign In
  Future<User?> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      final GoogleSignInAuthentication googleAuth = await googleUser!.authentication;

      final AuthResponse res = await _supabase.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: googleAuth.idToken!,
        accessToken: googleAuth.accessToken,
      );

      return res.user;
    } catch (e) {
      print('Error signing in with Google: $e');
      return null;
    }
  }

  // Email Sign In (Real API call)
  Future<User?> signInWithEmail(String email, String password) async {
    final AuthResponse response = await _supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );
    return response.user;
  }

  // Email Sign Up (Real API call)
  Future<User?> signUpWithEmail(String email, String password) async {
    final AuthResponse response = await _supabase.auth.signUp(
      email: email,
      password: password,
    );
    return response.user;
  }

  // Sign out
  Future<void> signOut() async {
    await _supabase.auth.signOut();
    await _googleSignIn.signOut();
  }

  // Get current user
  User? getCurrentUser() {
    return _supabase.auth.currentUser;
  }

  // Get user profile (Real Database query)
  Future<Map<String, dynamic>?> getProfile(String userId) async {
    try {
      final response = await _supabase
          .from('profiles')
          .select()
          .eq('id', userId)
          .single();

      return response;
    } catch (e) {
      print('Error getting profile: $e');
      return null;
    }
  }

  // Update profile (Real Database query)
  Future<void> updateProfile(Map<String, dynamic> updates) async {
    final userId = getCurrentUser()?.id;
    if (userId == null) throw Exception('No authenticated user');

    await _supabase
        .from('profiles')
        .update(updates)
        .eq('id', userId);
  }

  // Insert telemetry (for ESP32 to call)
  Future<void> insertTelemetry(Map<String, dynamic> telemetryData) async {
    await _supabase.from('telemetry').insert(telemetryData);
  }

  // Get latest telemetry for current user
  Future<Map<String, dynamic>?> getTelemetry() async {
    final userId = getCurrentUser()?.id;
    if (userId == null) throw Exception('No authenticated user');

    return getLatestTelemetry(userId);
  }

  // Get latest telemetry for a specific user ID (Real Database query)
  Future<Map<String, dynamic>?> getLatestTelemetry(String userId) async {
    try {
      final response = await _supabase
          .from('telemetry')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(1)
          .single();

      return response;
    } catch (e) {
      print('Error getting telemetry: $e');
      return null;
    }
  }

  // Upload avatar to storage
  Future<String?> uploadAvatar(String filePath) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('No authenticated user');

    final fileName = 'avatar_$userId.jpg'; // or use actual file extension
    try {
      await _supabase.storage
          .from('avatars')
          .upload(
            fileName,
            File(filePath),
            fileOptions: const FileOptions(upsert: true),
          );

      // Get public URL
      final avatarUrl = _supabase.storage.from('avatars').getPublicUrl(fileName);
      return avatarUrl;
    } catch (e) {
      print('Error uploading avatar: $e');
      return null;
    }
  }
}