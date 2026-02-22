import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import 'first_install_onboarding_screen.dart';
import 'login_screen.dart';

class AppEntryScreen extends StatelessWidget {
  const AppEntryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: DatabaseHelper.instance.hasUsers(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Gagal memuat aplikasi: ${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }

        final hasUsers = snapshot.data ?? false;
        if (!hasUsers) {
          return const FirstInstallOnboardingScreen();
        }

        return const LoginScreen();
      },
    );
  }
}
