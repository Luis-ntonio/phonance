import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
  FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    const AndroidInitializationSettings androidSettings =
    AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initSettings =
    InitializationSettings(android: androidSettings);

    await _notificationsPlugin.initialize(initSettings);
  }

  Future<void> showPersistentNotification({
    required String title,
    required String body,
    int id = 9991,
  }) async {
    const AndroidNotificationDetails androidDetails =
    AndroidNotificationDetails(
      'budget_alerts',
      'Alertas de presupuesto',
      channelDescription: 'Notificaciones cuando se excede el límite de gasto',
      importance: Importance.high,
      priority: Priority.high,
      ongoing: true,
      autoCancel: false,
      onlyAlertOnce: true,
    );

    await _notificationsPlugin.show(
      id,
      title,
      body,
      const NotificationDetails(android: androidDetails),
    );
  }

  Future<void> cancelPersistentNotification({int id = 9991}) async {
    await _notificationsPlugin.cancel(id);
  }
}
