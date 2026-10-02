import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'data/room_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const url = String.fromEnvironment('SUPABASE_URL');
  const key = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  final cloud = url.isNotEmpty && key.isNotEmpty;
  if (cloud) {
    await Supabase.initialize(url: url, publishableKey: key);
  }
  runApp(
    ToongApp(
      store: cloud
          ? CloudRoomStore(Supabase.instance.client)
          : LocalRoomStore(),
    ),
  );
}
