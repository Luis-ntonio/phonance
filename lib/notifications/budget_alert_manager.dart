import 'package:flutter/cupertino.dart';

import '../notifications/notification_service.dart';
// import '../models/expense.dart'; utilizar cuando se termine de refactorizar el codigo
// import '../utils/currency_utils.dart'; // utilizar cuando se termine de refactorizar el codigo

import '../main.dart';

class BudgetAlertManager {
  static final BudgetAlertManager _instance = BudgetAlertManager._internal();
  factory BudgetAlertManager() => _instance;
  BudgetAlertManager._internal();

  double _spendingLimit = 0;
  String _currency = 'PEN';
  bool _alertShown = false;

  void setUserSettings({required double spendingLimit, required String currency}) {
    _spendingLimit = spendingLimit;
    _currency = currency;
  }

  Future<void> evaluateAndNotify(List<Expense> expenses, double monthlyIncome) async {
    debugPrint('evaluando gastos: ${expenses}');
    final double totalSpent = expenses.fold(0, (sum, e) => sum + (e.amount ?? 0.0));
    final double limit = _spendingLimit;

    if (limit > 0 && totalSpent > limit) {
      if (!_alertShown) {
        await NotificationService().showPersistentNotification(
          title: 'Límite de gasto excedido',
          body:
          'Has gastado ${totalSpent.toStringAsFixed(2)} $_currency (límite: ${limit.toStringAsFixed(2)} $_currency)',
        );
        _alertShown = true;
      }
    } else if (_alertShown && totalSpent <= limit) {
      await NotificationService().cancelPersistentNotification();
      _alertShown = false;
    }
  }
}
