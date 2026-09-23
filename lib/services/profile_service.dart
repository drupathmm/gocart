import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/profile.dart';

class ProfileService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // --------------------------------------------------
  // Current user
  // --------------------------------------------------

  User _requireUser() {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      throw Exception('You must be logged in.');
    }

    return user;
  }

  // --------------------------------------------------
  // Get my profile
  // --------------------------------------------------

  Future<Profile> getMyProfile() async {
    final user = _requireUser();

    final response = await _supabase
        .from('profiles')
        .select('id, name, email, role, created_at')
        .eq('id', user.id)
        .maybeSingle();

    if (response == null) {
      throw Exception('Profile not found.');
    }

    return Profile.fromMap(response);
  }

  // --------------------------------------------------
  // Update my profile
  // --------------------------------------------------

  Future<Profile> updateMyProfile({required String name}) async {
    final user = _requireUser();

    final trimmedName = name.trim();

    if (trimmedName.isEmpty) {
      throw Exception('Name cannot be empty.');
    }

    if (trimmedName.length > 100) {
      throw Exception('Name must be 100 characters or less.');
    }

    final response = await _supabase
        .from('profiles')
        .update({'name': trimmedName})
        .eq('id', user.id)
        .select('id, name, email, role, created_at')
        .maybeSingle();

    if (response == null) {
      throw Exception('Could not update your profile.');
    }

    return Profile.fromMap(response);
  }

  // --------------------------------------------------
  // Sign out
  // --------------------------------------------------

  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }
}
