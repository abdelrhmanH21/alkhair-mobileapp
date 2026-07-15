import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../../app.dart' show appNavigatorKey;
import '../network/api_client.dart';
import '../network/api_endpoints.dart';
import 'app_snackbar.dart';

/// Registers this device for Firebase Cloud Messaging and keeps the
/// server-side fcm_token in sync. Listeners are attached once at app
/// startup so a refreshed token is forwarded even between logins;
/// [registerForCurrentUser] additionally requests permission and pushes
/// the current token immediately after a successful login.
class PushNotificationService {
  final ApiClient _client;
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  bool _listenersAttached = false;

  PushNotificationService(this._client);

  void initialize() {
    _attachListeners();
  }

  Future<void> registerForCurrentUser() async {
    await _messaging.requestPermission(alert: true, badge: true, sound: true);
    _attachListeners();
    final token = await _messaging.getToken();
    if (token != null) {
      await _sendTokenToServer(token);
    }
  }

  void _attachListeners() {
    if (_listenersAttached) return;
    _listenersAttached = true;
    _messaging.onTokenRefresh.listen(_sendTokenToServer);
    FirebaseMessaging.onMessage.listen(_showForegroundNotification);
  }

  Future<void> _sendTokenToServer(String token) async {
    try {
      await _client.dio.post(ApiEndpoints.registerDeviceToken, data: {'fcm_token': token});
    } catch (e) {
      // Best-effort: a failed registration (e.g. not logged in yet) just
      // means this device won't receive pushes until the next attempt.
      debugPrint('FCM token registration failed: $e');
    }
  }

  void _showForegroundNotification(RemoteMessage message) {
    final notification = message.notification;
    final context = appNavigatorKey.currentContext;
    if (notification == null || context == null) return;
    AppSnackbar.showInfo(context, notification.body ?? notification.title ?? '');
  }
}
