
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../main.dart';
import './profile_api.dart';

class SignupPage extends StatefulWidget {
  final ExpensesDb db;
  final VoidCallback onDarkModeToggle;
  final bool isDarkMode;

  const SignupPage({
    super.key,
    required this.db,
    required this.onDarkModeToggle,
    required this.isDarkMode,
  });

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  String _currency = 'PEN';
  final _savingsGoalCtrl = TextEditingController();
  final _monthlyIncomeCtrl = TextEditingController();
  final _spendingLimitCtrl = TextEditingController();

  bool _busy = false;
  bool _obscure = true;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _savingsGoalCtrl.dispose();
    _monthlyIncomeCtrl.dispose();
    _spendingLimitCtrl.dispose();
    super.dispose();
  }

  Future<void> _doSignup() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _busy = true);
    try {
      final signupWatch = Stopwatch()..start();
      debugPrint('[SIGNUP] start');
      final email = _emailCtrl.text.trim();
      final password = _passCtrl.text;
      final name = _nameCtrl.text.trim();
      final phoneNumber = _phoneCtrl.text.trim();

      debugPrint('[SIGNUP] creating firebase user');
      final createWatch = Stopwatch()..start();
      final credentials = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      createWatch.stop();

      debugPrint('[SIGNUP] firebase user created uid=${credentials.user?.uid} in ${createWatch.elapsedMilliseconds}ms');
      await credentials.user?.sendEmailVerification();
      debugPrint('[SIGNUP] verification email sent');

      // 2) Construye el perfil
      final profile = UserProfile(
        name: name,
        email: email,
        phoneNumber: phoneNumber,
        preferredCurrency: _currency,
        savingsGoal: double.tryParse(_savingsGoalCtrl.text.trim()) ?? 0,
        monthlyIncome: double.tryParse(_monthlyIncomeCtrl.text.trim()) ?? 0,
        spendingLimit: double.tryParse(_spendingLimitCtrl.text.trim()) ?? 0,
        isSubscribed: false,
        subscriptionUpdatedAt: 0,
        //deberia agregar si ya pago suscripcion
      );

      if (!mounted) return;
      debugPrint('[SIGNUP] signup done at ${signupWatch.elapsedMilliseconds}ms, returning to AuthGate');
      Navigator.of(context).maybePop();

      unawaited(
        (() async {
          final backgroundWatch = Stopwatch()..start();
          try {
            await credentials.user?.updateDisplayName(name);
            debugPrint('[SIGNUP][BG] displayName updated');
          } catch (displayNameError) {
            debugPrint('[SIGNUP][BG] displayName update failed: $displayNameError');
          }

          debugPrint('[SIGNUP][BG] syncing profile to gateway');
          try {
            await ProfileApi.upsertProfile(profile).timeout(const Duration(seconds: 12));
            backgroundWatch.stop();
            debugPrint('[SIGNUP][BG] profile sync ok in ${backgroundWatch.elapsedMilliseconds}ms');
          } catch (profileError) {
            backgroundWatch.stop();
            debugPrint('[SIGNUP][BG] profile sync failed after ${backgroundWatch.elapsedMilliseconds}ms: $profileError');
          }
        })(),
      );
    } on FirebaseAuthException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'No se pudo crear la cuenta.')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currencies = const ['PEN', 'USD', 'EUR'];

    return Scaffold(
      appBar: AppBar(title: const Text('Crear cuenta')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: SingleChildScrollView(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      TextFormField(
                        controller: _nameCtrl,
                        decoration: const InputDecoration(labelText: 'Nombre'),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Ingresa tu nombre' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _phoneCtrl,
                        decoration: const InputDecoration(labelText: 'Telefono'),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Ingresa tu telefono' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _emailCtrl,
                        decoration: const InputDecoration(labelText: 'Correo'),
                        keyboardType: TextInputType.emailAddress,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Ingresa tu correo';
                          if (!v.contains('@')) return 'Correo inválido';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _passCtrl,
                        decoration: InputDecoration(
                          labelText: 'Contraseña',
                          suffixIcon: IconButton(
                            icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                            onPressed: () => setState(() => _obscure = !_obscure),
                          ),
                        ),
                        obscureText: _obscure,
                        validator: (v) => (v == null || v.length < 6) ? 'Mínimo 6 caracteres' : null,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: _currency,
                        decoration: const InputDecoration(labelText: 'Moneda preferida'),
                        items: currencies.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                        onChanged: (v) => setState(() => _currency = v ?? _currency),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _savingsGoalCtrl,
                        decoration: const InputDecoration(labelText: 'Meta de ahorro mensual'),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _monthlyIncomeCtrl,
                        decoration: const InputDecoration(labelText: 'Ganancias mensuales'),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _spendingLimitCtrl,
                        decoration: const InputDecoration(labelText: 'Límite de gasto'),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _busy ? null : _doSignup,
                          child: _busy
                              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Text('Crear cuenta'),
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
