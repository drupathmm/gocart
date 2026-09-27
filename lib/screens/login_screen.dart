import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/gocart_logo.dart';
import 'admin_dashboard_screen.dart';
import 'merchant_dashboard_screen.dart';
import 'signup_screen.dart';
import 'user_home_screen.dart';

class LoginScreen extends StatefulWidget {
  final bool switchAccount;
  final String? initialMessage;

  const LoginScreen({
    super.key,
    this.switchAccount = false,
    this.initialMessage,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  bool isLoading = false;
  bool isPasswordVisible = false;

  @override
  void initState() {
    super.initState();
    final message = widget.initialMessage;
    if (message != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showMessage(message, isError: false);
        }
      });
    }
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  // ============================================================
  // LOGIN
  // ============================================================

  Future<void> login() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      final supabase = Supabase.instance.client;

      final email = emailController.text.trim();
      final password = passwordController.text;

      // ----------------------------------------------------------
      // Account switching
      // ----------------------------------------------------------

      if (widget.switchAccount && supabase.auth.currentSession != null) {
        await supabase.auth.signOut();
      }

      // ----------------------------------------------------------
      // Supabase authentication
      // ----------------------------------------------------------

      final response = await supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      final user = response.user;

      if (user == null) {
        throw Exception('Login failed. Please try again.');
      }

      // ----------------------------------------------------------
      // Load role and merchant status
      // ----------------------------------------------------------

      var profile = await supabase
          .from('profiles')
          .select('role, merchant_status')
          .eq('id', user.id)
          .maybeSingle();

      if (profile == null) {
        // Email confirmation can leave a valid Auth account without a usable
        // session during signup. Complete its profile on the first confirmed
        // login, using only the two roles offered by the signup flow.
        final metadata = user.userMetadata ?? const <String, dynamic>{};
        final name = (metadata['name'] as String? ?? '').trim();
        final requestedRole = metadata['role'] as String?;

        if (name.isEmpty ||
            (requestedRole != 'user' && requestedRole != 'merchant')) {
          await supabase.auth.signOut();
          throw Exception(
            'Your account profile could not be created. Please contact support.',
          );
        }

        profile = await supabase
            .from('profiles')
            .insert({
              'id': user.id,
              'name': name,
              'email': user.email ?? '',
              'role': requestedRole,
            })
            .select('role, merchant_status')
            .single();
      }

      final role = profile['role'] as String?;
      final merchantStatus = profile['merchant_status'] as String?;

      // ----------------------------------------------------------
      // Validate role
      //
      // Admin is intentionally NOT shown anywhere in signup.
      // It is only assigned directly in the database.
      // ----------------------------------------------------------

      if (role != 'merchant' && role != 'user' && role != 'admin') {
        await supabase.auth.signOut();

        throw Exception(
          'Your account has an invalid role. '
          'Please contact support.',
        );
      }

      // ----------------------------------------------------------
      // Suspended merchant protection
      // ----------------------------------------------------------

      if (role == 'merchant' && merchantStatus == 'suspended') {
        await supabase.auth.signOut();

        throw Exception(
          'Your merchant account has been suspended. '
          'Please contact support.',
        );
      }

      if (!mounted) {
        return;
      }

      // ----------------------------------------------------------
      // ADMIN
      // ----------------------------------------------------------

