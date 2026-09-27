import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/gocart_logo.dart';
import 'admin_dashboard_screen.dart';
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
  Timer? _splashDelayTimer;
  Completer<void>? _splashDelayCompleter;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  @override
  void dispose() {
    _splashDelayTimer?.cancel();
    final delayCompleter = _splashDelayCompleter;
    if (delayCompleter != null && !delayCompleter.isCompleted) {
      delayCompleter.complete();
    }
    super.dispose();
  }

  Future<void> _initializeApp() async {
    // Keep the splash screen visible briefly for branding.
    final delayCompleter = Completer<void>();
    _splashDelayCompleter = delayCompleter;
    _splashDelayTimer = Timer(
      const Duration(milliseconds: 1200),
      delayCompleter.complete,
    );
    await delayCompleter.future;
    _splashDelayTimer = null;

    if (!mounted) {
      return;
    }

    try {
      final supabase = Supabase.instance.client;

      // Supabase restores the existing session automatically
      // when the application starts again, including browser refresh.
      final session = supabase.auth.currentSession;

      // ------------------------------------------------------------
      // NO SESSION
      // ------------------------------------------------------------
      // User is a guest, so allow normal browsing.
      if (session == null) {
        _openUserHome();
        return;
      }

      final user = session.user;

      // ------------------------------------------------------------
      // LOAD PROFILE / ROLE
      // ------------------------------------------------------------
      final profile = await supabase
          .from('profiles')
          .select('role, merchant_status')
          .eq('id', user.id)
          .maybeSingle();

      if (!mounted) {
        return;
      }

      // ------------------------------------------------------------
      // SESSION EXISTS BUT PROFILE DOES NOT
      // ------------------------------------------------------------
      if (profile == null) {
        await supabase.auth.signOut();

        if (!mounted) {
          return;
        }

        _openUserHome();
        return;
      }

      final role = profile['role'] as String?;
      final merchantStatus =
          profile['merchant_status'] as String? ?? 'approved';

      // ------------------------------------------------------------
      // ADMIN
      // ------------------------------------------------------------
      if (role == 'admin') {
        _openAdminDashboard();
        return;
      }

      // ------------------------------------------------------------
      // MERCHANT
      // ------------------------------------------------------------
      if (role == 'merchant') {
        // A suspended merchant should not enter the dashboard.
        if (merchantStatus == 'suspended') {
          await supabase.auth.signOut();

          if (!mounted) {
            return;
          }

          _showSuspendedMessage();
          return;
        }

        _openMerchantDashboard();
        return;
      }

      // ------------------------------------------------------------
      // NORMAL USER / BUYER
      // ------------------------------------------------------------
      if (role == 'user') {
        _openUserHome();
        return;
      }

      // ------------------------------------------------------------
      // UNKNOWN ROLE
      // ------------------------------------------------------------
      // Only unexpected/invalid roles are signed out.
      // Admin is explicitly handled above.
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

  // ==========================================================================
  // NAVIGATION
  // ==========================================================================

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

  void _openAdminDashboard() {
    if (!mounted) {
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const AdminDashboardScreen()),
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

  // ==========================================================================
  // SUSPENDED MERCHANT
  // ==========================================================================

  void _showSuspendedMessage() {
    if (!mounted) {
      return;
    }

    setState(() {
      _isLoading = false;
      _errorMessage =
          'This merchant account has been suspended by the administrator.';
    });
  }

  // ==========================================================================
  // RETRY
  // ==========================================================================

  Future<void> _retry() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    await _initializeApp();
  }

  // ==========================================================================
  // BUILD
  // ==========================================================================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final logoWidth = (MediaQuery.sizeOf(context).width - 48).clamp(
      180.0,
      280.0,
    );

    return Scaffold(
      backgroundColor: const Color(0xFFFBF6F0),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GoCartLogo(width: logoWidth),

                  const SizedBox(height: 32),

                  if (_errorMessage == null) ...[
                    const SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Color(0xFF541B3D),
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
                          backgroundColor: const Color(0xFF541B3D),
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
