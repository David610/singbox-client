// Reconstructed (see docs/FORK_ARCHITECTURE_AUDIT.md, docs/ARCHITECTURE.md).
library;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class LocalNotifications {
  LocalNotifications._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) {
      return;
    }
    _initialized = true;
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    try {
      await _plugin.initialize(settings: settings);
    } catch (_) {}
  }

  static Future<void> notifiy(
    int id,
    String channelId,
    String title,
    String content,
    String payload,
    void Function()? onTap,
  ) async {
    if (!_initialized) {
      return;
    }
    try {
      await _plugin.show(
        id: id,
        title: title,
        body: content,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(channelId, channelId),
          iOS: const DarwinNotificationDetails(),
        ),
        payload: payload,
      );
    } catch (_) {}
  }

  static Future<void> remove(int id) async {
    try {
      await _plugin.cancel(id: id);
    } catch (_) {}
  }
}
