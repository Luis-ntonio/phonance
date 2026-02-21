/*
Solo muestra:

“Este mes has gastado”
Totales por moneda
“Tus ahorros son” (RAW por ahora)

No calcula nada → solo UI.
*/


// monthly_summary_card.dart
import 'package:flutter/material.dart';
import '../main.dart';
import '../charts_utils.dart';

class MonthlySummaryCard extends StatelessWidget {
  final Map<String, double> monthSpentByCurrency;
  final String preferredCurrency;
  final double monthlySavingsValue;
  final bool loadingProfile;
  final List<Expense> monthExpenses;

  const MonthlySummaryCard({
    super.key,
    required this.monthSpentByCurrency,
    required this.preferredCurrency,
    required this.monthlySavingsValue,
    required this.loadingProfile,
    required this.monthExpenses
  });

  @override
  Widget build(BuildContext context) {
    final isNegative = monthlySavingsValue < 0;
    final totalsByCurrency = sumByCurrency(monthExpenses);

    return Card(
      color: const Color(0xFFEDEDED),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: DefaultTextStyle(
          style: const TextStyle(color: Colors.black87),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Este mes has gastado:', style: TextStyle(fontSize: 16)),
              const SizedBox(height: 8),
              // Lista de totales por moneda
              ...totalsByCurrency.entries.map((e) => Text(
                '${e.value.toStringAsFixed(2)} ${e.key}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              )),
              const SizedBox(height: 16),
              Text(
                loadingProfile
                    ? 'Tus ahorros son: ...'
                    : 'Tus ahorros son: ${monthlySavingsValue.toStringAsFixed(2)} $preferredCurrency',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: loadingProfile ? null : (isNegative ? Colors.red : Colors.green),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
