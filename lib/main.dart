import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/splash_screen.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://jqulrjrpzdozhlxeuefy.supabase.co',
    publishableKey: 'sb_publishable_MDfR5Mz2uj7z2xznsVrvWA_qrEtUx6F',
  );

  runApp(const ProviderScope(child: GoCartApp()));
}

class GoCartApp extends StatelessWidget {
  const GoCartApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GoCart',
      debugShowCheckedModeBanner: false,
      theme: GoCartTheme.light,
      home: const SplashScreen(),
    );
  }
}
