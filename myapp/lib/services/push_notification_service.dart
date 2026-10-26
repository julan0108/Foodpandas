import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'order_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

class PushNotificationService {
  PushNotificationService({FirebaseMessaging? messaging})
    : _messaging = messaging ?? FirebaseMessaging.instance;

  final FirebaseMessaging _messaging;
  StreamSubscription<String>? _registrationSubscription;
  StreamSubscription<RemoteMessage>? _messageSubscription;
  String? _registrationId;

  Future<void> initialize({
    required String userId,
    required OrderService orderService,
  }) async {
    try {
      final permission = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (permission.authorizationStatus == AuthorizationStatus.denied) return;
      await _registrationSubscription?.cancel();
      _registrationSubscription = _messaging.onRegistered.listen((
        installationId,
      ) {
        _registrationId = installationId;
        unawaited(
          orderService.saveDeviceToken(userId, installationId, _platformName),
        );
      });
      await _messaging.register(
        vapidKey: kIsWeb ? const String.fromEnvironment('FCM_VAPID_KEY') : null,
        serviceWorkerScriptPath: kIsWeb ? 'firebase-messaging-sw.js' : null,
      );
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
      await _messageSubscription?.cancel();
      _messageSubscription = FirebaseMessaging.onMessage.listen((_) {});
    } catch (_) {
      // Orders remain visible in the in-app notification center when push setup
      // is unavailable (for example, a browser without HTTPS/VAPID configured).
    }
  }

  String get _platformName {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      TargetPlatform.macOS => 'macos',
      TargetPlatform.windows => 'windows',
      TargetPlatform.linux => 'linux',
      TargetPlatform.fuchsia => 'other',
    };
  }

  Future<void> dispose() async {
    await _registrationSubscription?.cancel();
    await _messageSubscription?.cancel();
  }

  Future<void> detachUser({
    required String userId,
    required OrderService orderService,
  }) async {
    await _registrationSubscription?.cancel();
    _registrationSubscription = null;
    final registrationId = _registrationId;
    _registrationId = null;
    if (registrationId != null) {
      await orderService.removeDeviceToken(userId, registrationId);
    }
  }
}
