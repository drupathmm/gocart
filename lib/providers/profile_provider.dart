import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/profile.dart';
import '../services/profile_service.dart';

final profileServiceProvider = Provider<ProfileService>((ref) {
  return ProfileService();
});

final profileProvider = AsyncNotifierProvider<ProfileNotifier, Profile>(
  ProfileNotifier.new,
);

class ProfileNotifier extends AsyncNotifier<Profile> {
  @override
  Future<Profile> build() async {
    return ref.read(profileServiceProvider).getMyProfile();
  }

  Future<void> refreshProfile() async {
    state = const AsyncLoading();

    state = await AsyncValue.guard(() {
      return ref.read(profileServiceProvider).getMyProfile();
    });
  }

  Future<void> updateName(String name) async {
    state = await AsyncValue.guard(() {
      return ref.read(profileServiceProvider).updateMyProfile(name: name);
    });
  }

  Future<void> signOut() async {
    await ref.read(profileServiceProvider).signOut();
  }
}
