import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toong/data/record_store.dart';
import 'package:toong/data/room_store.dart';
import 'package:toong/domain/models.dart';
import 'package:toong/domain/record.dart';

Matcher throwsMessage(Object message) =>
    throwsA(isA<StateError>().having((e) => e.message, 'message', message));

Expense meal(String payerId, {List<String>? memberIds, int amount = 10000}) =>
    Expense(
      id: 'meal',
      title: '식사',
      payerId: payerId,
      items: [
        LineItem(
          id: 'menu',
          name: '메뉴',
          amount: amount,
          memberIds: memberIds ?? [payerId],
        ),
      ],
    );

void main() {
  late DateTime now;
  late LocalRoomStore store;
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    now = DateTime.utc(2026, 11, 11, 12);
    store = LocalRoomStore(clock: () => now);
  });

  group('방 연장', () {
    test('남은 시간을 48시간으로 되돌리고 3회까지만 된다', () async {
      var room = await store.createRoom('모임', '민수');
      for (var i = 1; i <= roomExtendLimit; i++) {
        now = now.add(const Duration(hours: 40));
        room = await store.extendRoom(room);
        expect(room.extendCount, i);
        expect(room.remainingAt(now), roomInactiveLimit);
      }
      expect(room.extendsLeft, 0);
      await expectLater(
        store.extendRoom(room),
        throwsMessage(contains('더 연장할 수 없어요')),
      );
      now = now.add(const Duration(hours: 48));
      await expectLater(
        store.getRoom(room.id),
        throwsMessage(roomExpiredMessage),
      );
    });

    test('방장이 아니면 연장할 수 없고, 지출 저장은 연장 횟수를 바꾸지 못한다', () async {
      final room = await store.createRoom('모임', '민수');
      final owner = prefs.getString('toong_actor_id')!;
      await prefs.setString('toong_actor_id', 'friend');
      final joined = await store.joinRoom(room.code, '지수');
      await expectLater(
        store.extendRoom(joined),
        throwsMessage('방장만 할 수 있어요.'),
      );
      await prefs.setString('toong_actor_id', owner);
      final extended = await store.extendRoom(joined);
      final saved = await store.saveRoom(
        // 기기에서 오래된 상태(연장 0회)로 저장해도 저장된 횟수가 유지된다.
        joined.copyWith(
          version: extended.version,
          expenses: [meal(room.ownerMemberId)],
        ),
      );
      expect(saved.extendCount, 1);
    });
  });

  group('방 얼리기', () {
    test('얼리면 48시간이 지나도 남고 입력이 막히며, 녹이면 48시간을 다시 센다', () async {
      final room = await store.createRoom('모임', '민수');
      final frozen = await store.freezeRoom(room);
      expect(frozen.isFrozen, isTrue);
      expect(frozen.expiresAt, now.add(roomFreezeLimit));

      now = now.add(const Duration(days: 5));
      expect(await store.listRooms(), hasLength(1));
      await expectLater(
        store.saveRoom(frozen.copyWith(expenses: [meal(room.ownerMemberId)])),
        throwsMessage(roomFrozenMessage),
      );
      await expectLater(
        store.extendRoom(frozen),
        throwsMessage(roomFrozenMessage),
      );
      final owner = prefs.getString('toong_actor_id')!;
      await prefs.setString('toong_actor_id', 'friend');
      await expectLater(
        store.joinRoom(room.code, '지수'),
        throwsMessage(roomFrozenMessage),
      );
      await prefs.setString('toong_actor_id', owner);

      final thawed = await store.thawRoom(frozen);
      expect(thawed.isFrozen, isFalse);
      expect(thawed.remainingAt(now), roomInactiveLimit);
      final saved = await store.saveRoom(
        thawed.copyWith(expenses: [meal(room.ownerMemberId)]),
      );
      expect(saved.total, 10000);
    });

    test('얼린 지 7일이 지나면 삭제된다', () async {
      final frozen = await store.freezeRoom(await store.createRoom('모임', '민수'));
      now = now.add(roomFreezeLimit);
      await expectLater(
        store.thawRoom(frozen),
        throwsMessage(roomExpiredMessage),
      );
      expect(await store.listRooms(), isEmpty);
    });

    test('동시에 2개까지만 얼릴 수 있고, 녹이면 자리가 난다', () async {
      final a = await store.freezeRoom(await store.createRoom('하나', '민수'));
      await store.freezeRoom(await store.createRoom('둘', '민수'));
      final c = await store.createRoom('셋', '민수');
      await expectLater(
        store.freezeRoom(c),
        throwsMessage(contains('$roomFreezeSlots개까지만')),
      );
      await store.thawRoom(a);
      expect((await store.freezeRoom(c)).isFrozen, isTrue);
    });
  });

  group('정산 완료', () {
    test('지출이 없거나 잔돈이 남으면 완료할 수 없다', () async {
      final room = await store.createRoom('모임', '민수');
      await expectLater(
        store.completeRoom(room),
        throwsMessage(contains('지출이 없는 방')),
      );
      await prefs.setString('toong_actor_id', 'friend');
      final joined = await store.joinRoom(room.code, '지수');
      await prefs.setString('toong_actor_id', room.members.single.actorId!);
      final withRemainder = await store.saveRoom(
        joined.copyWith(
          expenses: [
            meal(
              room.ownerMemberId,
              amount: 10001,
              memberIds: joined.members.map((m) => m.id).toList(),
            ),
          ],
        ),
      );
      await expectLater(
        store.completeRoom(withRemainder),
        throwsMessage(contains('잔돈')),
      );
    });

    test('완료하면 수정·입장이 막히고 12시간 뒤 삭제되며 복제는 된다', () async {
      final room = await store.createRoom('모임', '민수');
      final saved = await store.saveRoom(
        room.copyWith(expenses: [meal(room.ownerMemberId)]),
      );
      now = now.add(const Duration(hours: 1));
      final done = await store.completeRoom(saved);
      expect(done.completedAt, now);
      expect(done.expiresAt, now.add(roomCompletedLimit));

      await expectLater(
        store.saveRoom(done.copyWith(expenses: [])),
        throwsMessage(roomCompletedMessage),
      );
      await expectLater(
        store.extendRoom(done),
        throwsMessage(roomCompletedMessage),
      );
      await expectLater(
        store.freezeRoom(done),
        throwsMessage(roomCompletedMessage),
      );
      await expectLater(
        store.completeRoom(done),
        throwsMessage(roomCompletedMessage),
      );

      final clone = await store.cloneRoom(done);
      expect(clone.isCompleted, isFalse);
      expect(clone.total, 10000);

      now = now.add(const Duration(hours: 11, minutes: 59));
      expect((await store.getRoom(done.id)).isCompleted, isTrue);
      now = now.add(const Duration(minutes: 1));
      await expectLater(
        store.getRoom(done.id),
        throwsMessage(roomExpiredMessage),
      );
      expect((await store.listRooms()).single.id, clone.id);
    });
  });

  group('정산 기록', () {
    Room example() {
      const a = Member(id: 'a', name: 'A', actorId: 'actor-a');
      const b = Member(id: 'b', name: 'B', actorId: 'actor-b');
      const c = Member(id: 'c', name: 'C', actorId: 'actor-c');
      return Room(
        id: 'room',
        code: 'ABC1234',
        name: '저녁 모임',
        ownerMemberId: 'a',
        members: const [a, b, c],
        expenses: const [
          Expense(
            id: 'e1',
            title: '음식점',
            payerId: 'a',
            items: [
              LineItem(id: 'i1', name: '스테이크', amount: 25000, memberIds: ['a']),
              LineItem(id: 'i2', name: '파스타', amount: 20000, memberIds: ['b']),
              LineItem(id: 'i3', name: '샐러드', amount: 15000, memberIds: ['c']),
            ],
          ),
          Expense(
            id: 'e2',
            title: '노래방',
            payerId: 'b',
            items: [
              LineItem(
                id: 'i4',
                name: '이용료',
                amount: 30001,
                memberIds: ['a', 'b', 'c'],
                remainderMemberId: 'b',
              ),
            ],
          ),
        ],
        version: 3,
        lastActivityAt: DateTime.utc(2026, 11, 11, 12),
        completedAt: DateTime.utc(2026, 11, 11, 13),
      );
    }

    test('모든 거래와 최종 송금을 텍스트로 남긴다', () {
      final text = buildRecordText(example());
      expect(text, startsWith('[퉁 정산 기록] 저녁 모임 (방 코드 ABC1234)'));
      expect(text, contains('방장 A'));
      expect(text, contains('참여자: A, B, C'));
      expect(text, contains('총액: 90,001원'));
      expect(text, contains('1. 음식점 · 결제 A · 60,000원'));
      expect(text, contains('   - 스테이크 25,000원 · A'));
      expect(text, contains('2. 노래방 · 결제 B · 30,001원'));
      expect(
        text,
        contains('   - 이용료 30,001원 · A, B, C (각 10,000원) · 잔돈 1원 B 부담'),
      );
      expect(text, contains('- A: 결제 60,000원 · 부담 35,000원 · +25,000원'));
      expect(text, contains('- B: 결제 30,001원 · 부담 30,001원 · 0원'));
      expect(text, contains('- C: 결제 0원 · 부담 25,000원 · -25,000원'));
      expect(text, endsWith('최종 송금\n- C → A 25,000원'));
    });

    test('완료된 방만 기기에 한 번 저장하고 지울 수 있다', () async {
      final records = RecordStore();
      final room = await store.createRoom('모임', '민수');
      await records.keep(room);
      expect(await records.list(), isEmpty);

      await records.keep(example());
      await records.keep(example());
      final saved = (await records.list()).single;
      expect(saved.name, '저녁 모임');
      expect(saved.text, buildRecordText(example()));

      await records.remove(saved.roomId);
      expect(await records.list(), isEmpty);
    });
  });
}
