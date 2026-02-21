import 'package:flutter/material.dart';
import '../auth/profile_api.dart';

class AccountSettingsPage extends StatefulWidget {
  const AccountSettingsPage({super.key});

  @override
  State<AccountSettingsPage> createState() => _AccountSettingsPageState();
}

class _AccountSettingsPageState extends State<AccountSettingsPage> {
  final _formKey = GlobalKey<FormState>();
  final _api = ProfileApi();

  bool _loading = true;
  bool _saving = false;
  UserProfile? _profile;

  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final p = await ProfileApi.getProfile();
      _profile = p;
      _nameCtrl.text = p!.name;
      _phoneCtrl.text = p.phoneNumber;
      _emailCtrl.text = p.email;
    } catch (e) {
      _profile = null;
      _nameCtrl.text = '';
      _phoneCtrl.text = '';
      _emailCtrl.text = '';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    try {
      final base = _profile ??
          UserProfile(
            email: _emailCtrl.text.trim(),
            name: '',
            phoneNumber: '',
            preferredCurrency: 'PEN',
            savingsGoal: 0,
            monthlyIncome: 0,
            spendingLimit: 0,
            isSubscribed: false,
            subscriptionUpdatedAt: 0,
          );

      final updated = base.copyWith(
        name: _nameCtrl.text.trim(),
        phoneNumber: _phoneCtrl.text.trim(),
        // email: lo dejamos como está (tu username); cambiarlo bien implica flujo Cognito aparte
      );

      final saved = await ProfileApi.upsertProfile(updated);
      _profile = saved;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cuenta actualizada')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error guardando: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Cuenta')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cuenta'),
        actions: [
          IconButton(
            tooltip: 'Recargar',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _emailCtrl,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'Correo (username)',
                ),
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _nameCtrl,
                readOnly: true,
                decoration: const InputDecoration(labelText: 'Nombre'),
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                readOnly: true,
                decoration: const InputDecoration(labelText: 'Teléfono'),
              )
            ],
          ),
        ),
      ),
    );
  }
}
