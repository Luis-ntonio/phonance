import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/gmail/v1.dart' as gmail;
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GmailService {
  static final GmailService _instance = GmailService._internal();
  
  factory GmailService() {
    return _instance;
  }
  
  GmailService._internal();
  
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      'email',
      'https://www.googleapis.com/auth/gmail.readonly',
    ],
  );
  
  GoogleSignInAccount? _currentUser;
  
  bool get isSignedIn => _currentUser != null;
  
  /// Intenta restaurar la sesión guardada previamente
  Future<void> initializeFromStorage() async {
    try {
      // Verificar si el usuario ya está silenciosamente signed in
      final account = await _googleSignIn.signInSilently(reAuthenticate: false);
      if (account != null) {
        _currentUser = account;
        debugPrint('✅ Gmail session restored from storage');
      } else {
        debugPrint('No Gmail session found in storage');
        _currentUser = null;
      }
    } catch (e) {
      debugPrint('Could not restore Gmail session: $e');
      _currentUser = null;
    }
  }
  
  Future<void> signIn() async {
    try {
      // Cerrar sesión primero para forzar una nueva autenticación con todos los scopes
      await _googleSignIn.signOut();
      
      // Ahora hacer signIn
      var account = await _googleSignIn.signIn();
      
      if (account != null) {
        _currentUser = account;
        
        // Verificar que tenemos los permisos necesarios
        final auth = await account.authentication;
        if (auth.accessToken == null) {
          throw Exception('Failed to get access token');
        }
        
        debugPrint('Successfully signed in to Gmail');
      } else {
        throw Exception('Sign in was cancelled');
      }
    } catch (e) {
      debugPrint('Error signing in to Google: $e');
      _currentUser = null;
      rethrow;
    }
  }
  
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    _currentUser = null;
  }
  
  /// Obtiene correos desde una fecha específica (en milisegundos)
  Future<List<EmailMessage>> getEmailsSince(int sinceTimestampMs) async {
    if (_currentUser == null) {
      throw Exception('User not signed in to Google');
    }
    
    try {
      final auth = await _currentUser!.authentication;
      final headers = {
        'Authorization': 'Bearer ${auth.accessToken}',
        'Content-Type': 'application/json',
      };
      
      // Query para buscar correos desde una fecha
      // Buscamos emails de BCP, YAPE, PLIN (basándose en el asunto o remitente)
      final sinceDateTime = DateTime.fromMillisecondsSinceEpoch(sinceTimestampMs);
      final query = 'from:(notificaciones@notificacionesbcp.com.pe OR notificaciones@yape.pe OR plin) after:${sinceDateTime.year}-${sinceDateTime.month.toString().padLeft(2, '0')}-${sinceDateTime.day.toString().padLeft(2, '0')}';
      
      final messagesResponse = await http.get(
        Uri.https('www.googleapis.com', '/gmail/v1/users/me/messages', {
          'q': query,
          'maxResults': '100',
        }),
        headers: headers,
      );
      
      if (messagesResponse.statusCode != 200) {
        throw Exception('Failed to fetch Gmail messages: ${messagesResponse.statusCode}');
      }
      
      final messagesJson = jsonDecode(messagesResponse.body) as Map<String, dynamic>;
      final messageIds = (messagesJson['messages'] as List<dynamic>?)
          ?.map((m) => (m as Map<String, dynamic>)['id'] as String)
          .toList() ?? [];
      
      if (messageIds.isEmpty) {
        return [];
      }
      
      // Obtener detalles de cada email
      final emails = <EmailMessage>[];
      for (final messageId in messageIds) {
        final detailResponse = await http.get(
          Uri.https('www.googleapis.com', '/gmail/v1/users/me/messages/$messageId', {
            'format': 'full',
          }),
          headers: headers,
        );
        
        if (detailResponse.statusCode == 200) {
          final emailJson = jsonDecode(detailResponse.body) as Map<String, dynamic>;
          final payload = emailJson['payload'] as Map<String, dynamic>?;
          
          if (payload != null) {
            final email = _parseEmailFromPayload(payload, emailJson);
            if (email != null) {
              emails.add(email);
            }
          }
        }
      }
      
      return emails;
    } catch (e) {
      debugPrint('Error fetching Gmail messages: $e');
      rethrow;
    }
  }
  
  EmailMessage? _parseEmailFromPayload(
    Map<String, dynamic> payload,
    Map<String, dynamic> emailJson,
  ) {
    try {
      final headers = payload['headers'] as List<dynamic>? ?? [];
      final parts = payload['parts'] as List<dynamic>? ?? [];
      
      String? subject;
      String? from;
      
      for (final header in headers) {
        if (header is Map<String, dynamic>) {
          final name = header['name'] as String?;
          final value = header['value'] as String?;
          
          if (name == 'Subject') subject = value;
          if (name == 'From') from = value;
        }
      }
      
      // Extraer el cuerpo del email
      String? body;
      if (parts.isNotEmpty) {
        for (final part in parts) {
          if (part is Map<String, dynamic>) {
            final mimeType = part['mimeType'] as String?;
            final data = part['body']?['data'] as String?;
            
            if (mimeType == 'text/plain' || mimeType == 'text/html') {
              if (data != null) {
                try {
                  body = utf8.decode(base64Url.decode(data.replaceAll('-', '+').replaceAll('_', '/')));
                  break;
                } catch (e) {
                  debugPrint('Error decoding email body: $e');
                }
              }
            }
          }
        }
      } else {
        final bodyData = payload['body']?['data'] as String?;
        if (bodyData != null) {
          try {
            body = utf8.decode(base64Url.decode(bodyData.replaceAll('-', '+').replaceAll('_', '/')));
          } catch (e) {
            debugPrint('Error decoding email body: $e');
          }
        }
      }
      
      final internalDate = int.tryParse(emailJson['internalDate'] as String? ?? '0') ?? 0;
      
      if (subject == null || body == null) {
        return null;
      }
      
      return EmailMessage(
        id: emailJson['id'] as String,
        subject: subject,
        from: from ?? 'Unknown',
        body: body,
        timestampMs: internalDate,
      );
    } catch (e) {
      debugPrint('Error parsing email: $e');
      return null;
    }
  }
}

