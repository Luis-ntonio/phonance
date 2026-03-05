
// auth_gate.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'login_page.dart';
import 'email_verification_page.dart';
import '../subscription/subscription_gate.dart';
import '../main.dart';


class AuthGate extends StatefulWidget {
  final ExpensesDb db;
  final VoidCallback onDarkModeToggle;
  final bool isDarkMode;

  const AuthGate({
    super.key,
    required this.db,
    required this.onDarkModeToggle,
    required this.isDarkMode,
  });

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.userChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final user = snap.data;
        final signedIn = user != null;
        if (!signedIn) {
          return LoginPage(
            db: widget.db,
            onDarkModeToggle: widget.onDarkModeToggle,
            isDarkMode: widget.isDarkMode,
          );
        }

        if (user!.emailVerified != true) {
          return const EmailVerificationPage();
        }

        return SubscriptionGate(
                db: widget.db,
                onDarkModeToggle: widget.onDarkModeToggle,
                isDarkMode: widget.isDarkMode,
              );
      },
    );
  }
}
