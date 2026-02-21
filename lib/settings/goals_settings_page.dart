import 'package:flutter/material.dart';
import '../auth/profile_api.dart';

class GoalsSettingsPage extends StatefulWidget {
  const GoalsSettingsPage({super.key});

  @override
  State<GoalsSettingsPage> createState() => _GoalsSettingsPageState();
}

class _GoalsSettingsPageState extends State<GoalsSettingsPage> {
  final _formKey = GlobalKey<FormState>();
  final _api = ProfileApi();

  bool _loading = true;
  bool _saving = false;

  UserProfile? _profile;

  final _savingsCtrl = TextEditingController();
  final _incomeCtrl = TextEditingController();
  final _limitCtrl = TextEditingController();
  String _currency = 'PEN';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _savingsCtrl.dispose();
    _incomeCtrl.dispose();
    _limitCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final p = await ProfileApi.getProfile();
      _profile = p;

      _currency = ((p?.preferredCurrency.isNotEmpty == true) ? p?.preferredCurrency : 'PEN')!;

      _savingsCtrl.text = (p?.savingsGoal ?? 0).toStringAsFixed(0);
      _incomeCtrl.text = (p?.monthlyIncome ?? 0).toStringAsFixed(0);
      _limitCtrl.text = (p?.spendingLimit ?? 0).toStringAsFixed(0);

    } catch (e) {
      // Si tu API devuelve 404, tu ProfileApi probablemente lanza excepción.
      // En ese caso dejamos campos por defecto y se creará al guardar.
      _profile = null;
      _currency = 'PEN';
      _savingsCtrl.text = '';
      _incomeCtrl.text = '';
      _limitCtrl.text = '';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  double _parseNum(String s) {
    final v = double.tryParse(s.trim().replaceAll(',', '.'));
    return v ?? 0;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    try {
      // OJO: email es tu username. No lo inventes si no existe.
      // Si _profile == null, intenta usar datos mínimos.
      final base = _profile ??
          UserProfile(
            email: '', // si tu backend requiere email, ideal: rellenarlo desde Auth.getCurrentUser
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
        preferredCurrency: _currency,
        savingsGoal: _parseNum(_savingsCtrl.text),
        monthlyIncome: _parseNum(_incomeCtrl.text),
        spendingLimit: _parseNum(_limitCtrl.text),
      );

      final saved = await ProfileApi.upsertProfile(updated);
      _profile = saved;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configuración guardada')),
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
        appBar: AppBar(title: const Text('Metas y presupuesto')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Metas y presupuesto'),
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
              DropdownButtonFormField<String>(
                value: _currency,
                items: const [
                  DropdownMenuItem(value: 'PEN', child: Text('PEN')),
                  DropdownMenuItem(value: 'USD', child: Text('USD')),
                ],
                onChanged: _saving ? null : (v) => setState(() => _currency = v ?? 'PEN'),
                decoration: const InputDecoration(
                  labelText: 'Moneda preferida',
                ),
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _savingsCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Meta de ahorro mensual',
                  hintText: 'Ej: 1000',
                ),
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _incomeCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Ganancias mensuales',
                  hintText: 'Ej: 3500',
                ),
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _limitCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Límite de gasto mensual',
                  hintText: 'Ej: 1200',
                ),
              ),
              const SizedBox(height: 20),

              ElevatedButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                    : const Icon(Icons.save),
                label: Text(_saving ? 'Guardando...' : 'Guardar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