      if (role == 'admin') {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const AdminDashboardScreen()),
          (route) => false,
        );

        return;
      }

      // ----------------------------------------------------------
      // MERCHANT
      // ----------------------------------------------------------

      if (role == 'merchant') {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (context) => const MerchantDashboardScreen(),
          ),
          (route) => false,
        );

        return;
      }

      // ----------------------------------------------------------
      // BUYER
      // ----------------------------------------------------------

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const UserHomeScreen()),
        (route) => false,
      );
    } on AuthException catch (error) {
      if (mounted) {
        _showMessage(_friendlyAuthError(error), isError: true);
      }
    } catch (error) {
      if (mounted) {
        final message = error.toString().replaceFirst('Exception: ', '').trim();

        _showMessage(
          message.isEmpty ? 'Something went wrong. Please try again.' : message,
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  // ============================================================
  // AUTH ERROR MESSAGE
  // ============================================================

  String _friendlyAuthError(AuthException error) {
    final message = error.message.toLowerCase();

    if (message.contains('invalid login credentials')) {
      return 'Incorrect email or password.';
    }

    if (message.contains('email not confirmed')) {
      return 'Please verify your email before signing in.';
    }

    if (message.contains('too many requests')) {
      return 'Too many login attempts. Please wait a moment and try again.';
    }

    if (message.contains('network')) {
      return 'Network error. Please check your internet connection.';
    }

    return error.message;
  }

  // ============================================================
  // MESSAGE
  // ============================================================

  void _showMessage(String message, {required bool isError}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: isError
              ? Colors.red.shade700
              : const Color(0xFF541B3D),
          content: Text(message),
        ),
      );
  }

  // ============================================================
  // SIGN UP
  // ============================================================

  void _openSignup() {
    if (isLoading) {
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SignupScreen()),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFBF6F0),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 800;

            return SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: isWide ? 40 : 20,
                vertical: isWide ? 34 : 22,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1050),
                  child: Column(
                    children: [
                      const SizedBox(height: 12),

                      const GoCartLogo(width: 155),

                      const SizedBox(height: 18),

                      const Text(
                        'Welcome back',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.7,
                          color: Color(0xFF21172A),
                        ),
                      ),

                      const SizedBox(height: 7),

                      Text(
                        'Sign in to continue shopping smarter.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                        ),
                      ),

                      const SizedBox(height: 30),

                      Container(
                        width: double.infinity,
                        constraints: const BoxConstraints(maxWidth: 470),
                        padding: EdgeInsets.all(isWide ? 30 : 22),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: const Color(0xFFEADDD5)),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFF541B3D,
                              ).withValues(alpha: 0.09),
                              blurRadius: 30,
                              offset: const Offset(0, 12),
                            ),
                          ],
                        ),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                'Sign in',
                                style: TextStyle(
                                  fontSize: 21,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF21172A),
                                ),
                              ),

                              const SizedBox(height: 5),

                              Text(
                                'Enter your account details below.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade600,
                                ),
                              ),

                              const SizedBox(height: 25),

                              const _FieldLabel(text: 'Email address'),

                              const SizedBox(height: 8),

                              TextFormField(
                                controller: emailController,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                autocorrect: false,
                                decoration: _inputDecoration(
                                  hint: 'Enter your email',
                                  icon: Icons.email_outlined,
                                ),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Please enter your email';
                                  }

                                  if (!value.contains('@')) {
                                    return 'Please enter a valid email';
                                  }

                                  return null;
                                },
                              ),

                              const SizedBox(height: 19),

                              const _FieldLabel(text: 'Password'),

                              const SizedBox(height: 8),

                              TextFormField(
                                controller: passwordController,
                                obscureText: !isPasswordVisible,
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted: (_) {
                                  if (!isLoading) {
                                    login();
                                  }
                                },
                                decoration: _inputDecoration(
                                  hint: 'Enter your password',
                                  icon: Icons.lock_outline_rounded,
                                  suffix: IconButton(
                                    tooltip: isPasswordVisible
                                        ? 'Hide password'
                                        : 'Show password',
                                    onPressed: () {
                                      setState(() {
                                        isPasswordVisible = !isPasswordVisible;
                                      });
                                    },
                                    icon: Icon(
                                      isPasswordVisible
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Please enter your password';
                                  }

                                  if (value.length < 6) {
                                    return 'Password must be at least 6 characters';
                                  }

                                  return null;
                                },
                              ),

                              const SizedBox(height: 27),

                              SizedBox(
                                height: 55,
                                child: FilledButton(
                                  onPressed: isLoading ? null : login,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFF541B3D),
                                    foregroundColor: Colors.white,
                                    disabledBackgroundColor: const Color(
                                      0xFFD9D0DF,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    elevation: 0,
                                  ),
                                  child: isLoading
                                      ? const SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.5,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              'Sign in',
                                              style: TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            SizedBox(width: 8),
                                            Icon(
                                              Icons.arrow_forward_rounded,
                                              size: 20,
                                            ),
                                          ],
                                        ),
                                ),
                              ),

                              const SizedBox(height: 16),

                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Flexible(
                                    child: Text(
                                      'Don\'t have an account?',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: isLoading ? null : _openSignup,
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 8,
                                      ),
                                      minimumSize: Size.zero,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    child: const Text(
                                      'Create account →',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF541B3D),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 25),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 34,
                            height: 1,
                            color: const Color(0xFFE7B98A),
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'SHOP SMART, GOCART',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.7,
                              color: Color(0xFF541B3D),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            width: 34,
                            height: 1,
                            color: const Color(0xFFE7B98A),
                          ),
                        ],
                      ),

                      const SizedBox(height: 8),

                      Text(
                        'GoCart • DMM-dev • 2026  All rights reserved.',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ============================================================
  // INPUT DECORATION
  // ============================================================

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, color: const Color(0xFF541B3D)),
      suffixIcon: suffix,
      filled: true,
      fillColor: const Color(0xFFFCF8F3),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFEADDD5)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF541B3D), width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE57373)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE53935), width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }
}

// ============================================================================
// FIELD LABEL
// ============================================================================

class _FieldLabel extends StatelessWidget {
  final String text;

  const _FieldLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: Color(0xFF3B3042),
      ),
    );
  }
}
