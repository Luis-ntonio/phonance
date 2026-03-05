import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class GcpApiClient {
  static const String _baseUrl = String.fromEnvironment(
    'PHONANCE_API_BASE_URL',
    defaultValue: '',
  );
  static const String _fallbackBaseUrl = 'https://phonance-gate-89lez58f.ue.gateway.dev';
  static const Duration _requestTimeout = Duration(seconds: 60);

  static String get _effectiveBaseUrl {
    if (_baseUrl.isNotEmpty) return _baseUrl;
    return _fallbackBaseUrl;
  }

  static Uri buildUri(
    String path, {
    Map<String, String>? queryParameters,
  }) {
    if (_effectiveBaseUrl.isEmpty) {
      throw Exception(
        'PHONANCE_API_BASE_URL no está configurado. Ejecuta con --dart-define=PHONANCE_API_BASE_URL=https://<gateway-host>',
      );
    }

    final base = Uri.parse(_effectiveBaseUrl);
    final normalizedPath = path.startsWith('/') ? path : '/$path';

    return Uri(
      scheme: base.scheme,
      host: base.host,
      port: base.hasPort ? base.port : null,
      path: normalizedPath,
      queryParameters: queryParameters,
    );
  }

  static Future<Map<String, String>> authHeaders() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('No hay sesión de Firebase activa.');
    }

    final token = await user.getIdToken();
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  static Future<Map<String, String>> jsonHeaders() async {
    return {'Content-Type': 'application/json'};
  }

  static Future<http.Response> get(
    String path, {
    Map<String, String>? queryParameters,
    bool auth = true,
  }) async {
    final headers = auth ? await authHeaders() : await jsonHeaders();
    final uri = buildUri(path, queryParameters: queryParameters);
    debugPrint('[GCP][GET] $uri');
    final response = await http.get(
      uri,
      headers: headers,
    ).timeout(_requestTimeout);
    debugPrint('[GCP][GET][${response.statusCode}] ${response.body}');
    return response;
  }

  static Future<http.Response> post(
    String path, {
    Object? body,
    bool auth = true,
  }) async {
    final headers = auth ? await authHeaders() : await jsonHeaders();
    final uri = buildUri(path);
    debugPrint('[GCP][POST] $uri body=${jsonEncode(body)}');
    final response = await http.post(
      uri,
      headers: headers,
      body: body == null ? null : jsonEncode(body),
    ).timeout(_requestTimeout);
    debugPrint('[GCP][POST][${response.statusCode}] ${response.body}');
    return response;
  }

  static Future<http.Response> put(
    String path, {
    Object? body,
    bool auth = true,
  }) async {
    final headers = auth ? await authHeaders() : await jsonHeaders();
    final uri = buildUri(path);
    debugPrint('[GCP][PUT] $uri body=${jsonEncode(body)}');
    final response = await http.put(
      uri,
      headers: headers,
      body: body == null ? null : jsonEncode(body),
    ).timeout(_requestTimeout);
    debugPrint('[GCP][PUT][${response.statusCode}] ${response.body}');
    return response;
  }

  static Future<http.Response> patch(
    String path, {
    Object? body,
    bool auth = true,
  }) async {
    final headers = auth ? await authHeaders() : await jsonHeaders();
    final uri = buildUri(path);
    debugPrint('[GCP][PATCH] $uri body=${jsonEncode(body)}');
    final response = await http.patch(
      uri,
      headers: headers,
      body: body == null ? null : jsonEncode(body),
    ).timeout(_requestTimeout);
    debugPrint('[GCP][PATCH][${response.statusCode}] ${response.body}');
    return response;
  }
}
