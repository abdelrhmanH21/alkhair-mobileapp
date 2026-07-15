import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'core/di/service_locator.dart';
import 'core/utils/push_notification_service.dart';
import 'app.dart';

// Runs in a separate isolate for background/terminated messages. The OS
// already shows the notification tray entry for a message with a
// `notification` payload (as sent by SendDelegateInvoiceNotification on the
// backend) — this handler only needs to keep Firebase initialized so the
// plugin doesn't crash; no extra background data processing is needed.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  setupServiceLocator();
  sl<PushNotificationService>().initialize();
  runApp(const AlKhairApp());
}
