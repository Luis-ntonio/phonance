import 'dart:convert';

import '../gcp_api_client.dart';

class SubscriptionStatus {
  final bool isSubscribed;
  final int? subscriptionUpdatedAt;

  SubscriptionStatus({required this.isSubscribed, this.subscriptionUpdatedAt});

  factory SubscriptionStatus.fromJson(Map<String, dynamic> json) {
    return SubscriptionStatus(
      isSubscribed: json['isSubscribed'] == true,
      subscriptionUpdatedAt: (json['subscriptionUpdatedAt'] as num?)?.toInt(),
    );
  }
}

class SubscriptionApi {
  static const String _path = '/subscription';

  static Future<SubscriptionSummary> getSummary() async {
    final response = await GcpApiClient.get('/subscription/summary');
    final map = jsonDecode(response.body) as Map<String, dynamic>;
    return SubscriptionSummary.fromJson(map);
  }

  static Future<void> cancel() async {
    final response = await GcpApiClient.post('/subscription/cancel', body: {});
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('POST /subscription/cancel failed: ${response.statusCode} ${response.body}');
    }
  }

  static Future<SubscriptionStatus> getStatus() async {
    final response = await GcpApiClient.get(_path);
    final map = jsonDecode(response.body) as Map<String, dynamic>;
    return SubscriptionStatus.fromJson(map);
  }

  static Future<SubscriptionStatus> refreshStatus() async {
    final response = await GcpApiClient.post('/subscription/refresh', body: {});
    final map = jsonDecode(response.body) as Map<String, dynamic>;
    return SubscriptionStatus.fromJson(map);
  }

  static Future<Uri> createCheckoutUrl(String userId) async {
    final response = await GcpApiClient.post(
      '/getMPlink',
      body: {'order_id': userId},
    );

    final map = jsonDecode(response.body) as Map<String, dynamic>;
    final checkoutUrl = (map['checkout_url'] ?? map['init_point']) as String?;

    if (checkoutUrl == null || checkoutUrl.isEmpty) {
      throw Exception('Backend no devolvió checkout_url');
    }

    return Uri.parse(checkoutUrl);
  }
}

class SubscriptionSummary {
  final bool isSubscribed;
  final String mpStatus;
  final String? preapprovalId;
  final num? amount;
  final String? currency;
  final int? frequency;
  final String? frequencyType;
  final String? lastPaymentDate;
  final String? nextChargeDate;

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

  factory SubscriptionSummary.fromJson(Map<String, dynamic> json) {
    final mp = (json['mp'] as Map?)?.cast<String, dynamic>() ?? {};
    final billing = (json['billing'] as Map?)?.cast<String, dynamic>() ?? {};

    return SubscriptionSummary(
      isSubscribed: json['isSubscribed'] == true,
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
