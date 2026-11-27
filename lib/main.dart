import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'data/room_store.dart';
import 'reminders.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const url = String.fromEnvironment('SUPABASE_URL');
  const key = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  final cloud = url.isNotEmpty && key.isNotEmpty;
  if (cloud) {
    await Supabase.initialize(url: url, publishableKey: key);
  }
  // 정기 구독 알림으로 앱이 켜졌는지 확인하고, 알림을 누를 때를 받을 준비를 한다.
  await (reminders as PluginReminders).start();
  runApp(
    ToongApp(
      // 방 링크(toong://join/코드)로 앱을 열었을 때의 주소를 받는다.
      links: AppLinks().uriLinkStream,
      store: cloud
          ? CloudRoomStore(Supabase.instance.client)
          : LocalRoomStore(),
    ),
  );
}
