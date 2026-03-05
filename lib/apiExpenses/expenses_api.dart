import 'dart:convert';

import 'package:flutter/cupertino.dart';

import '../gcp_api_client.dart';
import '../main.dart';

class ExpensesApi {
  static const String _path = '/expenses';

  static Future<void> postExpense(Expense expense) async {
    final body = {
      'timestampMs': expense.timestampMs,
      'amount': expense.amount,
      'currency': expense.currency,
      'merchant': expense.merchant,
      'category': expense.category,
      'rawText': expense.rawText,
      'sourcePackage': expense.sourcePackage,
      'dedupeKey': expense.dedupeKey,
    };

    debugPrint('POST /expenses body: ${jsonEncode(body)}');

    final response = await GcpApiClient.post(_path, body: body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('POST /expenses failed: ${response.statusCode} ${response.body}');
    }
  }

  static Future<void> updateExpenseCategory(
    String dedupeKey,
    int timestampMs,
    String category,
  ) async {
    final body = {
      'dedupeKey': dedupeKey,
      'timestampMs': timestampMs,
      'category': category,
    };

    debugPrint('PATCH /expenses body: ${jsonEncode(body)}');

    final response = await GcpApiClient.patch(_path, body: body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('PATCH /expenses failed: ${response.statusCode} ${response.body}');
    }
  }

  static Future<List<Map<String, dynamic>>> getExpenses({
    required int fromMs,
    int? toMs,
    int limit = 2000,
  }) async {
    final response = await GcpApiClient.get(
      _path,
      queryParameters: {
        'fromMs': fromMs.toString(),
        'limit': limit.toString(),
        if (toMs != null) 'toMs': toMs.toString(),
      },
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('GET /expenses failed: ${response.statusCode} ${response.body}');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final items = (decoded['items'] as List?) ?? const [];
    return items.map((x) => Map<String, dynamic>.from(x as Map)).toList();
  }
}
