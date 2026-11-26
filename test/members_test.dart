import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toong/app.dart';
import 'package:toong/theme.dart';
import 'package:toong/data/room_store.dart';
import 'package:toong/domain/models.dart';

void main() {
  group('방장의 인원 추가·빼기', () {
    test('이름으로 추가하면 앱 계정 없는 참여자로 들어간다', () async {
      SharedPreferences.setMockInitialValues({});
      final store = LocalRoomStore();
      final room = await store.createRoom('모임', '민수');
      final added = await store.addMember(room, '  현우 ');
      expect(added.members.map((m) => m.name), ['민수', '현우']);
      expect(added.members.last.actorId, isNull);
      expect(added.version, room.version + 1);
      await expectLater(
        store.addMember(added, '현우'),
        throwsA(isA<StateError>()),
      );
      await expectLater(store.addMember(added, ''), throwsA(isA<StateError>()));
    });

    test('방장과 지출에 들어간 사람은 뺄 수 없다', () async {
      SharedPreferences.setMockInitialValues({});
      final store = LocalRoomStore();
      var room = await store.createRoom('모임', '민수');
      room = await store.addMember(room, '현우');
      room = await store.addMember(room, '지수');
      final [owner, hyunwoo, jisu] = room.members;
      room = await store.saveRoom(
        room.copyWith(
          expenses: [
            Expense(
              id: 'e1',
              title: '분식',
              payerId: owner.id,
              items: [
                LineItem(
                  id: 'i1',
                  name: '떡볶이',
                  amount: 9000,
                  memberIds: [owner.id, hyunwoo.id],
                ),
              ],
            ),
          ],
        ),
      );
      await expectLater(
        store.removeMember(room, owner.id),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        store.removeMember(room, hyunwoo.id),
        throwsA(isA<StateError>()),
      );
      room = await store.removeMember(room, jisu.id);
      expect(room.members.map((m) => m.name), ['민수', '현우']);
    });

    test('방장이 아니거나 얼린 방이면 바꿀 수 없다', () async {
      SharedPreferences.setMockInitialValues({});
      final store = LocalRoomStore();
      final prefs = await SharedPreferences.getInstance();
      var room = await store.createRoom('모임', '민수');
      final owner = prefs.getString('toong_actor_id')!;
      await prefs.setString('toong_actor_id', 'friend');
      room = await store.joinRoom(room.code, '지수');
      await expectLater(
        store.addMember(room, '현우'),
        throwsA(isA<StateError>()),
      );
      await prefs.setString('toong_actor_id', owner);
      room = await store.freezeRoom(room);
      await expectLater(
        store.addMember(room, '현우'),
        throwsA(isA<StateError>()),
      );
    });

    test('추가한 사람이 나중에 입장하면 기록을 연결할 수 있다', () async {
      SharedPreferences.setMockInitialValues({});
      final store = LocalRoomStore();
      final prefs = await SharedPreferences.getInstance();
      var room = await store.createRoom('모임', '민수');
      final owner = prefs.getString('toong_actor_id')!;
      room = await store.addMember(room, '현우');
      final placeholder = room.members.last.id;
      await prefs.setString('toong_actor_id', 'hyunwoo');
      room = await store.joinRoom(room.code, '현우폰');
      await prefs.setString('toong_actor_id', owner);
      room = await store.linkMember(room, placeholder, room.members.last.id);
      expect(room.members.map((m) => (m.name, m.actorId)), [
        ('민수', owner),
        ('현우', 'hyunwoo'),
      ]);
    });
  });

  testWidgets('방장은 방 화면에서 사람을 추가하고 뺄 수 있다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = LocalRoomStore();
    final room = await store.createRoom('저녁 모임', '민수');
    await tester.pumpWidget(
      MaterialApp(
        home: RoomPage(store: store, roomId: room.id),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('민수 빼기'), findsNothing);

    // 취소하면 아무것도 바뀌지 않는다.
    await tester.tap(find.text('사람 추가'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '서연');
    await tester.tap(find.widgetWithText(FilledButton, '취소'));
    await tester.pumpAndSettle();
    expect((await store.getRoom(room.id)).members, hasLength(1));

    await tester.tap(find.text('사람 추가'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '현우');
    await tester.tap(find.widgetWithText(FilledButton, '확인'));
    await tester.pumpAndSettle();
    expect(find.text('현우 · 미연결'), findsOneWidget);
    // 방장이 추가한 사람의 "미연결"은 빨간 글씨다.
    final label = tester.widget<Text>(find.text('현우 · 미연결'));
    final unlinked = (label.textSpan! as TextSpan).children!.single as TextSpan;
    expect(unlinked.text, ' · 미연결');
    expect(unlinked.style!.color, toongDanger);
    expect((await store.getRoom(room.id)).members, hasLength(2));

    await tester.tap(find.byTooltip('현우 빼기'));
    await tester.pumpAndSettle();
    expect(find.text('현우 님을 뺄까요?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '확인'));
    await tester.pumpAndSettle();
    expect(find.text('현우 · 미연결'), findsNothing);
    expect((await store.getRoom(room.id)).members, hasLength(1));
  });
}
