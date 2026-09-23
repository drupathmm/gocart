import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/gocart_logo.dart';
import 'login_screen.dart';
import 'merchant_dashboard_screen.dart';
import 'user_home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    // Keep the splash screen visible briefly so the branding
    // does not disappear instantly on fast devices.
    await Future<void>.delayed(const Duration(milliseconds: 1200));

    if (!mounted) {
      return;
    }

    try {
      final supabase = Supabase.instance.client;
      final session = supabase.auth.currentSession;

      // No active session:
      // allow the user to browse the store as a guest.
      if (session == null) {
        _openUserHome();
        return;
      }

      final user = session.user;

      // The session exists, so load the user's profile
      // to determine whether they are a buyer or merchant.
      final profile = await supabase
          .from('profiles')
          .select('role')
          .eq('id', user.id)
          .maybeSingle();

      if (!mounted) {
        return;
      }

      // A valid Auth session without a profile is an
      // incomplete account state. Do not leave the user
      // trapped on a broken authenticated screen.
      if (profile == null) {
        await supabase.auth.signOut();

        if (!mounted) {
          return;
        }

        _openUserHome();
        return;
      }

      final role = profile['role'] as String?;

      if (role == 'merchant') {
        _openMerchantDashboard();
        return;
      }

      if (role == 'user') {
        _openUserHome();
        return;
      }

      // Unknown role: safely sign out rather than trusting
      // an unexpected role value.
      await supabase.auth.signOut();

      if (!mounted) {
        return;
      }

      _openUserHome();
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
        _errorMessage =
            'We could not finish setting up your session. Please try again.';
      });

      debugPrint('Splash initialization error: $error');
    }
  }

  void _openUserHome() {
    if (!mounted) {
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const UserHomeScreen()),
    );
  }

  void _openMerchantDashboard() {
    if (!mounted) {
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const MerchantDashboardScreen()),
    );
  }

  void _openLogin() {
    if (!mounted) {
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
    );
  }

  Future<void> _retry() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    await _initializeApp();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFFCF7FF),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const GoCartLogo(width: 280),

                  const SizedBox(height: 32),

                  if (_errorMessage == null) ...[
                    const SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Color(0xFF6F52A1),
                      ),
                    ),

                    const SizedBox(height: 16),

                    Text(
                      'Getting things ready...',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ] else ...[
                    Icon(
                      Icons.cloud_off_rounded,
                      size: 42,
                      color: Colors.grey.shade600,
                    ),

                    const SizedBox(height: 16),

                    Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.grey.shade700,
                        height: 1.5,
                      ),
                    ),

                    const SizedBox(height: 20),

                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _isLoading ? null : _retry,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF6F52A1),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text('Try Again'),
                      ),
                    ),

                    const SizedBox(height: 10),

                    TextButton(
                      onPressed: _isLoading ? null : _openUserHome,
                      child: const Text('Continue as Guest'),
                    ),

                    const SizedBox(height: 4),

                    TextButton(
                      onPressed: _isLoading ? null : _openLogin,
                      child: const Text('Login'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
