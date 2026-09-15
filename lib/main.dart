import 'package:flutter/material.dart';
import 'screens/splash_screen.dart';

void main() {
  runApp(const GoCartApp());
}

class GoCartApp extends StatelessWidget {
  const GoCartApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GoCart',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const SplashScreen(),
    );
  }
}
