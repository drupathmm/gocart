import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/profile.dart';

class ProfileService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<Profile> getMyProfile() async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      throw Exception('You must be logged in.');
    }

    final response = await _supabase
        .from('profiles')
        .select()
        .eq('id', user.id)
        .single();

    return Profile.fromMap(response);
  }

  Future<Profile> updateMyProfile({required String name}) async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      throw Exception('You must be logged in.');
    }

    final response = await _supabase
        .from('profiles')
        .update({'name': name.trim()})
        .eq('id', user.id)
        .select()
        .single();

    return Profile.fromMap(response);
  }

  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }
}
