
// auth_gate.dart
import 'package:flutter/material.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'auth_service.dart';
import 'login_page.dart';
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
  late final Future<AuthSession> _authSessionFuture;

  @override
  void initState() {
    super.initState();
    _authSessionFuture = Amplify.Auth.fetchAuthSession();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AuthSession>(
      future: _authSessionFuture,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final signedIn = snap.hasData && (snap.data?.isSignedIn == true);
        return signedIn
            ? SubscriptionGate(
                db: widget.db,
                onDarkModeToggle: widget.onDarkModeToggle,
                isDarkMode: widget.isDarkMode,
              )
            : LoginPage(
                db: widget.db,
                onDarkModeToggle: widget.onDarkModeToggle,
                isDarkMode: widget.isDarkMode,
              );
      },
    );
  }
}
