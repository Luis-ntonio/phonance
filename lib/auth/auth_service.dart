
// auth_service.dart
import 'package:sqflite/sqflite.dart';

import '../main.dart';

class AuthService {
  /// Devuelve true si hay una sesión marcada como logged_in=1.
  static Future<bool> isLoggedIn(ExpensesDb db) async {
    final rows = await db.db.query(
      'session',
      where: 'id = ? AND logged_in = 1',
      whereArgs: [1],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Guarda / reemplaza la sesión (usamos id=1 para tener una sola).
  static Future<void> signIn(ExpensesDb db, {required String email, String? name}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.db.insert(
      'session',
      {
        'id': 1,
        'email': email.trim(),
        'name': (name ?? '').trim(),
        'logged_in': 1,
        'ts': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Borra la sesión actual (o marca logged_in=0).
  static Future<void> signOut(ExpensesDb db) async {
    // Puedes marcar logged_in=0 para auditoría, pero aquí borramos la fila:
    await db.db.delete('session', where: 'id = ?', whereArgs: [1]);
  }

  /// (Opcional) Obtener datos del usuario actual
  static Future<Map<String, dynamic>?> currentUser(ExpensesDb db) async {
    final rows = await db.db.query('session', where: 'id = ?', whereArgs: [1], limit: 1);
    return rows.isNotEmpty ? rows.first : null;
  }
}