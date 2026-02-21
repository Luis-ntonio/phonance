
import 'package:flutter/material.dart';
import 'package:amplify_flutter/amplify_flutter.dart' hide UserProfile;
import '../main.dart';
import './profile_api.dart';
import 'confirm_sign_up_page.dart';
import '../subscription/subscription_gate.dart';

import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';

Future<void> debugAuthSession() async {
  final session = await Amplify.Auth.fetchAuthSession();
  safePrint('isSignedIn: ${session.isSignedIn}');

  if (session is CognitoAuthSession) {
    safePrint('identityId: ${session.identityIdResult}');
    safePrint('awsCredentials: ${session.credentialsResult}');
    safePrint('userPoolTokens: ${session.userPoolTokensResult}');
  }
}

class SignupPage extends StatefulWidget {
  final ExpensesDb db;
  const SignupPage({super.key, required this.db});

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
      final email = _emailCtrl.text.trim();
      final password = _passCtrl.text;
      final name = _nameCtrl.text.trim();
      final phoneNumber = _phoneCtrl.text.trim();


      final result = await Amplify.Auth.signUp(
        username: email,
        password: password,
        options: SignUpOptions(
          userAttributes: {
            AuthUserAttributeKey.email: email,       // recomendado pasar email explícitamente
            AuthUserAttributeKey.phoneNumber: "+51$phoneNumber", // número de teléfono
            AuthUserAttributeKey.name: name,         // nombre estándar
          },
        ),
      );

      //confirmacion

      switch (result.nextStep.signUpStep) {
        case AuthSignUpStep.confirmSignUp:
        // Abre la pantalla de confirmación
          final confirmed = await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => ConfirmSignUpPage(email: email)),
          );
          if (confirmed != true) {
            // El usuario no confirmó; muestra aviso y corta flujo
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Registro pendiente de confirmación.')),
            );
            return;
          }
          break;
        case AuthSignUpStep.done:
        // Nada extra; el usuario ya está confirmado
          break;
      }

      final signInRes = await Amplify.Auth.signIn(username: email, password: password);
      if (!signInRes.isSignedIn) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cuenta creada. Revisa tu correo para confirmar el registro.')),
        );
        return;
      }

      await debugAuthSession();

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

      // 3) Persistir el perfil en tu API (DynamoDB via Lambda)
      // Si aún no tienes el endpoint, deja este paso para luego.
      await ProfileApi.upsertProfile(profile);

      if (!mounted) return;
      // 4) Navegar a suscripcion

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => SubscriptionGate(db: widget.db)),
      );
    } on AuthException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
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
