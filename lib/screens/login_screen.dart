import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/gocart_logo.dart';
import 'merchant_dashboard_screen.dart';
import 'signup_screen.dart';
import 'user_home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

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
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  // ==========================================================================
  // LOGIN
  // ==========================================================================

  Future<void> login() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      final email = emailController.text.trim();
      final password = passwordController.text;

      final response = await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );

      final user = response.user;

      if (user == null) {
        throw Exception('Login failed.');
      }

      final profile = await Supabase.instance.client
          .from('profiles')
          .select('role')
          .eq('id', user.id)
          .single();

      final role = profile['role'] as String;

      if (!mounted) {
        return;
      }

      if (role == 'merchant') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => const MerchantDashboardScreen(),
          ),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const UserHomeScreen()),
        );
      }
    } on AuthException catch (error) {
      if (mounted) {
        _showMessage(error.message, isError: true);
      }
    } catch (error) {
      if (mounted) {
        _showMessage('Something went wrong: $error', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  // ==========================================================================
  // MESSAGE
  // ==========================================================================

  void _showMessage(String message, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError
            ? Colors.red.shade700
            : const Color(0xFF6F4B9B),
        content: Text(message),
      ),
    );
  }

  // ==========================================================================
  // BUILD
  // ==========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF9FF),
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
                      // ======================================================
                      // TOP NAVIGATION
                      // ======================================================
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const SizedBox(width: 90),

                          if (isWide)
                            Row(
                              children: [
                                Text(
                                  'Don\'t have an account?',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                                TextButton(
                                  onPressed: isLoading
                                      ? null
                                      : () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) =>
                                                  const SignupScreen(),
                                            ),
                                          );
                                        },
                                  child: const Text(
                                    'Create account →',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF6F4B9B),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          else
                            const SizedBox(width: 90),
                        ],
                      ),

                      const SizedBox(height: 12),

                      // ======================================================
                      // BRAND
                      // ======================================================
                      const GoCartLogo(width: 185),

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

                      // ======================================================
                      // LOGIN CARD
                      // ======================================================
                      Container(
                        width: double.infinity,
                        constraints: const BoxConstraints(maxWidth: 470),
                        padding: EdgeInsets.all(isWide ? 30 : 22),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: const Color(0xFFE4D9E9)),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFF6F4B9B,
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

                              // ==================================================
                              // EMAIL
                              // ==================================================
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

                              // ==================================================
                              // PASSWORD
                              // ==================================================
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

                              // ==================================================
                              // LOGIN BUTTON
                              // ==================================================
                              SizedBox(
                                height: 55,
                                child: FilledButton(
                                  onPressed: isLoading ? null : login,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFF6F4B9B),
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

                              const SizedBox(height: 20),

                              // ==================================================
                              // MOBILE SIGNUP
                              // ==================================================
                              if (!isWide)
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      'Don\'t have an account?',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: isLoading
                                          ? null
                                          : () {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (context) =>
                                                      const SignupScreen(),
                                                ),
                                              );
                                            },
                                      child: const Text(
                                        'Create account',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF6F4B9B),
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

                      // ======================================================
                      // BRAND FOOTER
                      // ======================================================
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 34,
                            height: 1,
                            color: const Color(0xFFD8C9E2),
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'SHOP SMART, GOCART',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.7,
                              color: Color(0xFF6F4B9B),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            width: 34,
                            height: 1,
                            color: const Color(0xFFD8C9E2),
                          ),
                        ],
                      ),

                      const SizedBox(height: 8),

                      Text(
                        'GoCart • Mini E-Commerce App',
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

  // ==========================================================================
  // INPUT DECORATION
  // ==========================================================================

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      hintText: hint,

      prefixIcon: Icon(icon, color: const Color(0xFF6F4B9B)),

      suffixIcon: suffix,

      filled: true,

      fillColor: const Color(0xFFFAF7FC),

      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),

      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE4D9E9)),
      ),

      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF6F4B9B), width: 1.5),
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
