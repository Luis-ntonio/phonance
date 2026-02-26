
// settings_tab.dart
import 'package:flutter/material.dart';
import 'account_settings_page.dart';
import 'membership_settings_page.dart';
import 'goals_settings_page.dart';

import 'package:amplify_flutter/amplify_flutter.dart';


import '../auth/auth_service.dart';
import '../auth/login_page.dart';
import '../main.dart';


class SettingsTab extends StatelessWidget {
  final ExpensesDb db;
  final VoidCallback onDarkModeToggle;
  final bool isDarkMode;

  const SettingsTab({
    super.key,
    required this.db,
    required this.onDarkModeToggle,
    required this.isDarkMode,
  });


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
        const SizedBox(height: 12),
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

                await Amplify.Auth.signOut();
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