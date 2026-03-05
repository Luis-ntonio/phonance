
// settings_tab.dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'account_settings_page.dart';
import 'membership_settings_page.dart';
import 'goals_settings_page.dart';

import 'package:firebase_auth/firebase_auth.dart';


import '../auth/auth_service.dart';
import '../auth/login_page.dart';
import '../main.dart';


class SettingsTab extends StatelessWidget {
  static const String _privacyUrl = String.fromEnvironment(
    'PHONANCE_PRIVACY_URL',
    defaultValue: 'https://phonance-43490.web.app/privacy-policy',
  );

  final ExpensesDb db;
  final VoidCallback onDarkModeToggle;
  final bool isDarkMode;

  const SettingsTab({
    super.key,
    required this.db,
    required this.onDarkModeToggle,
    required this.isDarkMode,
  });

  Future<void> _openPrivacyPolicy(BuildContext context) async {
    final uri = Uri.parse(_privacyUrl);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir la política de privacidad.')),
      );
    }
  }

  Future<void> _deleteAccount(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar cuenta'),
        content: const Text(
          'Esta acción es permanente. Se cerrará la sesión y eliminarás el acceso con esta cuenta.\n\n¿Deseas continuar?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Eliminar')),
        ],
      ),
    );

    if (confirm != true || !context.mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('No hay sesión activa.');
      }

      await db.clearAll();
      await user.delete();
      await FirebaseAuth.instance.signOut();

      if (!context.mounted) return;
      Navigator.of(context).pop();
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => LoginPage(
            db: db,
            onDarkModeToggle: onDarkModeToggle,
            isDarkMode: isDarkMode,
          ),
        ),
        (r) => false,
      );
    } on FirebaseAuthException catch (e) {
      if (!context.mounted) return;
      Navigator.of(context).pop();
      final message = e.code == 'requires-recent-login'
          ? 'Por seguridad, vuelve a iniciar sesión y luego intenta eliminar la cuenta.'
          : (e.message ?? 'No se pudo eliminar la cuenta.');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo eliminar la cuenta: $e')),
      );
    }
  }


  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.person),
            title: const Text('Ajustes de cuenta'),
            subtitle: const Text('Nombre, correo, moneda preferida'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AccountSettingsPage()),
              );
            },
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.workspace_premium),
            title: const Text('Ajustes de membresía'),
            subtitle: const Text('Plan actual, facturación'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MembershipSettingsPage()),
              );
            },
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.flag),
            title: const Text('Configuración de metas'),
            subtitle: const Text('Metas de ahorro y límites de gasto'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const GoalsSettingsPage()),
              );
            },
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Política de privacidad'),
            subtitle: const Text('Ver cómo se usan y protegen tus datos'),
            trailing: const Icon(Icons.open_in_new),
            onTap: () => _openPrivacyPolicy(context),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          color: Theme.of(context).colorScheme.errorContainer,
          child: ListTile(
            leading: Icon(Icons.delete_forever, color: Theme.of(context).colorScheme.onErrorContainer),
            title: Text(
              'Eliminar cuenta',
              style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
            ),
            subtitle: Text(
              'Borra el acceso de esta cuenta en Firebase Auth',
              style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
            ),
            onTap: () => _deleteAccount(context),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          color: Theme.of(context).colorScheme.errorContainer,
          child: ListTile(
            leading: Icon(Icons.logout, color: Theme.of(context).colorScheme.onErrorContainer),
            title: Text('Cerrar sesión', style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer)),

            onTap: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Cerrar sesión'),
                  content: const Text('¿Seguro que deseas cerrar sesión?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
                    FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cerrar sesión')),
                  ],
                ),
              );
              if (ok == true && context.mounted) {

                await FirebaseAuth.instance.signOut();
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(
                    builder: (_) => LoginPage(
                      db: db,
                      onDarkModeToggle: onDarkModeToggle,
                      isDarkMode: isDarkMode,
                    ),
                  ),
                  (r) => false,
                );

              }
            },
          ),
        ),
      ],
    );
  }
}