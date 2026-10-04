import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'backend.dart';

class PushService {
  static bool ready = false;
  static final openedForUser = ValueNotifier<String?>(null);
  static Future<void> initialize() async {
    const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
    const appId = String.fromEnvironment('FIREBASE_APP_ID');
    const sender = String.fromEnvironment('FIREBASE_SENDER_ID');
    const project = String.fromEnvironment('FIREBASE_PROJECT_ID');
    if (kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android ||
        apiKey.isEmpty ||
        appId.isEmpty ||
        sender.isEmpty ||
        project.isEmpty) {
      return;
    }
    try {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: apiKey,
          appId: appId,
          messagingSenderId: sender,
          projectId: project,
        ),
      );
      ready = true;
      FirebaseMessaging.onMessageOpenedApp.listen(_open);
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) _open(initial);
      FirebaseMessaging.instance.onTokenRefresh.listen((_) => sync());
      Backend.client.auth.onAuthStateChange.listen((_) => sync());
      await sync();
    } catch (_) {
      ready = false;
    }
  }

  static void _open(RemoteMessage message) {
    final owner = message.data['user_id'];
    if (owner != null && owner == Backend.userId) openedForUser.value = owner;
  }

  static Future<void> sync() async {
    if (!ready || Backend.userId == null) return;
    try {
      final settings = await FirebaseMessaging.instance
          .getNotificationSettings();
      if (settings.authorizationStatus != AuthorizationStatus.authorized) {
        return;
      }
      await _register();
    } catch (_) {
      /* User can retry using Enable notifications in the inbox. */
    }
  }

  static Future<void> _register() async {
    final uid = Backend.userId;
    final token = await FirebaseMessaging.instance.getToken();
    if (uid != null && uid == Backend.userId && token != null) {
      await Backend.client.rpc(
        'register_push_device',
        params: {'device_token': token},
      );
    }
  }

  static Future<String> enable() async {
    if (!ready) return 'Notifikasi HP belum diaktifkan untuk versi ini.';
    final settings = await FirebaseMessaging.instance.requestPermission();
    if (settings.authorizationStatus != AuthorizationStatus.authorized) {
      return 'Izin notifikasi belum diberikan. Aktifkan melalui pengaturan aplikasi di HP.';
    }
    await _register();
    return 'Perangkat terdaftar untuk menerima notifikasi.';
  }

  static Future<void> unregister() async {
    if (!ready) return;
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null && Backend.userId != null) {
      await Backend.client
          .from('push_devices')
          .delete()
          .eq('token', token)
          .eq('user_id', Backend.userId!);
    }
    await FirebaseMessaging.instance.deleteToken();
  }
}
