import 'package:flutter/material.dart';

import 'login_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const CircleAvatar(radius: 50, child: Icon(Icons.person, size: 55)),

          const SizedBox(height: 20),

          const Center(
            child: Text(
              'GoCart User',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
          ),

          const SizedBox(height: 8),

          const Center(child: Text('user@example.com')),

          const SizedBox(height: 32),

          const ListTile(
            leading: Icon(Icons.person_outline),
            title: Text('Personal Information'),
            trailing: Icon(Icons.chevron_right),
          ),

          const ListTile(
            leading: Icon(Icons.email_outlined),
            title: Text('Email'),
            trailing: Icon(Icons.chevron_right),
          ),

          const ListTile(
            leading: Icon(Icons.settings_outlined),
            title: Text('Settings'),
            trailing: Icon(Icons.chevron_right),
          ),

          const SizedBox(height: 20),

          SizedBox(
            height: 50,
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                  (route) => false,
                );
              },
              icon: const Icon(Icons.logout),
              label: const Text('Logout'),
            ),
          ),
        ],
      ),
    );
  }
}
