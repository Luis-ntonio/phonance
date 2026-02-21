
// charts_utils.dart
import 'package:intl/intl.dart';
import 'main.dart'; // para acceder al modelo Expense

/// Devuelve la clave de mes en formato 'yyyy-MM'
String monthKey(DateTime dt) => DateFormat('yyyy-MM').format(dt);

/// Filtra expenses que pertenecen al mes actual del dispositivo
List<Expense> filterCurrentMonth(List<Expense> all) {
  final now = DateTime.now();
  final keyNow = monthKey(now);
  return all.where((e) => monthKey(
      DateTime.fromMillisecondsSinceEpoch(e.timestampMs)
  ) == keyNow).toList();
}

/// Agrupa por mes (clave 'yyyy-MM')
Map<String, List<Expense>> groupByMonth(List<Expense> all) {
  final map = <String, List<Expense>>{};
  for (final e in all) {
    final k = monthKey(DateTime.fromMillisecondsSinceEpoch(e.timestampMs));
    (map[k] ??= []).add(e);
  }
  return map;
}

/// Suma por moneda (para el mes actual)
Map<String, double> sumByCurrency(List<Expense> monthExpenses) {
  final totals = <String, double>{};
  for (final e in monthExpenses) {
    if (e.amount == null) continue;
    final c = (e.currency ?? '').isEmpty ? 'N/A' : e.currency!;
    totals[c] = (totals[c] ?? 0.0) + e.amount!;
  }
  return totals;
}

/// Agrupa por categoría dentro de una lista
Map<String, List<Expense>> groupByCategory(List<Expense> expenses) {
  final map = <String, List<Expense>>{};
  for (final e in expenses) {
    final cat = e.category ?? 'Sin categoría';
    (map[cat] ??= []).add(e);
  }
  return map;
}

/// Suma total (independiente de moneda) de una lista
double sumTotal(List<Expense> expenses) {
  double s = 0.0;
  for (final e in expenses) {
    if (e.amount != null) s += e.amount!;
  }
  return s;
}

double sumTotalInCurrency(List<Expense> expenses, String currency) {
  double s = 0.0;
  for (final e in expenses) {
    if (e.amount == null) continue;

    // Si viene sin moneda, asumimos que es la moneda preferida
    final c = (e.currency == null || e.currency!.isEmpty) ? currency : e.currency!;
    if (c == currency) s += e.amount!;
  }
  return s;
}
