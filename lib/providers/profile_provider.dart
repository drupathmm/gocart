import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/profile.dart';
import '../services/profile_service.dart';

// --------------------------------------------------
// Profile service
// --------------------------------------------------

final profileServiceProvider = Provider<ProfileService>((ref) {
  return ProfileService();
});

// --------------------------------------------------
// Current user's profile
// --------------------------------------------------

final profileProvider = AsyncNotifierProvider<ProfileNotifier, Profile>(
  ProfileNotifier.new,
);

class ProfileNotifier extends AsyncNotifier<Profile> {
  @override
  Future<Profile> build() async {
    return ref.read(profileServiceProvider).getMyProfile();
  }

  // --------------------------------------------------
  // Refresh profile
  // --------------------------------------------------

  Future<void> refreshProfile() async {
    state = const AsyncLoading();

    state = await AsyncValue.guard(
      () => ref.read(profileServiceProvider).getMyProfile(),
    );
  }

  // --------------------------------------------------
  // Update profile name
  // --------------------------------------------------

  Future<void> updateName(String name) async {
    final trimmedName = name.trim();

    if (trimmedName.isEmpty) {
      throw Exception('Name cannot be empty.');
    }

    state = await AsyncValue.guard(
      () => ref.read(profileServiceProvider).updateMyProfile(name: trimmedName),
    );
  }

  // --------------------------------------------------
  // Sign out
  // --------------------------------------------------

  Future<void> signOut() async {
    await ref.read(profileServiceProvider).signOut();

    // Clear the provider after logout so an old user's
    // profile is not kept in memory.
    ref.invalidateSelf();
  }
}
