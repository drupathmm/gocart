import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers/profile_provider.dart';
import 'buyer_profile_screen.dart';
import 'login_screen.dart';
import 'merchant_profile_screen.dart';
import 'user_home_screen.dart';

class ProfileScreen extends ConsumerWidget {
  final VoidCallback? onBuyerBack;

  const ProfileScreen({super.key, this.onBuyerBack});

  void _openHome(BuildContext context) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const UserHomeScreen()),
      (route) => false,
    );
  }

  void _openLogin(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = Supabase.instance.client.auth.currentUser;

    // ------------------------------------------------------------
    // GUEST PROFILE
    // ------------------------------------------------------------
    if (user == null) {
      return _GuestProfileScreen(
        onLogin: () => _openLogin(context),
        onContinueBrowsing: () => _openHome(context),
      );
    }

    // ------------------------------------------------------------
    // LOGGED-IN PROFILE
    // ------------------------------------------------------------
    final profileAsync = ref.watch(profileProvider);

    return profileAsync.when(
      loading: () {
        return const Scaffold(
          backgroundColor: Color(0xFFFFF9FF),
          body: Center(
            child: CircularProgressIndicator(color: Color(0xFF6F4B9B)),
          ),
        );
      },
      error: (error, stackTrace) {
        return Scaffold(
          backgroundColor: const Color(0xFFFFF9FF),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.cloud_off_outlined,
                      size: 48,
                      color: Colors.grey.shade600,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Could not load your profile',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF222222),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Please check your connection and try again.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: () {
                        ref.read(profileProvider.notifier).refreshProfile();
                      },
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Try Again'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF6F4B9B),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      data: (profile) {
        // ----------------------------------------------------------
        // MERCHANT PROFILE
        // ----------------------------------------------------------
        if (profile.isMerchant) {
          return const MerchantProfileScreen();
        }

        // ----------------------------------------------------------
        // BUYER PROFILE
        // ----------------------------------------------------------
        return BuyerProfileScreen(
          onBack:
              onBuyerBack ??
              () {
                Navigator.of(context).maybePop();
              },
        );
      },
    );
  }
}

// ============================================================================
// GUEST PROFILE
// ============================================================================

class _GuestProfileScreen extends StatelessWidget {
  final VoidCallback onLogin;
  final VoidCallback onContinueBrowsing;

  const _GuestProfileScreen({
    required this.onLogin,
    required this.onContinueBrowsing,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF9FF),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // ==========================================================
                  // GUEST ICON
                  // ==========================================================
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0E8F8),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: const Icon(
                      Icons.person_outline_rounded,
                      size: 52,
                      color: Color(0xFF6F4B9B),
                    ),
                  ),

                  const SizedBox(height: 28),

                  // ==========================================================
                  // TITLE
                  // ==========================================================
                  const Text(
                    'Welcome to GoCart',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF222222),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // ==========================================================
                  // DESCRIPTION
                  // ==========================================================
                  Text(
                    'You are currently browsing as a guest. '
                    'Login or create an account to manage your profile, '
                    'orders, cart and shopping activity.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.6,
                      color: Colors.grey.shade600,
                    ),
                  ),

                  const SizedBox(height: 30),

                  // ==========================================================
                  // LOGIN
                  // ==========================================================
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: onLogin,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF6F4B9B),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'Login / Sign Up',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // ==========================================================
                  // CONTINUE BROWSING
                  // ==========================================================
                  TextButton(
                    onPressed: onContinueBrowsing,
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF6F4B9B),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                    child: const Text(
                      'Continue Browsing',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
