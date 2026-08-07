import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppUser {
  final String id;
  final String? email;
  AppUser({required this.id, this.email});
}

class SupabaseService {
  final supabase.SupabaseClient _supabase = supabase.Supabase.instance.client;

  // Initialize Supabase
  Future<void> initialize() async {
    await supabase.Supabase.initialize(
      url: dotenv.env['SUPABASE_URL'] ?? '',
      anonKey: dotenv.env['SUPABASE_ANON_KEY'] ?? '',
    );
  }

  // Email Sign In (via Firebase Auth)
  Future<AppUser?> signInWithEmail(String email, String password) async {
    try {
      final response = await firebase_auth.FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = response.user;
      if (user != null) {
        return AppUser(id: user.uid, email: user.email);
      }
      return null;
    } catch (e) {
      print('Error signing in: $e');
      rethrow;
    }
  }

  // Email Sign Up (via Firebase Auth)
  Future<AppUser?> signUpWithEmail(String email, String password, String fullName) async {
    try {
      final response = await firebase_auth.FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = response.user;
      
      if (user != null) {
        // Also update the display name in Firebase
        await user.updateDisplayName(fullName);
        
        // IMPORTANT: We must also mirror this user into the Supabase database
        // so that the devices and telemetry tables can link to them!
        try {
          await _supabase.from('profiles').upsert({
            'id': user.uid,
            'email': user.email,
            'full_name': fullName,
          });
        } catch (dbError) {
          print('Warning: Failed to create profile in Supabase: $dbError');
        }

        return AppUser(id: user.uid, email: user.email);
      }
      return null;
    } catch (e) {
      print('Error signing up: $e');
      rethrow;
    }
  }

  // Sign out
  Future<void> signOut() async {
    await firebase_auth.FirebaseAuth.instance.signOut();
  }

  // Get current user (via Firebase)
  AppUser? getCurrentUser() {
    final user = firebase_auth.FirebaseAuth.instance.currentUser;
    if (user != null) {
      return AppUser(id: user.uid, email: user.email);
    }
    return null;
  }

  // Get user profile
  Future<Map<String, dynamic>?> getProfile(String userId) async {
    try {
      var response = await _supabase
          .from('profiles')
          .select()
          .eq('id', userId)
          .maybeSingle();

      if (response == null && userId != 'IIRfy38Wh2RJegWK2x1AOHN0xQt2') {
        response = await _supabase
            .from('profiles')
            .select()
            .eq('id', 'IIRfy38Wh2RJegWK2x1AOHN0xQt2')
            .maybeSingle();
      }

      return response;
    } catch (e) {
      print('Error getting profile: $e');
      return null;
    }
  }

  // Update profile
  Future<void> updateProfile(Map<String, dynamic> updates) async {
    final user = firebase_auth.FirebaseAuth.instance.currentUser;
    final targetId = user?.uid ?? 'IIRfy38Wh2RJegWK2x1AOHN0xQt2';

    // 1. Update the hardcoded ESP32 profile row
    try {
      await _supabase
          .from('profiles')
          .update(updates)
          .eq('id', 'IIRfy38Wh2RJegWK2x1AOHN0xQt2');
    } catch (e) {
      print('Warning: Failed updating ESP32 profile row: $e');
    }

    // 2. Also update the user's specific Firebase profile row if different
    if (user != null && targetId != 'IIRfy38Wh2RJegWK2x1AOHN0xQt2') {
      try {
        await _supabase
            .from('profiles')
            .update(updates)
            .eq('id', targetId);
      } catch (e) {
        print('Warning: Failed updating user profile row: $e');
      }
    }
  }

  // Get user's devices
  Future<List<Map<String, dynamic>>> getDevices() async {
    final user = firebase_auth.FirebaseAuth.instance.currentUser;
    if (user == null) return [];
    try {
      final response = await _supabase
          .from('devices')
          .select()
          .eq('owner_id', user.uid);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error getting devices: $e');
      return [];
    }
  }
  
  // Register a new device
  Future<void> registerDevice(String macAddress) async {
    final user = firebase_auth.FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        await _supabase.from('devices').upsert({
          'id': macAddress,
          'owner_id': user.uid,
          'name': 'New Solak Plant',
          'status': 'online',
        });
      } catch (e) {
        print('Error registering device: $e');
      }
    }
  }

  // Get latest telemetry for a specific user ID
  Future<Map<String, dynamic>?> getLatestTelemetry(String userId) async {
    try {
      // 1. Try querying with the active user ID
      var response = await _supabase
          .from('telemetry')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      // 2. If null, try the default ESP32 user ID
      if (response == null && userId != 'IIRfy38Wh2RJegWK2x1AOHN0xQt2') {
        response = await _supabase
            .from('telemetry')
            .select()
            .eq('user_id', 'IIRfy38Wh2RJegWK2x1AOHN0xQt2')
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();
      }

      // 3. Fallback: get the absolute latest telemetry row regardless of user_id
      if (response == null) {
        response = await _supabase
            .from('telemetry')
            .select()
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();
      }

      return response;
    } catch (e) {
      print('Error getting telemetry: $e');
      return null;
    }
  }

  // Upload avatar to storage
  Future<String?> uploadAvatar(String filePath) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return null;
    
    final fileName = 'avatar_${user.id}.jpg';
    try {
      await _supabase.storage
          .from('avatars')
          .upload(
            fileName,
            File(filePath),
            fileOptions: const supabase.FileOptions(upsert: true),
          );

      final avatarUrl = _supabase.storage.from('avatars').getPublicUrl(fileName);
      return avatarUrl;
    } catch (e) {
      print('Error uploading avatar: $e');
      return null;
    }
  }
}