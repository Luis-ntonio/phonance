
// login_page.dart
import 'package:flutter/material.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'auth_service.dart';
import '../main.dart';
import 'signup_page.dart';
import '../subscription/subscription_gate.dart';

class LoginPage extends StatefulWidget {
  final ExpensesDb db;
  final VoidCallback onDarkModeToggle;
  final bool isDarkMode;

  const LoginPage({
    super.key,
    required this.db,
    required this.onDarkModeToggle,
    required this.isDarkMode,
  });

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _busy = false;
  bool _obscure = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _doLogin() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final res = await Amplify.Auth.signIn(
        username: _emailCtrl.text.trim(),
        password: _passCtrl.text,
      );


      if (res.isSignedIn && mounted) {
        // Ir a HomePage
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => SubscriptionGate(
              db: widget.db,
              onDarkModeToggle: widget.onDarkModeToggle,
              isDarkMode: widget.isDarkMode,
            ),
          ),
        );
      } else {
        // Si falta confirmación (según políticas del Pool)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Inicio de sesión pendiente de confirmación.')),
        );
      }
    } on AuthException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }

  }

  void _goToSignup() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SignupPage(
          db: widget.db,
          onDarkModeToggle: widget.onDarkModeToggle,
          isDarkMode: widget.isDarkMode,
        ),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Iniciar sesión')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
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
                      validator: (v) => (v == null || v.isEmpty) ? 'Ingresa tu contraseña' : null,
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _busy ? null : _doLogin,
                        child: _busy
                            ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Entrar'),
                      ),
                    ),
                    TextButton(onPressed: _busy ? null : _goToSignup, child: const Text('Crear cuenta')),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

