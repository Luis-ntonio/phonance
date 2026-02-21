/*
Gráfica histórica de gastos.
Responsabilidades:

Barras por mes
Posible apilado por categorías (después)
Selector de rango (compartido)
*/


// expenses_history_chart.dart
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../main.dart';
import '../charts_utils.dart';
import 'category_palette.dart';

class ExpensesHistoryChart extends StatelessWidget {
  final List<Expense> expenses;
  final int rangeMonths;

  const ExpensesHistoryChart({
    super.key,
    required this.expenses,
    required this.rangeMonths,
  });

  @override
  Widget build(BuildContext context) {
    // Agrupa todos los gastos por mes (yyyy-MM)
    final byMonth = groupByMonth(expenses);

    // Construimos la lista de meses desde el actual hacia atrás
    final now = DateTime.now();
    final months = List.generate(rangeMonths, (i) {
      final d = DateTime(now.year, now.month - i, 1);
      return monthKey(d);
    }).reversed.toList(); // más antiguo primero

    // Determinar categorías presentes (para legend y orden)
    final presentCategories = <String>{};
    for (final m in months) {
      final monthExpenses = byMonth[m] ?? const <Expense>[];
      monthExpenses.forEach((e) {
        presentCategories.add(e.category ?? 'Sin categoría');
      });
    }

    // Orden estable: usa la paleta; agrega categorías no mapeadas al final
    final orderedCategories = [
      ...CategoryPalette.ordered.where((c) => presentCategories.contains(c)),
      ...presentCategories.where((c) => !CategoryPalette.ordered.contains(c)),
    ];

    // Construir grupos de barras apiladas por mes
    final groups = <BarChartGroupData>[];
    double maxY = 0.0;

    for (int i = 0; i < months.length; i++) {
      final k = months[i];
      final monthExpenses = byMonth[k] ?? const <Expense>[];

      // Totales por categoría dentro del mes
      final totalsByCat = <String, double>{};
      for (final e in monthExpenses) {
        final cat = e.category ?? 'Sin categoría';
        final amt = e.amount ?? 0.0;
        totalsByCat[cat] = (totalsByCat[cat] ?? 0.0) + amt;
      }

      // Crear los segmentos apilados (begin..end acumulado)
      final stackItems = <BarChartRodStackItem>[];
      double cursor = 0.0;
      for (final cat in orderedCategories) {
        final v = totalsByCat[cat] ?? 0.0;
        if (v <= 0.0) continue; // no agregues segmentos vacíos
        final begin = cursor;
        final end = cursor + v;
        stackItems.add(
          BarChartRodStackItem(begin, end, CategoryPalette.colorFor(cat)),
        );
        cursor = end;
      }

      maxY = maxY < cursor ? cursor : maxY;

      groups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: cursor, // altura total del mes
              color: Colors.transparent, // el color base no se usa con stack
              width: 20,
              borderRadius: BorderRadius.circular(2),
              rodStackItems: stackItems, // ⬅️ apilado por categoría
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Leyenda de categorías (chips)
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: orderedCategories.map((c) {
            return _LegendChip(label: c, color: CategoryPalette.colorFor(c));
          }).toList(),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 240,
          child: BarChart(
            BarChartData(
              maxY: (maxY == 0.0) ? 10.0 : maxY * 1.2,
              minY: 0,
              gridData: FlGridData(show: true),
              titlesData: FlTitlesData(
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      final idx = value.toInt();
                      if (idx < 0 || idx >= months.length) {
                        return const SizedBox.shrink();
                      }
                      final label = months[idx].split('-'); // yyyy-MM
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          '${label[1]}/${label[0]}',
                          style: const TextStyle(fontSize: 10),
                        ),
                      );
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: true, reservedSize: 40),
                ),
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
              ),
              borderData: FlBorderData(show: false),
              barGroups: groups,
              barTouchData: BarTouchData(
                enabled: true,
                // En 1.1.1 normalmente existe BarTouchTooltipData; si no,
                // podemos dejar el touch enabled y sin tooltips.
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    // Muestra el total del mes y los segmentos apilados

                    final monthKeyStr = months[group.x];        // 'yyyy-MM'
                    final parts = monthKeyStr.split('-');       // [yyyy, MM]
                    final monthLabel = '${parts[1]}/${parts[0]}';

                    // Gastos de ese mes
                    final monthExpenses = byMonth[monthKeyStr] ?? const <Expense>[];

                    // Totales por categoría
                    final totalsByCat = <String, double>{};
                    for (final e in monthExpenses) {
                      final cat = e.category ?? 'Sin categoría';
                      final amt = e.amount ?? 0.0;
                      totalsByCat[cat] = (totalsByCat[cat] ?? 0.0) + amt;
                    }

                    // Construimos el texto: total + desglose ordenado
                    final buf = StringBuffer();
                    buf.writeln('Mes $monthLabel');
                    buf.writeln('Total: ${rod.toY.toStringAsFixed(2)}');

                    for (final cat in orderedCategories) {
                      final v = totalsByCat[cat] ?? 0.0;
                      if (v > 0.0) {
                        buf.writeln('$cat: ${v.toStringAsFixed(2)}');
                      }
                    }

                    return BarTooltipItem(
                      buf.toString(),
                      const TextStyle(color: Colors.white),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LegendChip extends StatelessWidget {
  final String label;
  final Color color;
  const _LegendChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(label),
      backgroundColor: color.withOpacity(0.2),
      avatar: CircleAvatar(backgroundColor: color, radius: 8),
    );
  }
}
