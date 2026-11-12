import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toong/data/room_store.dart';
import 'package:toong/domain/models.dart';

Matcher throwsMessage(String message) =>
    throwsA(isA<StateError>().having((e) => e.message, 'message', message));

Expense meal(String payerId) => Expense(
  id: 'meal',
  title: '식사',
  payerId: payerId,
  items: [
    LineItem(id: 'menu', name: '메뉴', amount: 10000, memberIds: [payerId]),
  ],
);

void main() {
  late DateTime now;
  late LocalRoomStore store;
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    now = DateTime.utc(2026, 11, 8, 12);
    store = LocalRoomStore(clock: () => now);
  });

  test('입력 없이 48시간이 지나면 입장·수정·복제를 막고 목록에서 지운다', () async {
    final room = await store.createRoom('모임', '민수');
    expect(room.lastActivityAt, now);
    expect(room.expiresAt, now.add(const Duration(hours: 48)));

    now = now.add(const Duration(hours: 47, minutes: 59));
    expect((await store.getRoom(room.id)).id, room.id);
    expect(await store.listRooms(), hasLength(1));

    now = now.add(const Duration(minutes: 1));
    await expectLater(
      store.getRoom(room.id),
      throwsMessage(roomExpiredMessage),
    );
    await expectLater(
      store.saveRoom(room.copyWith(expenses: [meal(room.ownerMemberId)])),
      throwsMessage(roomExpiredMessage),
    );
    await expectLater(store.cloneRoom(room), throwsMessage(roomExpiredMessage));
    await prefs.setString('toong_actor_id', 'friend-actor');
    await expectLater(
      store.joinRoom(room.code, '지수'),
      throwsMessage(roomExpiredMessage),
    );

    expect(await store.listRooms(), isEmpty);
    expect(prefs.getStringList('toong_rooms'), isEmpty);
    await expectLater(
      store.joinRoom(room.code, '지수'),
      throwsMessage('방 코드를 찾을 수 없습니다.'),
    );
  });

  test('입력은 48시간을 새로 세고, 열어 보기만 하면 그대로다', () async {
    final room = await store.createRoom('모임', '민수');

    now = now.add(const Duration(hours: 40));
    final viewed = await store.getRoom(room.id);
    await store.listRooms();
    expect(viewed.lastActivityAt, room.lastActivityAt);

    final saved = await store.saveRoom(
      viewed.copyWith(expenses: [meal(room.ownerMemberId)]),
    );
    expect(saved.lastActivityAt, now);

    now = now.add(const Duration(hours: 30));
    final owner = prefs.getString('toong_actor_id')!;
    await prefs.setString('toong_actor_id', 'friend-actor');
    final joined = await store.joinRoom(room.code, '지수');
    expect(joined.lastActivityAt, now);
    // 이미 참여한 방에 다시 들어가는 것은 입력이 아니다.
    final rejoinedAt = now.add(const Duration(hours: 1));
    now = rejoinedAt;
    expect(
      (await store.joinRoom(room.code, '지수')).lastActivityAt,
      joined.lastActivityAt,
    );

    await prefs.setString('toong_actor_id', owner);
    now = joined.lastActivityAt.add(const Duration(hours: 47));
    expect((await store.getRoom(room.id)).version, joined.version);
  });

  test('복제본은 48시간을 새로 세고 원본이 삭제돼도 남는다', () async {
    final room = await store.createRoom('모임', '민수');

    now = now.add(const Duration(hours: 47));
    final copy = await store.cloneRoom(room);
    expect(copy.lastActivityAt, now);
    expect(copy.sourceRoomId, room.id);

    now = now.add(const Duration(hours: 2));
    final rooms = await store.listRooms();
    expect(rooms.map((r) => r.id), [copy.id]);
    await expectLater(
      store.getRoom(room.id),
      throwsMessage(roomMissingMessage),
    );
    expect((await store.getRoom(copy.id)).sourceRoomId, room.id);
  });

  test('마지막 입력 시각이 없던 이전 방은 지금부터 48시간을 센다', () async {
    final legacy = jsonEncode({
      'id': 'old-room',
      'code': 'OLDROOM',
      'name': '예전 방',
      'owner_member_id': 'm1',
      'members': [
        {'id': 'm1', 'name': '민수', 'actor_id': 'me'},
      ],
      'expenses': [],
      'version': 3,
      'source_room_id': null,
    });
    SharedPreferences.setMockInitialValues({
      'toong_actor_id': 'me',
      'toong_rooms': [legacy],
    });
    prefs = await SharedPreferences.getInstance();

    final loaded = await store.getRoom('old-room');
    expect(loaded.lastActivityAt, now);
    expect(
      prefs.getStringList('toong_rooms')!.single,
      contains('"last_activity_at"'),
    );

    now = now.add(const Duration(hours: 48));
    expect(await store.listRooms(), isEmpty);
  });

  test('서버가 준 시각을 읽고 남은 시간을 보여준다', () {
    final room = Room.fromJson({
      'id': 'r',
      'code': 'ABC',
      'name': '모임',
      'owner_member_id': 'm1',
      'members': [],
      'expenses': [],
      'version': 0,
      'source_room_id': null,
      'last_activity_at': '2026-11-08T03:00:00.123456+00:00',
    });
    expect(room.lastActivityAt, DateTime.utc(2026, 11, 8, 3, 0, 0, 123, 456));
    final at = DateTime.utc(2026, 11, 8, 4);
    expect(formatRemaining(room.remainingAt(at)), '1일 23시간');
    expect(room.isExpiredAt(DateTime.utc(2026, 11, 10, 3, 0, 1)), isTrue);
    expect(room.remainingAt(DateTime.utc(2026, 11, 11)), Duration.zero);

    expect(formatRemaining(const Duration(hours: 48)), '2일');
    expect(formatRemaining(const Duration(hours: 5, minutes: 20)), '5시간 20분');
    expect(formatRemaining(const Duration(hours: 5)), '5시간');
    expect(formatRemaining(const Duration(minutes: 12)), '12분');
    expect(formatRemaining(const Duration(seconds: 30)), '1분 미만');
    expect(formatRemaining(Duration.zero), '곧 삭제');
  });
}
