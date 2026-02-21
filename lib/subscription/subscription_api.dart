// subscription_api.dart
import 'dart:convert';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';

class SubscriptionStatus {
  final bool isSubscribed;
  final int? subscriptionUpdatedAt;

  SubscriptionStatus({required this.isSubscribed, this.subscriptionUpdatedAt});

  factory SubscriptionStatus.fromJson(Map<String, dynamic> j) {
    return SubscriptionStatus(
      isSubscribed: (j['isSubscribed'] == true),
      subscriptionUpdatedAt: (j['subscriptionUpdatedAt'] as num?)?.toInt(),
    );
  }
}

class SubscriptionApi {
  static const String _apiName = 'phonanceApi';
  static const String _path = '/subscription';

  static Future<Map<String, String>> _jwtHeaders() async {
    final session = await Amplify.Auth.fetchAuthSession() as CognitoAuthSession;
    final idToken = session.userPoolTokensResult.value.idToken.raw;

    return {
      // en la mayoría de authorizers sirve con Bearer:
      'Authorization': '$idToken',
      'Content-Type': 'application/json',
    };
  }

  static Future<SubscriptionSummary> getSummary() async {
    final headers = await _jwtHeaders();
    final op = Amplify.API.get(
      '/subscription/summary',
      apiName: _apiName,
      headers: headers,
    );
    final res = await op.response;
    final map = json.decode(res.decodeBody()) as Map<String, dynamic>;
    return SubscriptionSummary.fromJson(map);
  }

  static Future<void> cancel() async {
    final headers = await _jwtHeaders();
    final op = Amplify.API.post(
      '/subscription/cancel',
      apiName: _apiName,
      headers: headers,
      body: HttpPayload.json({}),
    );
    await op.response; // si no lanza, ok
  }

  static Future<SubscriptionStatus> getStatus() async {
      final headers = await _jwtHeaders();

      final operation = Amplify.API.get(_path, apiName: _apiName, headers: headers);
      //logging


      final response = await operation.response;

      // decodeBody é o padrão para Amplify v2
      final map = json.decode(response.decodeBody()) as Map<String, dynamic>;
      return SubscriptionStatus.fromJson(map);

  }

  static Future<SubscriptionStatus> refreshStatus() async {
    final headers = await _jwtHeaders();

    final op = Amplify.API.post(
      '/subscription/refresh',
      apiName: _apiName,
      headers: headers,
      body: HttpPayload.json({}),
    );

    final res = await op.response;
    final map = json.decode(res.decodeBody()) as Map<String, dynamic>;
    return SubscriptionStatus.fromJson(map);
  }

  static Future<Uri> createCheckoutUrl(userId) async {
    final headers = await _jwtHeaders();

    final operation = Amplify.API.post(
      '/getMPlink',
      apiName: _apiName,
      headers: headers,
      body: HttpPayload.json({
        // opcional: puedes enviar un planKey/planId si tienes más de un plan
        'order_id': userId,
      }),
    );

    final response = await operation.response;
    final map = json.decode(response.decodeBody()) as Map<String, dynamic>;

    final checkoutUrl = (map['checkout_url'] ?? map['init_point']) as String?;
    if (checkoutUrl == null || checkoutUrl.isEmpty) {
      throw Exception('Backend no devolvió checkout_url');
    }

    return Uri.parse(checkoutUrl);
  }

// Nota: setSubscribed será chamado pelo seu Webhook no backend AWS
// quando o Mercado Pago confirmar o pagamento.
}


class SubscriptionSummary {
  final bool isSubscribed;
  final String mpStatus;
  final String? preapprovalId;
  final num? amount;
  final String? currency;
  final int? frequency;
  final String? frequencyType;
  final String? lastPaymentDate; // ISO
  final String? nextChargeDate;  // ISO

  SubscriptionSummary({
    required this.isSubscribed,
    required this.mpStatus,
    this.preapprovalId,
    this.amount,
    this.currency,
    this.frequency,
    this.frequencyType,
    this.lastPaymentDate,
    this.nextChargeDate,
  });

  factory SubscriptionSummary.fromJson(Map<String, dynamic> j) {
    final mp = (j['mp'] as Map?)?.cast<String, dynamic>() ?? {};
    final billing = (j['billing'] as Map?)?.cast<String, dynamic>() ?? {};
    return SubscriptionSummary(
      isSubscribed: j['isSubscribed'] == true,
      mpStatus: (mp['status'] ?? 'unknown').toString(),
      preapprovalId: mp['preapprovalId']?.toString(),
      amount: mp['amount'],
      currency: mp['currency']?.toString(),
      frequency: (mp['frequency'] is num) ? (mp['frequency'] as num).toInt() : null,
      frequencyType: mp['frequencyType']?.toString(),
      lastPaymentDate: billing['lastPaymentDate']?.toString(),
      nextChargeDate: billing['nextChargeDate']?.toString(),
    );
  }
}

