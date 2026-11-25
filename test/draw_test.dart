import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toong/app.dart';
import 'package:toong/data/room_store.dart';
import 'package:toong/domain/models.dart';

/// 항상 [value]번째 후보를 뽑는 난수.
class FixedRandom implements Random {
  FixedRandom(this.value);
  final int value;
  @override
  int nextInt(int max) => value % max;
  @override
  double nextDouble() => 0;
  @override
  bool nextBool() => false;
}

/// 민수(방장)·지수·현우 세 명이 10,000원을 나눠 잔돈 1원이 남은 방.
Future<(LocalRoomStore, Room)> roomWithRemainder() async {
  SharedPreferences.setMockInitialValues({});
  final store = LocalRoomStore();
  final prefs = await SharedPreferences.getInstance();
  var room = await store.createRoom('모임', '민수');
  final owner = prefs.getString('toong_actor_id')!;
  for (final (actor, name) in [('a2', '지수'), ('a3', '현우')]) {
    await prefs.setString('toong_actor_id', actor);
    room = await store.joinRoom(room.code, name);
  }
  await prefs.setString('toong_actor_id', owner);
  final ids = room.members.map((m) => m.id).toList();
  room = await store.saveRoom(
    room.copyWith(
      expenses: [
        Expense(
          id: 'e1',
          title: '고깃집',
          payerId: ids.first,
          items: [
            LineItem(id: 'i1', name: '삼겹살', amount: 10000, memberIds: ids),
          ],
        ),
      ],
    ),
  );
  return (store, room);
}

void main() {
  testWidgets('잔돈을 추첨하면 뽑힌 사람이 부담자로 저장된다', (tester) async {
    final (store, room) = await roomWithRemainder();
    drawRandom = FixedRandom(1);
    await tester.pumpWidget(
      MaterialApp(
        home: RemainderPage(store: store, room: room, canEdit: true),
      ),
    );
    await tester.tap(find.text('추첨으로 정하기'));
    await tester.pumpAndSettle();
    expect(find.text('잔돈 추첨'), findsOneWidget);

    // 돌리기 전에는 확인을 누를 수 없다.
    FilledButton confirm() =>
        tester.widget(find.widgetWithText(FilledButton, '확인'));
    expect(confirm().onPressed, isNull);

    // 후보를 모두 빼면 돌릴 수 없고, 모두 선택으로 되돌린다.
    await tester.tap(find.widgetWithText(FilterChip, '모두 선택'));
    await tester.pump();
    expect(find.text('추첨할 사람을 한 명 이상 골라주세요.'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilterChip, '모두 선택'));
    await tester.pump();
    expect(find.text('후보 3명 중 한 명을 뽑아요.'), findsOneWidget);

    await tester.tap(find.text('돌리기'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(confirm().onPressed, isNull);
    await tester.pumpAndSettle();
    expect(find.text('지수 님이 잔돈 1원을 내요!'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('draw-slot'))).data, '지수');

    await tester.tap(find.widgetWithText(FilledButton, '확인'));
    await tester.pumpAndSettle();
    final saved = await store.getRoom(room.id);
    final item = saved.expenses.single.items.single;
    expect(saved.memberName(item.remainderMemberId!), '지수');
    expect(find.text('잔돈 지정 완료'), findsOneWidget);
  });

  testWidgets('추첨 후보에서 뺀 사람은 뽑히지 않는다', (tester) async {
    final (store, room) = await roomWithRemainder();
    drawRandom = FixedRandom(1);
    await tester.pumpWidget(
      MaterialApp(
        home: RemainderPage(store: store, room: room, canEdit: true),
      ),
    );
    await tester.tap(find.text('추첨으로 정하기'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, '지수'));
    await tester.pump();
    await tester.tap(find.text('돌리기'));
    await tester.pumpAndSettle();
    // 후보는 민수·현우, 두 번째 후보인 현우가 뽑힌다.
    expect(find.text('현우 님이 잔돈 1원을 내요!'), findsOneWidget);

    // 취소하면 저장하지 않는다.
    await tester.tap(find.widgetWithText(FilledButton, '취소'));
    await tester.pumpAndSettle();
    final saved = await store.getRoom(room.id);
    expect(saved.expenses.single.items.single.remainderMemberId, isNull);
  });

  testWidgets('방장이 아니면 추첨 버튼이 없다', (tester) async {
    final (store, room) = await roomWithRemainder();
    await tester.pumpWidget(
      MaterialApp(
        home: RemainderPage(store: store, room: room, canEdit: false),
      ),
    );
    expect(find.text('추첨으로 정하기'), findsNothing);
  });
}
