import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toong/app.dart';
import 'package:toong/data/record_store.dart';
import 'package:toong/data/room_store.dart';
import 'package:toong/domain/models.dart';
import 'package:toong/domain/record.dart';
import 'package:toong/domain/settlement.dart';

/// 민수(방장)·지수·현우. 민수가 30,000원을 결제하고 셋이 나눠, 지수·현우가 민수에게 10,000원씩.
Future<(LocalRoomStore, Room, String owner)> setup() async {
  SharedPreferences.setMockInitialValues({});
  final store = LocalRoomStore();
  final prefs = await SharedPreferences.getInstance();
  var room = await store.createRoom('모임', '민수');
  final owner = prefs.getString('toong_actor_id')!;
  for (final (actor, name) in [('a-jisu', '지수'), ('a-hyunwoo', '현우')]) {
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
          payerId: ids[0],
          items: [
            LineItem(id: 'i1', name: '고기', amount: 30000, memberIds: ids),
          ],
        ),
      ],
    ),
  );
  return (store, room, owner);
}

Future<void> actAs(String actor) async =>
    (await SharedPreferences.getInstance()).setString('toong_actor_id', actor);

void main() {
  group('송금 완료 표시', () {
    test('보내는 사람·받는 사람·방장만 표시하고, 금액이 바뀌면 다시 확인한다', () async {
      final (store, room, owner) = await setup();
      final [jisuToMinsu, hyunwooToMinsu] = calculateSettlement(room).transfers;
      expect(room.memberName(jisuToMinsu.from), '지수');

      // 현우는 지수→민수 송금을 표시할 수 없다.
      await actAs('a-hyunwoo');
      await expectLater(
        store.markTransfer(room, jisuToMinsu, paid: true),
        throwsA(isA<StateError>()),
      );
      // 지수(보내는 사람)는 표시할 수 있다.
      await actAs('a-jisu');
      var updated = await store.markTransfer(room, jisuToMinsu, paid: true);
      expect(updated.isPaid(jisuToMinsu.from, jisuToMinsu.to, 10000), isTrue);
      expect(
        updated.paidMark(jisuToMinsu.from, jisuToMinsu.to)!.by,
        jisuToMinsu.from,
      );
      expect(updated.lastActivityAt, room.lastActivityAt);
      // 방장은 남의 송금도 표시할 수 있다.
      await actAs(owner);
      updated = await store.markTransfer(updated, hyunwooToMinsu, paid: true);
      expect(updated.paidTransfers, hasLength(2));
      // 풀기
      updated = await store.markTransfer(updated, hyunwooToMinsu, paid: false);
      expect(updated.paidTransfers, hasLength(1));

      // 지출이 바뀌어 금액이 달라지면 완료로 보지 않는다.
      final ids = updated.members.map((m) => m.id).toList();
      updated = await store.saveRoom(
        updated.copyWith(
          expenses: [
            Expense(
              id: 'e1',
              title: '고깃집',
              payerId: ids[0],
              items: [
                LineItem(id: 'i1', name: '고기', amount: 36000, memberIds: ids),
              ],
            ),
          ],
        ),
      );
      expect(updated.paidTransfers, hasLength(1));
      final t = calculateSettlement(updated).transfers.first;
      expect(updated.isPaid(t.from, t.to, t.amount), isFalse);
    });

    test('완료된 방의 기록 글자와 저장된 기록에 송금 완료가 반영된다', () async {
      final (store, room, owner) = await setup();
      final done = await store.completeRoom(room);
      final records = RecordStore();
      await records.keep(done);
      final t = calculateSettlement(done).transfers.first;
      final marked = await store.markTransfer(done, t, paid: true);
      await records.replace(marked);
      final saved = (await records.list()).single;
      expect(saved.text, contains('10,000원 (송금 완료)'));
      expect(saved.room!.paidTransfers, hasLength(1));
      expect(buildRecordText(marked), contains('(송금 완료)'));
    });
  });

  testWidgets('정산 결과에서 체크하면 물어보고 송금 완료로 표시하고, 풀 때도 묻는다', (tester) async {
    final (store, room, _) = await setup();
    await actAs('a-jisu');
    await tester.pumpWidget(
      MaterialApp(
        home: SettlementPage(store: store, room: room),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('송금 2건 중 0건 완료'), findsOneWidget);

    // 지수는 자기 송금만 체크할 수 있다.
    final mine = find.byTooltip('지수 → 민수 송금 완료 표시');
    final others = find.byTooltip('현우 → 민수 송금 완료 표시');
    expect(mine, findsOneWidget);
    await tester.tap(others);
    await tester.pumpAndSettle();
    expect(find.text('이 금액이 정산되었나요?'), findsNothing);

    // 체크 → 묻기 → 취소하면 그대로
    await tester.tap(mine);
    await tester.pumpAndSettle();
    expect(find.text('이 금액이 정산되었나요?'), findsOneWidget);
    expect(find.textContaining('지수 → 민수 10,000원을 송금 완료로'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '취소'));
    await tester.pumpAndSettle();
    expect(find.text('송금 2건 중 0건 완료'), findsOneWidget);

    // 체크 → 확인하면 완료
    await tester.tap(mine);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '확인'));
    await tester.pumpAndSettle();
    expect(find.text('송금 2건 중 1건 완료'), findsOneWidget);
    expect(find.text('송금 완료 · 지수 확인'), findsOneWidget);

    // 풀 때도 묻는다
    await tester.tap(find.byTooltip('지수 → 민수 송금 완료 풀기'));
    await tester.pumpAndSettle();
    expect(find.text('송금 완료 표시를 풀까요?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '확인'));
    await tester.pumpAndSettle();
    expect(find.text('송금 2건 중 0건 완료'), findsOneWidget);
    final saved = await store.getRoom(room.id);
    expect(saved.paidTransfers, isEmpty);
  });

  testWidgets('체크하지 않은 송금이 있으면 정산 완료 때 한 번 더 묻는다', (tester) async {
    final (store, room, _) = await setup();
    // 지수→민수만 체크해 둔다.
    await actAs('a-jisu');
    final first = calculateSettlement(room).transfers.first;
    var marked = await store.markTransfer(room, first, paid: true);
    final prefs = await SharedPreferences.getInstance();
    final owner = (await store.getRoom(room.id)).members.first.actorId!;
    await prefs.setString('toong_actor_id', owner);
    expect(unpaidTransfers(marked), 1);

    await tester.pumpWidget(
      MaterialApp(
        home: RoomPage(store: store, roomId: room.id),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('정산 완료'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('정산 완료'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '확인'));
    await tester.pumpAndSettle();
    expect(find.text('아직 체크하지 않은 송금이 있어요'), findsOneWidget);
    expect(find.textContaining('체크하지 않은 송금이 1건'), findsOneWidget);
    // 취소하면 완료하지 않는다.
    await tester.tap(find.widgetWithText(FilledButton, '취소'));
    await tester.pumpAndSettle();
    expect((await store.getRoom(room.id)).isCompleted, isFalse);

    // 다시 눌러 두 번 모두 확인하면 완료되고, 출력되는 정산서에는 체크 표시가 없다.
    await tester.tap(find.text('정산 완료'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '확인'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '확인'));
    await tester.pumpAndSettle();
    expect((await store.getRoom(room.id)).isCompleted, isTrue);
    expect(find.text('퉁 정산서'), findsOneWidget);
    expect(find.textContaining('✓'), findsNothing);
    marked = await store.getRoom(room.id);
    expect(marked.paidTransfers, hasLength(1));
  });

  testWidgets('모두 체크했으면 정산 완료 때 따로 묻지 않는다', (tester) async {
    final (store, room, owner) = await setup();
    var r = room;
    for (final t in calculateSettlement(room).transfers) {
      r = await store.markTransfer(r, t, paid: true);
    }
    expect(unpaidTransfers(r), 0);
    await tester.pumpWidget(
      MaterialApp(
        home: RoomPage(store: store, roomId: room.id),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('정산 완료'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('정산 완료'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '확인'));
    await tester.pumpAndSettle();
    expect(find.text('아직 체크하지 않은 송금이 있어요'), findsNothing);
    expect((await store.getRoom(room.id)).isCompleted, isTrue);
  });
}
