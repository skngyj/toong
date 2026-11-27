import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toong/app.dart';
import 'package:toong/data/nickname_store.dart';
import 'package:toong/data/room_store.dart';
import 'package:toong/qr_page.dart';

void main() {
  test('시간에 따라 아침·점심·저녁 인사', () {
    expect(greeting(DateTime(2026, 11, 27, 5), '민수'), '민수 님, 좋은 아침이에요 ☀️');
    expect(greeting(DateTime(2026, 11, 27, 10, 59), null), '좋은 아침이에요 ☀️');
    expect(
      greeting(DateTime(2026, 11, 27, 11), '민수'),
      '민수 님, 점심은 맛있게 드셨나요? 🍚',
    );
    expect(greeting(DateTime(2026, 11, 27, 17), '민수'), '민수 님, 오늘 하루도 수고했어요 🌙');
    expect(greeting(DateTime(2026, 11, 27, 2), null), '오늘 하루도 수고했어요 🌙');
  });

  testWidgets('시작 화면에서 닉네임을 정하고 바꾸고 지운다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    homeClock = () => DateTime(2026, 11, 27, 12);
    addTearDown(() => homeClock = DateTime.now);
    await tester.pumpWidget(ToongApp(store: LocalRoomStore()));
    await tester.pumpAndSettle();
    expect(find.text('점심은 맛있게 드셨나요? 🍚'), findsOneWidget);

    await tester.tap(find.byTooltip('닉네임 정하기'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '민수');
    await tester.tap(find.widgetWithText(FilledButton, '확인'));
    await tester.pumpAndSettle();
    expect(find.text('민수 님, 점심은 맛있게 드셨나요? 🍚'), findsOneWidget);
    expect(await NicknameStore().load(), '민수');

    await tester.tap(find.byTooltip('닉네임 바꾸기'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.widgetWithText(FilledButton, '확인'));
    await tester.pumpAndSettle();
    expect(find.text('점심은 맛있게 드셨나요? 🍚'), findsOneWidget);
    expect(await NicknameStore().load(), isNull);
  });

  testWidgets('방을 만든 닉네임이 저장되고 다음 입장과 시작 화면에 쓰인다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    homeClock = () => DateTime(2026, 11, 27, 8);
    addTearDown(() => homeClock = DateTime.now);
    await tester.pumpWidget(ToongApp(store: LocalRoomStore()));
    await tester.tap(find.text('새방 만들기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), '저녁 모임');
    await tester.enterText(find.byType(TextFormField).at(1), '지수');
    await tester.tap(find.text('방 만들기'));
    await tester.pumpAndSettle();
    expect(await NicknameStore().load(), '지수');

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('지수 님, 좋은 아침이에요 ☀️'), findsOneWidget);
    await tester.tap(find.text('방 코드로 입장'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, '지수'), findsOneWidget);
  });

  testWidgets('닉네임이 있으면 QR을 찍고 한 번 확인하면 바로 입장한다', (tester) async {
    SharedPreferences.setMockInitialValues({'toong_nickname': '현우'});
    final store = LocalRoomStore();
    final room = await store.createRoom('금요일 모임', '민수');
    // 다른 기기에서 찍은 것처럼 이 기기의 참여자 정보를 새로 만든다.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('toong_actor_id', 'other-device');
    final original = scanRoomQr;
    addTearDown(() => scanRoomQr = original);
    scanRoomQr = (_) async => room.code;
    await tester.pumpWidget(ToongApp(store: store));
    await tester.tap(find.text('방 코드로 입장'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('QR 스캔'));
    await tester.pumpAndSettle();
    expect(find.text('현우(으)로 입장할까요?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '확인'));
    await tester.pumpAndSettle();
    expect(find.text('금요일 모임'), findsWidgets);
    expect(find.text('방 코드'), findsOneWidget);
    final joined = await store.getRoom(room.id);
    expect(joined.members.map((m) => m.name), contains('현우'));
  });

  testWidgets('닉네임이 있으면 방 링크도 한 번 확인하고 바로 입장한다', (tester) async {
    SharedPreferences.setMockInitialValues({'toong_nickname': '현우'});
    final store = LocalRoomStore();
    final room = await store.createRoom('금요일 모임', '민수');
    // 다른 기기에서 링크를 연 것처럼 이 기기의 참여자 정보를 새로 만든다.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('toong_actor_id', 'other-device');
    final links = StreamController<Uri>();
    addTearDown(links.close);
    await tester.pumpWidget(ToongApp(store: store, links: links.stream));
    links.add(Uri.parse('toong://join/${room.code}'));
    await tester.pumpAndSettle();
    expect(find.text('게스트 이용 안내'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '확인'));
    await tester.pumpAndSettle();
    expect(find.text('현우(으)로 입장할까요?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '확인'));
    await tester.pumpAndSettle();
    expect(find.text('방 코드'), findsOneWidget);
    expect((await store.getRoom(room.id)).members.map((m) => m.name), [
      '민수',
      '현우',
    ]);
  });
}
