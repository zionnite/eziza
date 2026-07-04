import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get/get.dart';

import '../controllers/auth_controller.dart';
import '../controllers/delivery_controller.dart';
import '../pages/customer/customer_delivery_detail_page.dart';
import '../pages/customer/delivery_tracking_page.dart';
import 'supabase_service.dart';

// ── Background handler (top-level, required by firebase_messaging) ─

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Firebase is already initialized in main() before this fires.
  // The OS shows the notification automatically when the app is backgrounded/terminated.
}

// ── Channel constant ──────────────────────────────────────────────

const _kChannel = AndroidNotificationChannel(
  'eziza_jobs',
  'Eziza Jobs',
  description: 'Delivery alerts for riders, companies, and customers',
  importance: Importance.max,
  playSound: true,
);

// ── Service ───────────────────────────────────────────────────────

class FcmService {
  FcmService._();

  static final _messaging          = FirebaseMessaging.instance;
  static final _localNotifications = FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    // 1. Create the Android notification channel
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_kChannel);

    // 2. Configure local notifications (for foreground messages)
    await _localNotifications.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS:     DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: _onTap,
    );

    // 3. Request permission (iOS — Android 13+ handled by the OS prompt)
    final settings = await _messaging.requestPermission(
      alert:         true,
      badge:         true,
      sound:         true,
      announcement:  false,
      carPlay:       false,
      criticalAlert: false,
      provisional:   false,
    );

    final granted =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
    if (!granted) return;

    // 4. Get and save token
    await _refreshAndSaveToken();

    // 5. Token rotation
    _messaging.onTokenRefresh.listen(_saveToken);

    // 6. Foreground messages → show local notification
    FirebaseMessaging.onMessage.listen(_showLocalNotification);

    // 7. Notification tap when app was in background
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessage);

    // 8. Notification tap when app was terminated
    final initial = await _messaging.getInitialMessage();
    if (initial != null) _handleMessage(initial);
  }

  // ── Token ─────────────────────────────────────────────────────

  static Future<void> _refreshAndSaveToken() async {
    try {
      final token = await _messaging.getToken();
      if (token != null) await _saveToken(token);
    } catch (_) {
      // iOS: APNs token not yet available (no APNs key configured or simulator).
      // Token will arrive via onTokenRefresh once APNs is ready.
    }
  }

  static Future<void> _saveToken(String token) async {
    // Universal store — covers all roles (customer, company, rider)
    await SupabaseService.saveDeviceToken(token);

    // Also keep riders.fcm_token in sync for notify-new-job backward compat
    try {
      final riderId = Get.find<AuthController>().rider.value?.id;
      if (riderId != null) await SupabaseService.updateFcmToken(riderId, token);
    } catch (_) {}
  }

  // ── Foreground notification display ───────────────────────────

  static Future<void> _showLocalNotification(RemoteMessage message) async {
    final n = message.notification;
    if (n == null) return;

    await _localNotifications.show(
      message.hashCode,
      n.title,
      n.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _kChannel.id,
          _kChannel.name,
          channelDescription: _kChannel.description,
          importance:         _kChannel.importance,
          priority:           Priority.high,
          icon:               '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      // Encode full data so the tap handler can navigate with delivery_id
      payload: message.data.isNotEmpty ? jsonEncode(message.data) : null,
    );
  }

  // ── Tap handlers ──────────────────────────────────────────────

  static void _onTap(NotificationResponse response) {
    Map<String, dynamic> data = {};
    try {
      data = jsonDecode(response.payload ?? '{}') as Map<String, dynamic>;
    } catch (_) {}
    _navigate(data['type'] as String?, data);
  }

  static void _handleMessage(RemoteMessage message) {
    _navigate(message.data['type'] as String?, message.data);
  }

  static void _navigate(String? type, Map<String, dynamic> data) {
    final deliveryId = data['delivery_id'] as String?;
    final status     = data['status']      as String?;

    switch (type) {
      case 'bid_accepted':
      case 'new_job':
        // Rider: refresh controller so dashboard / active delivery updates
        try { Get.find<DeliveryController>().refresh(); } catch (_) {}

      case 'bid_placed':
        // Customer: open detail page so they can review and accept the bid
        if (deliveryId != null) {
          Get.to(() => CustomerDeliveryDetailPage(deliveryId: deliveryId));
        }

      case 'delivery_update':
        if (deliveryId == null) break;
        if (status == 'awaiting_pickup_confirm' || status == 'delivered') {
          // Customer needs to act (confirm handoff / confirm receipt) — detail page
          Get.to(() => CustomerDeliveryDetailPage(deliveryId: deliveryId));
        } else if (status == 'confirmed') {
          // Rider's delivery just completed — refresh their controller
          try { Get.find<DeliveryController>().refresh(); } catch (_) {}
        } else {
          // picked_up, assigned, etc. — live tracking
          Get.to(() => DeliveryTrackingPage(deliveryId: deliveryId));
        }

      case 'company_invite':
        // Rider: reload home tab so the invite card appears immediately
        try { Get.find<DeliveryController>().refresh(); } catch (_) {}

      case 'company_bid_accepted':
        break;
    }
  }
}
