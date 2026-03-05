// subscription_gate.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../main.dart';
import '../auth/profile_api.dart';
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
  static final Map<String, bool> _profileExistsCache = <String, bool>{};
  static final Map<String, bool> _subscribedCache = <String, bool>{};

  bool _loading = true;
  bool _subscribed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkSubscriptionStatus();
  }

  Future<void> _checkSubscriptionStatus({bool force = false}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    if (!force && uid != null && _subscribedCache.containsKey(uid)) {
      if (!mounted) return;
      setState(() {
        _subscribed = _subscribedCache[uid] == true;
        _loading = false;
        _error = null;
      });
      return;
    }

    try {
      bool profileExists;
      if (!force && uid != null && _profileExistsCache.containsKey(uid)) {
        profileExists = _profileExistsCache[uid] == true;
      } else {
        final profile = await ProfileApi.getProfile();
        profileExists = profile != null;
        if (uid != null) {
          _profileExistsCache[uid] = profileExists;
        }
      }

      if (!mounted) return;

      if (!profileExists) {
        if (uid != null) {
          _subscribedCache[uid] = false;
        }
        setState(() {
          _subscribed = false;
          _loading = false;
          _error = null;
        });
        return;
      }

      final status = await SubscriptionApi.refreshStatus();
      if (uid != null) {
        _subscribedCache[uid] = status.isSubscribed;
      }
      if (!mounted) return;
      setState(() {
        _subscribed = status.isSubscribed;
        _loading = false;
      });
    } catch (e) {
      try {
        final cached = await SubscriptionApi.getStatus();
        if (uid != null) {
          _subscribedCache[uid] = cached.isSubscribed;
        }
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
        onSubscribeSuccess: () => _checkSubscriptionStatus(force: true),
      );
    }

    return HomePage(
      db: widget.db,
      onDarkModeToggle: widget.onDarkModeToggle,
      isDarkMode: widget.isDarkMode,
    );
  }
}