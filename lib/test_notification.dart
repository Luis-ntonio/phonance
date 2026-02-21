import 'dart:math';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class TestNotifications {
  static final FlutterLocalNotificationsPlugin _plugin =
  FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'test_wallet_channel',
    'Test Wallet Notifications',
    description: 'Channel for simulated Wallet-like purchase notifications',
    importance: Importance.high,
  );

  static Future<void> init() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');

    const initSettings = InitializationSettings(android: androidInit);

    await _plugin.initialize(initSettings);

    // Crear channel (Android 8+)
    final android = _plugin
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      await android.createNotificationChannel(_channel);
    }
  }

  /// Genera una notificación “tipo Wallet”:
  /// title: COMERCIO
  /// body:  PEN280.20 with Visa ••8487
  static Future<void> showWalletLikeNotification({
    String? merchant,
    String currency = 'PEN',
    double? amount,
    String cardSuffix = '8487',
  }) async {
    final rnd = Random();

    final m = merchant ??
        [
          'OXXO ALIAGA',
          'EDO SUSHI BAR',
          'TOTTUS',
          'PLAZA VEA',
          'INKAFARMA',
          'STARBUCKS',
        ][rnd.nextInt(6)];

    final a = amount ?? (rnd.nextInt(30000) / 100.0); // 0.00 a 300.00
    final body = '$currency${a.toStringAsFixed(2)} with Visa ••$cardSuffix';

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channel.id,
        _channel.name,
        channelDescription: _channel.description,
        importance: Importance.high,
        priority: Priority.high,
      ),
    );

    // id aleatorio para que no “actualice” la anterior
    await _plugin.show(rnd.nextInt(1 << 30), m, body, details);
  }
}
