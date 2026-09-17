import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/gocart_logo.dart';
import 'login_screen.dart';
import 'merchant_dashboard_screen.dart';
import 'user_home_screen.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController nameController = TextEditingController();

  final TextEditingController emailController = TextEditingController();

  final TextEditingController passwordController = TextEditingController();

  String selectedRole = 'user';

  bool isLoading = false;
  bool isPasswordVisible = false;

  @override
  void dispose() {
    nameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  // ==========================================================================
  // CREATE ACCOUNT
  // ==========================================================================

  Future<void> createAccount() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      final name = nameController.text.trim();
      final email = emailController.text.trim();
      final password = passwordController.text;

      final response = await Supabase.instance.client.auth.signUp(
        email: email,
        password: password,
      );

      final user = response.user;

      if (user == null) {
        throw Exception('Account creation failed.');
      }

      await Supabase.instance.client.from('profiles').insert({
        'id': user.id,
        'name': name,
        'email': email,
        'role': selectedRole,
      });

      if (!mounted) {
        return;
      }

      if (selectedRole == 'merchant') {
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
                vertical: isWide ? 28 : 18,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1050),
                  child: Column(
                    children: [
                      // ======================================================
                      // TOP BAR
                      // ======================================================
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TextButton.icon(
                            onPressed: isLoading
                                ? null
                                : () {
                                    Navigator.pushReplacement(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            const LoginScreen(),
                                      ),
                                    );
                                  },
                            icon: const Icon(
                              Icons.arrow_back_rounded,
                              size: 19,
                            ),
                            label: const Text(
                              'Back',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF5F5365),
                            ),
                          ),

                          if (isWide)
                            Row(
                              children: [
                                Text(
                                  'Already have an account?',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                                TextButton(
                                  onPressed: isLoading
                                      ? null
                                      : () {
                                          Navigator.pushReplacement(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) =>
                                                  const LoginScreen(),
                                            ),
                                          );
                                        },
                                  child: const Text(
                                    'Sign in →',
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

                      const SizedBox(height: 10),

                      // ======================================================
                      // BRAND
                      // ======================================================
                      const GoCartLogo(width: 185),

                      const SizedBox(height: 18),

                      const Text(
                        'Create your account',
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
                        'Join GoCart and start shopping smarter.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                        ),
                      ),

                      const SizedBox(height: 28),

                      // ======================================================
                      // SIGNUP CARD
                      // ======================================================
                      Container(
                        width: double.infinity,
                        constraints: const BoxConstraints(maxWidth: 650),
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
                                'Account details',
                                style: TextStyle(
                                  fontSize: 21,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF21172A),
                                ),
                              ),

                              const SizedBox(height: 5),

                              Text(
                                'Enter your information to create your GoCart account.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade600,
                                ),
                              ),

                              const SizedBox(height: 25),

                              // ==================================================
                              // NAME
                              // ==================================================
                              const _FieldLabel(text: 'Full name'),

                              const SizedBox(height: 8),

                              TextFormField(
                                controller: nameController,
                                textCapitalization: TextCapitalization.words,
                                textInputAction: TextInputAction.next,
                                decoration: _inputDecoration(
                                  hint: 'Enter your name',
                                  icon: Icons.person_outline_rounded,
                                ),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Please enter your name';
                                  }

                                  return null;
                                },
                              ),

                              const SizedBox(height: 19),

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
                                decoration: _inputDecoration(
                                  hint: 'Create a password',
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
                                    return 'Please enter a password';
                                  }

                                  if (value.length < 6) {
                                    return 'Password must be at least 6 characters';
                                  }

                                  return null;
                                },
                              ),

                              const SizedBox(height: 28),

                              // ==================================================
                              // ROLE
                              // ==================================================
                              const Text(
                                'How will you use GoCart?',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF21172A),
                                ),
                              ),

                              const SizedBox(height: 5),

                              Text(
                                'Choose your account type.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade600,
                                ),
                              ),

                              const SizedBox(height: 14),

                              // ==================================================
                              // ROLE OPTIONS
                              // ==================================================
                              if (isWide)
                                Row(
                                  children: [
                                    Expanded(
                                      child: _RoleOption(
                                        title: 'Buyer',
                                        description:
                                            'Browse products and shop from merchants.',
                                        icon: Icons.shopping_cart_outlined,
                                        selected: selectedRole == 'user',
                                        onTap: isLoading
                                            ? null
                                            : () {
                                                setState(() {
                                                  selectedRole = 'user';
                                                });
                                              },
                                      ),
                                    ),

                                    const SizedBox(width: 14),

                                    Expanded(
                                      child: _RoleOption(
                                        title: 'Merchant',
                                        description:
                                            'Add and manage your products and inventory.',
                                        icon: Icons.storefront_outlined,
                                        selected: selectedRole == 'merchant',
                                        onTap: isLoading
                                            ? null
                                            : () {
                                                setState(() {
                                                  selectedRole = 'merchant';
                                                });
                                              },
                                      ),
                                    ),
                                  ],
                                )
                              else
                                Column(
                                  children: [
                                    _RoleOption(
                                      title: 'Buyer',
                                      description:
                                          'Browse products and shop from merchants.',
                                      icon: Icons.shopping_cart_outlined,
                                      selected: selectedRole == 'user',
                                      onTap: isLoading
                                          ? null
                                          : () {
                                              setState(() {
                                                selectedRole = 'user';
                                              });
                                            },
                                    ),

                                    const SizedBox(height: 12),

                                    _RoleOption(
                                      title: 'Merchant',
                                      description:
                                          'Add and manage your products and inventory.',
                                      icon: Icons.storefront_outlined,
                                      selected: selectedRole == 'merchant',
                                      onTap: isLoading
                                          ? null
                                          : () {
                                              setState(() {
                                                selectedRole = 'merchant';
                                              });
                                            },
                                    ),
                                  ],
                                ),

                              const SizedBox(height: 27),

                              // ==================================================
                              // CREATE ACCOUNT
                              // ==================================================
                              SizedBox(
                                height: 55,
                                child: FilledButton(
                                  onPressed: isLoading ? null : createAccount,
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
                                              'Create Account',
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
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 18),

                      // ======================================================
                      // MOBILE LOGIN
                      // ======================================================
                      if (!isWide)
                        Container(
                          width: double.infinity,
                          constraints: const BoxConstraints(maxWidth: 650),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 13,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF4EBFA),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFE4D9E9)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Already have an account?',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                              TextButton(
                                onPressed: isLoading
                                    ? null
                                    : () {
                                        Navigator.pushReplacement(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) =>
                                                const LoginScreen(),
                                          ),
                                        );
                                      },
                                child: const Text(
                                  'Sign in',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF6F4B9B),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                      const SizedBox(height: 25),

                      // ======================================================
                      // FOOTER
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

                      const SizedBox(height: 8),
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

// ============================================================================
// ROLE OPTION
// ============================================================================

class _RoleOption extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  const _RoleOption({
    required this.title,
    required this.description,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(17),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFF1E5FF) : const Color(0xFFFCFAFD),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(
            color: selected ? const Color(0xFF6F4B9B) : const Color(0xFFE4D9E9),
            width: selected ? 1.7 : 1,
          ),
        ),
        child: Row(
          children: [
            // ================================================================
            // ICON
            // ================================================================
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: selected
                    ? const Color(0xFFE5D2FF)
                    : const Color(0xFFF1E8F6),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: const Color(0xFF6F4B9B), size: 23),
            ),

            const SizedBox(width: 13),

            // ================================================================
            // TEXT
            // ================================================================
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF21172A),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.3,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 10),

            // ================================================================
            // RADIO
            // ================================================================
            Container(
              width: 21,
              height: 21,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected
                      ? const Color(0xFF6F4B9B)
                      : Colors.grey.shade400,
                  width: 2,
                ),
              ),
              child: selected
                  ? Center(
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFF6F4B9B),
                        ),
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
