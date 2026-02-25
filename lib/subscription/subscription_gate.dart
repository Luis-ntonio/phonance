// subscription_gate.dart
import 'package:flutter/material.dart';
import '../main.dart';
import 'subscription_api.dart';
import 'subscription_page.dart';

class SubscriptionGate extends StatefulWidget {
  final ExpensesDb db;
  final VoidCallback onDarkModeToggle;
  final bool isDarkMode;

  const SubscriptionGate({
    super.key,
    required this.db,
    required this.onDarkModeToggle,
    required this.isDarkMode,
  });

  @override
  State<SubscriptionGate> createState() => _SubscriptionGateState();
}

class _SubscriptionGateState extends State<SubscriptionGate> {
  bool _loading = true;
  bool _subscribed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkSubscriptionStatus();
  }

  Future<void> _checkSubscriptionStatus() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final status = await SubscriptionApi.refreshStatus();
      if (!mounted) return;
      setState(() {
        _subscribed = status.isSubscribed;
        _loading = false;
      });
    } catch (e) {
      try {
        final cached = await SubscriptionApi.getStatus();
        if (!mounted) return;
        setState(() {
          _subscribed = cached.isSubscribed;
          _loading = false;
          _error = null;
        });
      } catch (inner) {
        if (!mounted) return;
        setState(() {
          _error = inner.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_error ?? 'Erro desconhecido'),
              ElevatedButton(
                  onPressed: _checkSubscriptionStatus,
                  child: const Text('Tentar novamente')
              ),
            ],
          ),
        ),
      );
    }

    if (!_subscribed) {
      return SubscriptionPage(
        onSubscribeSuccess: _checkSubscriptionStatus,
      );
    }

    return HomePage(
      db: widget.db,
      onDarkModeToggle: widget.onDarkModeToggle,
      isDarkMode: widget.isDarkMode,
    );
  }
}