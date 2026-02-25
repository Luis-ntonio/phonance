/*
Gráfica histórica de ahorros.
Responsabilidades:

Recibe:

gastos por mes
ahorros por mes (RAW)

Colores:

Verde si ahorro ≥ gasto
Rojo si gasto > ahorro


Tiene selector de rango de meses
*/


// savings_history_chart.dart
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../main.dart';
import '../charts_utils.dart';

class SavingsHistoryChart extends StatelessWidget {
  final List<Expense> expenses;
  final int rangeMonths;
  final String preferredCurrency;
  final double monthlyIncome;

  const SavingsHistoryChart({
    super.key,
    required this.expenses,
    required this.rangeMonths,
    required this.preferredCurrency,
    required this.monthlyIncome,
  });

  @override
  Widget build(BuildContext context) {
    final byMonth = groupByMonth(expenses);

    // Construimos la lista de meses desde el actual hacia atrás
    final now = DateTime.now();
    final months = List.generate(rangeMonths, (i) {
      final d = DateTime(now.year, now.month - i, 1);
      return monthKey(d);
    }).reversed.toList(); // más antiguo primero

    // Para cada mes, calculamos gasto total y “ahorro raw”
    final groups = <BarChartGroupData>[];
    final savingsByMonth = <String, double>{};
    double minY = 0;
    double maxY = 0.0;


    for (final m in months) {
      final monthExpenses = byMonth[m] ?? const <Expense>[];
      final spent = sumTotalInCurrency(monthExpenses, preferredCurrency); //mejorar el sumTotalInCurrency
      final savings = monthlyIncome - spent;

      savingsByMonth[m] = savings;
      if (savings < minY) minY = savings;
      if (savings > maxY) maxY = savings;
    }
    final pad = ((maxY - minY).abs() * 0.15);
    final chartMinY = (minY - pad).floorToDouble();
    final chartMaxY = (maxY + pad).ceilToDouble();

    for (int i = 0; i < months.length; i++) {

      final savings = savingsByMonth[months[i]] ?? 0.0;
      final color = savings < 0 ? Colors.red : Colors.green;

      // Una barra por mes con el valor del “ahorro”
      groups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: savings,
              width: 18,
              color: color,
              borderRadius: BorderRadius.circular(6),
            ),
          ],
        )
      );
    }

    return SizedBox(
      height: 220,
      child: BarChart(
        BarChartData(
          minY: chartMinY,
          maxY: chartMaxY,
          gridData: FlGridData(
            show: true,
            horizontalInterval: null,
            drawHorizontalLine: false,
            drawVerticalLine: false,
          ),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= months.length) return const SizedBox.shrink();

                  final key = months[i];
                  final savings = savingsByMonth[key] ?? 0.0;

                  final labelColor = savings < 0 ? Colors.red : Colors.green;

                  return SideTitleWidget(
                    meta: meta,
                    child: Text(
                      key,
                      style: TextStyle(
                        fontSize: 11,
                        color: labelColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(showTitles: true, reservedSize: 40),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          barGroups: groups,
        ),
      ),
    );
  }
}
