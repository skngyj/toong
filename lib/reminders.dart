import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'domain/subscription.dart';

/// 앞으로 몇 달 치 결제일 알림을 미리 예약할지. 앱을 열 때마다 다시 채운다.
const reminderMonths = 12;

/// 정기 구독 결제일 알림. 위젯 테스트에서 바꿔 끼울 수 있게 변수로 둔다.
Reminders reminders = PluginReminders();

/// 알림을 눌렀을 때 그 구독 id가 들어온다.
final reminderTaps = StreamController<String>.broadcast();

abstract class Reminders {
  /// 알림 권한을 묻는다(Android 13 이상). 허용됐으면 true.
  Future<bool> requestPermission();

  /// 이 구독의 알림을 모두 지우고 다가오는 결제일로 다시 예약한다.
  Future<void> schedule(Subscription sub, {DateTime? now});

  Future<void> cancel(Subscription sub);

  /// 결제일 알림을 지금 한 번 보여준다(미리 보기).
  Future<void> showNow(Subscription sub);
}

/// 알림 id: 구독마다 [Subscription.notifyBase] × 100부터, 결제일은 +0~11, 전날은 +50~61.
int billingNotificationId(Subscription s, int index) =>
    s.notifyBase * 100 + index;
int beforeNotificationId(Subscription s, int index) =>
    s.notifyBase * 100 + 50 + index;

class PluginReminders implements Reminders {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'subscription',
      '정기 구독 결제일',
      channelDescription: '함께 쓰는 구독의 결제일과 보낼·받을 돈을 알려줘요.',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
  );

  Future<void> _init() async {
    if (_ready) return;
    _ready = true;
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Seoul'));
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) {
        final id = response.payload;
        if (id != null && id.isNotEmpty) reminderTaps.add(id);
      },
    );
    // 꺼져 있던 앱이 알림으로 켜졌으면 그 구독을 연다.
    final launch = await _plugin.getNotificationAppLaunchDetails();
    final id = launch?.notificationResponse?.payload;
    if (launch?.didNotificationLaunchApp == true && id != null) {
      Future<void>.delayed(const Duration(milliseconds: 600), () {
        reminderTaps.add(id);
      });
    }
  }

  /// 앱이 켜질 때 부른다. 알림으로 켜졌는지 확인하고 알림을 받을 준비를 한다.
  Future<void> start() async {
    try {
      await _init();
    } catch (error) {
      debugPrint('reminders: $error');
    }
  }

  @override
  Future<bool> requestPermission() async {
    await _init();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    return await ios?.requestPermissions(alert: true, sound: true) ?? false;
  }

  @override
  Future<void> schedule(Subscription sub, {DateTime? now}) async {
    await _init();
    await cancel(sub);
    final from = now ?? DateTime.now();
    final dates = upcomingBillings(sub, from, reminderMonths);
    final billing = billingMessage(sub);
    final before = reminderMessage(sub);
    for (final (i, at) in dates.indexed) {
      await _plugin.zonedSchedule(
        id: billingNotificationId(sub, i),
        title: billing.title,
        body: billing.body,
        scheduledDate: tz.TZDateTime.from(at, tz.local),
        notificationDetails: _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: sub.id,
      );
      final dayBefore = at.subtract(const Duration(days: 1));
      if (sub.remindBefore && dayBefore.isAfter(from)) {
        await _plugin.zonedSchedule(
          id: beforeNotificationId(sub, i),
          title: before.title,
          body: before.body,
          scheduledDate: tz.TZDateTime.from(dayBefore, tz.local),
          notificationDetails: _details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: sub.id,
        );
      }
    }
  }

  @override
  Future<void> cancel(Subscription sub) async {
    await _init();
    for (var i = 0; i < reminderMonths; i++) {
      await _plugin.cancel(id: billingNotificationId(sub, i));
      await _plugin.cancel(id: beforeNotificationId(sub, i));
    }
  }

  @override
  Future<void> showNow(Subscription sub) async {
    await _init();
    final message = billingMessage(sub);
    await _plugin.show(
      id: sub.notifyBase * 100 + 99,
      title: message.title,
      body: message.body,
      notificationDetails: _details,
      payload: sub.id,
    );
  }
}