class EmailMessage {
  final String id;
  final String subject;
  final String from;
  final String body;
  final int timestampMs;
  
  EmailMessage({
    required this.id,
    required this.subject,
    required this.from,
    required this.body,
    required this.timestampMs,
  });
  
  /// Combina subject + body en un formato similar a las notificaciones
  String get combinedText {
    return '$subject\n$body';
  }
  
  /// Verifica si este email es una transacción válida (BCP, YAPE, PLIN, BBVA, etc)
  bool isValidTransaction() {
    final combined = combinedText.toLowerCase();
    
    // Palabras clave de acción de pago
    const actionKeywords = [
      'pagaste', 'pago', 'compra', 'purchase', 'spent', 'transacción',
      'se realizó', 'se ha realizado', 'aprobada', 'approved',
      'consumo', 'cargo', 'débito', 'yapeo', 'transferencia', 'visa',
      'operación realizada', 'has realizado',
    ];
    
    // Palabras clave de moneda/monto
    const moneyKeywords = [
      's/', 'pen', 'usd', r'$', 'soles', 'dólares',
    ];
    
    // Bancos y billeteras digitales
    const bankKeywords = [
      'bcp', 'bbva', 'yape notificaciones', 'plin',
      'interbank', 'scotiabank', 'hsbc', 'wallet', 'google pay',
    ];
    
    // Debe tener al menos una palabra de banco Y una palabra de acción Y una de dinero
    final hasBank = bankKeywords.any((k) => combined.contains(k));
    final hasAction = actionKeywords.any((k) => combined.contains(k));
    final hasMoney = moneyKeywords.any((k) => combined.contains(k));
    
    return hasBank && hasAction && hasMoney;
  }
}
