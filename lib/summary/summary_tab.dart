/*
Expected Display for this view
┌────────────────────────┐
│ Resumen mensual        │  ← card izquierda
│ PieChart mensual       │  ← derecha
├────────────────────────┤
│ Selector rango meses   │
│ Histórico ahorros      │
├────────────────────────┤
│ Selector rango meses   │
│ Histórico gastos       │
└────────────────────────┘

*/


// summary_tab.dart
import 'package:flutter/material.dart';
import '../main.dart';
import '../charts_utils.dart';
import 'monthly_summary_card.dart';
import 'monthly_category_pie.dart';
import 'savings_history_chart.dart';
import 'expenses_history_chart.dart';
import '../auth/profile_api.dart';

class SummaryTab extends StatefulWidget {
  final List<Expense> expenses;
  const SummaryTab({super.key, required this.expenses});

  @override
  State<SummaryTab> createState() => _SummaryTabState();
}

class _SummaryTabState extends State<SummaryTab> {
  // Rangos de meses (históricos)
  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  int _savingsRangeMonths = 6;  // por defecto 6 meses
  int _expensesRangeMonths = 6; // por defecto 6 meses

  UserProfile? _profile;
  bool _loadingProfile = true;

  String get _preferredCurrency => (_profile?.preferredCurrency.trim().isNotEmpty ?? false)
      ? _profile!.preferredCurrency.trim()
      : 'PEN';

  double get _monthlyIncome => _profile?.monthlyIncome ?? 0.0;

  Future<void> _loadProfile() async {
    try {
      final p = await ProfileApi.getProfile();
      if (!mounted) return;
      setState(() {
        _profile = p;
        _loadingProfile = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingProfile = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentMonthExpenses = filterCurrentMonth(widget.expenses);
    final monthExpenses = filterCurrentMonth(widget.expenses);
    final monthSpentByCurrency = sumByCurrency(monthExpenses);

    // Solo calculamos ahorro en la moneda preferida
    final spentPreferred = sumTotalInCurrency(monthExpenses, _preferredCurrency);
    final monthlySavingsValue = _monthlyIncome - spentPreferred;



    // Layout principal scrollable
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Fila superior: Card izquierda + Pie derecha
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Izquierda: resumen del mes actual
              Expanded(
                flex: 1,
                child: MonthlySummaryCard(
                  monthExpenses: currentMonthExpenses,
                  monthSpentByCurrency: monthSpentByCurrency,
                  preferredCurrency: _preferredCurrency,
                  monthlySavingsValue: monthlySavingsValue,
                  loadingProfile: _loadingProfile,
                ),
              ),
              const SizedBox(width: 12),
              // Derecha: pie chart del mes actual
              Expanded(
                flex: 1,
                child: MonthlyCategoryPie(
                  monthExpenses: currentMonthExpenses,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Sección: Histórico de ahorros
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Histórico de ahorros',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              DropdownButton<int>(
                value: _savingsRangeMonths,
                items: const [
                  DropdownMenuItem(value: 3, child: Text('Últimos 3 meses')),
                  DropdownMenuItem(value: 6, child: Text('Últimos 6 meses')),
                  DropdownMenuItem(value: 12, child: Text('Últimos 12 meses')),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _savingsRangeMonths = v);
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          SavingsHistoryChart(
            expenses: widget.expenses,
            rangeMonths: _savingsRangeMonths,
            preferredCurrency: _preferredCurrency,
            monthlyIncome: _monthlyIncome,
          ),



          const SizedBox(height: 16),

          // Sección: Histórico de gastos
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Histórico de gastos',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              DropdownButton<int>(
                value: _expensesRangeMonths,
                items: const [
                  DropdownMenuItem(value: 3, child: Text('Últimos 3 meses')),
                  DropdownMenuItem(value: 6, child: Text('Últimos 6 meses')),
                  DropdownMenuItem(value: 12, child: Text('Últimos 12 meses')),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _expensesRangeMonths = v);
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          ExpensesHistoryChart(
            expenses: widget.expenses,
            rangeMonths: _expensesRangeMonths,
          ),
        ],
      ),
    );
  }
}
