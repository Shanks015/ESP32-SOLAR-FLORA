import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import 'package:firebase_auth/firebase_auth.dart' as firebase;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppUser {
  final String id;
  final String? email;
  AppUser({required this.id, this.email});
}

class SupabaseService {
  final supabase.SupabaseClient _supabase = supabase.Supabase.instance.client;
  final firebase.FirebaseAuth _firebaseAuth = firebase.FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  // Initialize Supabase (initialized in main.dart)
  Future<void> initialize() async {
    await supabase.Supabase.initialize(
      url: dotenv.env['SUPABASE_URL'] ?? '',
      anonKey: dotenv.env['SUPABASE_ANON_KEY'] ?? '',
    );
  }

  // Google Sign In (via Firebase)
  Future<AppUser?> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null;

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final firebase.AuthCredential credential = firebase.GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final firebase.UserCredential userCredential = await _firebaseAuth.signInWithCredential(credential);
      final firebase.User? user = userCredential.user;

      if (user != null) {
        // Automatically sync or create profile in Supabase
        await createUserProfileIfNotExist(user.uid, user.email, user.displayName);
        return AppUser(id: user.uid, email: user.email);
      }
      return null;
    } catch (e) {
      print('Error signing in with Google: $e');
      return null;
    }
  }

  // Email Sign In (via Firebase)
  Future<AppUser?> signInWithEmail(String email, String password) async {
    final firebase.UserCredential credential = await _firebaseAuth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    final user = credential.user;
    if (user != null) {
      await createUserProfileIfNotExist(user.uid, user.email, null);
      return AppUser(id: user.uid, email: user.email);
    }
    return null;
  }

  // Email Sign Up (via Firebase)
  Future<AppUser?> signUpWithEmail(String email, String password) async {
    final firebase.UserCredential credential = await _firebaseAuth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    final user = credential.user;
    if (user != null) {
      await createUserProfileIfNotExist(user.uid, user.email, null);
      return AppUser(id: user.uid, email: user.email);
    }
    return null;
  }

  // Sign out
  Future<void> signOut() async {
    await _firebaseAuth.signOut();
    await _googleSignIn.signOut();
  }

  // Get current user
  AppUser? getCurrentUser() {
    final user = _firebaseAuth.currentUser;
    if (user != null) {
      return AppUser(id: user.uid, email: user.email);
    }
    return null;
  }

  // Automatically provision user profile row in Supabase if it doesn't exist
  Future<void> createUserProfileIfNotExist(String uid, String? email, String? fullName) async {
    try {
      final profile = await getProfile(uid);
      if (profile == null) {
        await _supabase.from('profiles').insert({
          'id': uid,
          'email': email,
          'full_name': fullName ?? email?.split('@').first ?? 'Plant Caretaker',
          'number_of_plants': 3,
          'dark_mode': false,
          'notifications': true,
          'language': 'English',
          'motor_active': false,
          'daily_watering_enabled': false,
          'daily_watering_time': '08:00:00',
          'watering_duration': 15,
          'sleep_interval': 600,
        });
        print('Created new profile for user: $uid');
      }
    } catch (e) {
      print('Error creating profile: $e');
    }
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
    final userId = getCurrentUser()?.id;
    if (userId == null) throw Exception('No authenticated user');

    final fileName = 'avatar_$userId.jpg';
    try {
      await _supabase.storage
          .from('avatars')
          .upload(
            fileName,
            File(filePath),
            fileOptions: const supabase.FileOptions(upsert: true),
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