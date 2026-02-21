/*
Aquí va tu PieChart actual, pero adaptado para:

Filtrar solo gastos del mes actual
Colocarlo a la derecha
*/


// monthly_category_pie.dart
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../main.dart';
import '../charts_utils.dart';
import 'category_palette.dart';

class MonthlyCategoryPie extends StatefulWidget {
  final List<Expense> monthExpenses;
  const MonthlyCategoryPie({super.key, required this.monthExpenses});

  @override
  State<MonthlyCategoryPie> createState() => _MonthlyCategoryPieState();
}

class _MonthlyCategoryPieState extends State<MonthlyCategoryPie> {
  String _selectedCategory = '';
  double _selectedValue = 0.0;

  @override
  Widget build(BuildContext context) {
    final byCat = groupByCategory(widget.monthExpenses);

    final sections = byCat.entries.map((entry) {
      final total = entry.value.fold(0.0, (sum, e) => sum + (e.amount ?? 0.0));
      return PieChartSectionData(
        value: total,
        title: entry.key,
        color: CategoryPalette.colorFor(entry.key),
        // ⬅️ usa paleta compartida
        radius: 52,
        titleStyle: const TextStyle(color: Colors.white, fontSize: 13),
      );
    }).toList();


    return SizedBox(
      height: 220,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Fondo: el PieChart
          PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 40,
              sections: sections,
              pieTouchData: PieTouchData(
                touchCallback: (FlTouchEvent event, PieTouchResponse? response) {
                  setState(() {
                    final noTouch = !event.isInterestedForInteractions ||
                        response == null ||
                        response.touchedSection == null ||
                        response.touchedSection!.touchedSectionIndex == null;

                    if (noTouch) {
                      _selectedCategory = '';
                      _selectedValue = 0.0;
                      return;
                    }

                    final idx = response.touchedSection!.touchedSectionIndex!;
                    final section = sections[idx];
                    _selectedCategory = section.title;
                    _selectedValue = section.value;
                  });
                },
              ),
            ),
          ),

          // Overlay: etiqueta encima del gráfico (no captura toques)
          if (_selectedCategory.isNotEmpty)
            IgnorePointer(
              ignoring: true, // deja pasar los toques al chart
              child: Align(
                alignment: Alignment.topCenter, // o Alignment.center para centrar
                child: Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$_selectedCategory • ${_selectedValue.toStringAsFixed(2)}',
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
