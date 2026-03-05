import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class EmailVerificationPage extends StatefulWidget {
  const EmailVerificationPage({super.key});

  @override
  State<EmailVerificationPage> createState() => _EmailVerificationPageState();
}

class _EmailVerificationPageState extends State<EmailVerificationPage> {
  bool _busy = false;

  Future<void> _resendEmail() async {
    setState(() => _busy = true);
    try {
      await FirebaseAuth.instance.currentUser?.sendEmailVerification();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Correo de verificación reenviado.')),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'No se pudo reenviar el correo.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _iAlreadyVerified() async {
    setState(() => _busy = true);
    try {
      await FirebaseAuth.instance.currentUser?.reload();
      if (!mounted) return;

      final refreshed = FirebaseAuth.instance.currentUser;
      if (refreshed?.emailVerified == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Correo verificado correctamente.')),
        );
        setState(() {});
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aún no se detecta verificación. Revisa tu bandeja y vuelve a intentar.')),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'No se pudo actualizar el estado de verificación.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Verifica tu correo')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Te enviamos un correo de verificación a:'),
                    const SizedBox(height: 8),
                    Text(email, style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 16),
                    const Text('Abre el enlace del correo y luego presiona "Ya verifiqué".'),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _busy ? null : _iAlreadyVerified,
                        child: _busy
                            ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Ya verifiqué'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: _busy ? null : _resendEmail,
                        child: const Text('Reenviar correo'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: _busy ? null : _signOut,
                        child: const Text('Usar otra cuenta'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
