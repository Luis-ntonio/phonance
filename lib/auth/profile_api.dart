import 'dart:convert';
import 'dart:typed_data';

import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:amplify_api/amplify_api.dart';

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
    required this.subscriptionUpdatedAt
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
    'subscriptionUpdatedAt': subscriptionUpdatedAt
  };

  static UserProfile fromJson(Map<String, dynamic> j) => UserProfile(
    name: j['name'] ?? '',
    email: j['email'] ?? '',
    phoneNumber: j['phoneNumber'] ?? '',
    preferredCurrency: j['preferredCurrency'] ?? 'PEN',
    savingsGoal: (j['savingsGoal'] as num?)?.toDouble() ?? 0.0,
    monthlyIncome: (j['monthlyIncome'] as num?)?.toDouble() ?? 0.0,
    spendingLimit: (j['spendingLimit'] as num?)?.toDouble() ?? 0.0,
    isSubscribed: (j['isSubscribed'] == true),
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
      isSubscribed: this.isSubscribed,
      subscriptionUpdatedAt: this.subscriptionUpdatedAt
    );
  }
}



class ProfileApi {
  static const String _apiName = 'phonanceApi';
  static const String _profilePath = '/profile';

  static Future<Map<String, String>> _authHeaders() async {
    final session = await Amplify.Auth.fetchAuthSession();
    final cognito = session as CognitoAuthSession;

    if (!cognito.isSignedIn) {
      throw Exception('No hay sesión iniciada en Cognito.');
    }

    final tokens = cognito.userPoolTokensResult.value;
    final idToken = tokens.idToken.raw;

    return <String, String>{
      'Authorization': 'Bearer $idToken',
      'Content-Type': 'application/json',
    };
  }

  static Future<Map<String, String>> _jwtHeaders() async {
    final session = await Amplify.Auth.fetchAuthSession() as CognitoAuthSession;
    final idToken = session.userPoolTokensResult.value.idToken.raw;

    return {
      // en la mayoría de authorizers sirve con Bearer:
      'Authorization': '$idToken',
      'Content-Type': 'application/json',
    };
  }

  static Future<UserProfile> upsertProfile(UserProfile p) async {
    final headers = await _jwtHeaders();

    final req = Amplify.API.post(
      _profilePath,
      apiName: _apiName,
      headers: headers,
      body: HttpPayload.json(p.toJson()),
    );

    final res = await req.response;
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Error upserting profile: ${res.statusCode} ${res.decodeBody()}');
    }

    final map = jsonDecode(res.decodeBody()) as Map<String, dynamic>;
    return UserProfile.fromJson(map);
  }

  static Future<UserProfile?> getProfile() async {
    final headers = await _jwtHeaders();

    final req = Amplify.API.get(
      _profilePath,
      apiName: _apiName,
      headers: headers,
    );

    final res = await req.response;
    if (res.statusCode == 404) return null;
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Error get profile: ${res.statusCode} ${res.decodeBody()}');
    }

    final data = json.decode(res.decodeBody()) as Map<String, dynamic>;
    return UserProfile.fromJson(data);
  }
}