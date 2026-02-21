
// category_palette.dart
import 'package:flutter/material.dart';

class CategoryPalette {
  static const Map<String, Color> _colors = {
    'comida': Colors.orange,
    'supermercado': Colors.green,
    'transporte': Colors.blue,
    'entretenimiento': Colors.purple,
    'salud': Colors.red,
    'servicios': Colors.teal,
    'otros': Colors.grey,
    'sin categoría': Colors.grey,
  };

  /// Devuelve el color para la categoría; fallback gris.
  static Color colorFor(String category) {
    final key = category.toLowerCase().trim();
    return _colors[key] ?? Colors.grey;
  }

  /// Orden recomendado de categorías para consistencia visual.
  static const List<String> ordered = [
    'Comida',
    'Supermercado',
    'Transporte',
    'Entretenimiento',
    'Salud',
    'Servicios',
    'Otros',
    'Sin categoría',
  ];
}
