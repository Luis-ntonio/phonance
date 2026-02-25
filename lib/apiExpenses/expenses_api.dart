import 'dart:convert';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:flutter/cupertino.dart';
import '../main.dart';

import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';

class ExpensesApi {
  static const String _apiName = 'phonanceApi';
  static const String _path = '/expenses';

  static Future<Map<String, String>> _jwtHeaders() async {
    // Mantengo tu estilo actual (como ProfileApi)
    final session = await Amplify.Auth.fetchAuthSession() as CognitoAuthSession;
    final idToken = session.userPoolTokensResult.value.idToken.raw;

    return {
      // en la mayoría de authorizers sirve con Bearer:
      'Authorization': '$idToken',
      'Content-Type': 'application/json',
    };
  }

  static Future<void> postExpense(Expense e) async {
    final headers = await _jwtHeaders();
    final body = jsonEncode({
      'timestampMs': e.timestampMs,
      'amount': e.amount,
      'currency': e.currency,
      'merchant': e.merchant,
      'category': e.category,
      'rawText': e.rawText,
      'sourcePackage': e.sourcePackage,
      'dedupeKey': e.dedupeKey,
    });

    debugPrint('POST /expenses body: $body');

    final op = Amplify.API.post(
      _path,
      apiName: _apiName,
      body: HttpPayload.string(body, contentType: 'application/json'),
      headers: headers,
    );

    final res = await op.response;
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('POST /expenses failed: ${res.statusCode} ${res.decodeBody()}');
    }
  }

  static Future<void> updateExpenseCategory(String dedupeKey, int timestampMs, String category) async {
    final headers = await _jwtHeaders();
    final body = jsonEncode({
      'dedupeKey': dedupeKey,
      'timestampMs': timestampMs,
      'category': category,
    });

    debugPrint('PATCH /expenses body: $body');

    final op = Amplify.API.patch(
      _path,
      apiName: _apiName,
      body: HttpPayload.string(body, contentType: 'application/json'),
      headers: headers,
    );

    final res = await op.response;
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('PATCH /expenses failed: ${res.statusCode} ${res.decodeBody()}');
    }
  }

  static Future<List<Map<String, dynamic>>> getExpenses({
    required int fromMs,
    int? toMs,
    int limit = 2000,
  }) async {
    final headers = await _jwtHeaders();
    final q = <String, String>{
      'fromMs': fromMs.toString(),
      'limit': limit.toString(),
      if (toMs != null) 'toMs': toMs.toString(),
    };

    final op = Amplify.API.get(
      _path,
      apiName: _apiName,
      headers: headers,
      queryParameters: q,
    );

    final res = await op.response;
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('GET /expenses failed: ${res.statusCode} ${res.decodeBody()}');
    }

    final decoded = jsonDecode(res.decodeBody()) as Map<String, dynamic>;
    final items = (decoded['items'] as List?) ?? const [];
    return items.map((x) => Map<String, dynamic>.from(x as Map)).toList();
  }
}
