import 'dart:convert';

import '../gcp_api_client.dart';

class UserProfile {
  final String name;
  final String email;
  final String preferredCurrency;
  final double savingsGoal;
  final double monthlyIncome;
  final double spendingLimit;
  final String phoneNumber;
  final int subscriptionUpdatedAt;
  final bool isSubscribed;

  UserProfile({
    required this.name,
    required this.email,
    required this.phoneNumber,
    required this.preferredCurrency,
    required this.savingsGoal,
    required this.monthlyIncome,
    required this.spendingLimit,
    required this.isSubscribed,
    required this.subscriptionUpdatedAt,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'email': email,
    'phoneNumber': phoneNumber,
    'preferredCurrency': preferredCurrency,
    'savingsGoal': savingsGoal,
    'monthlyIncome': monthlyIncome,
    'spendingLimit': spendingLimit,
    'isSubscribed': isSubscribed,
    'subscriptionUpdatedAt': subscriptionUpdatedAt,
  };

  static UserProfile fromJson(Map<String, dynamic> j) => UserProfile(
    name: j['name'] ?? '',
    email: j['email'] ?? '',
    phoneNumber: j['phoneNumber'] ?? '',
    preferredCurrency: j['preferredCurrency'] ?? 'PEN',
    savingsGoal: (j['savingsGoal'] as num?)?.toDouble() ?? 0.0,
    monthlyIncome: (j['monthlyIncome'] as num?)?.toDouble() ?? 0.0,
    spendingLimit: (j['spendingLimit'] as num?)?.toDouble() ?? 0.0,
    isSubscribed: j['isSubscribed'] == true,
    subscriptionUpdatedAt: (j['subscriptionUpdatedAt'] as num?)?.toInt() ?? 0,
  );

  UserProfile copyWith({
    String? email,
    String? name,
    String? phoneNumber,
    String? preferredCurrency,
    double? savingsGoal,
    double? monthlyIncome,
    double? spendingLimit,
  }) {
    return UserProfile(
      email: email ?? this.email,
      name: name ?? this.name,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      preferredCurrency: preferredCurrency ?? this.preferredCurrency,
      savingsGoal: savingsGoal ?? this.savingsGoal,
      monthlyIncome: monthlyIncome ?? this.monthlyIncome,
      spendingLimit: spendingLimit ?? this.spendingLimit,
      isSubscribed: isSubscribed,
      subscriptionUpdatedAt: subscriptionUpdatedAt,
    );
  }
}

class ProfileApi {
  static const String _profilePath = '/profile';

  static Future<UserProfile> upsertProfile(UserProfile profile) async {
    final response = await GcpApiClient.post(_profilePath, body: profile.toJson());

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Error upserting profile: ${response.statusCode} ${response.body}');
    }

    final map = jsonDecode(response.body) as Map<String, dynamic>;
    return UserProfile.fromJson(map);
  }

  static Future<UserProfile?> getProfile() async {
    final response = await GcpApiClient.get(_profilePath);

    if (response.statusCode == 404) return null;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Error getting profile: ${response.statusCode} ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return UserProfile.fromJson(data);
  }
}
