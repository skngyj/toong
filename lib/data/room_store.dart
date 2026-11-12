import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/models.dart';

String newId() {
  final random = Random.secure();
  return List.generate(32, (_) => random.nextInt(16).toRadixString(16)).join();
}

abstract class RoomStore {
  bool get isCloud;
  Future<String> actorId();
  Future<List<Room>> listRooms();
  Future<Room> createRoom(String name, String nickname);
  Future<Room> joinRoom(String code, String nickname);
  Future<Room> getRoom(String id);
  Future<Room> saveRoom(Room room);
  Future<Room> cloneRoom(Room source);
  Future<Room> linkMember(Room room, String historicalId, String joinedId);

  /// 남은 시간을 48시간으로 되돌린다. 방 하나당 [roomExtendLimit]회, 방장만.
  Future<Room> extendRoom(Room room);

  /// 방을 얼려 삭제 시간을 멈춘다. 동시에 [roomFreezeSlots]개, 방장만.
  Future<Room> freezeRoom(Room room);

  /// 얼린 방을 녹인다. 그때부터 48시간을 다시 센다.
  Future<Room> thawRoom(Room room);

  /// 정산을 완료한다. 방은 [roomCompletedLimit] 뒤 삭제된다.
  Future<Room> completeRoom(Room room);
}

/// 체험 모드 저장소. 서버와 같은 48시간 규칙을 기기 안에서 적용한다.
///
/// 기한이 지난 방은 즉시 입장·수정·복제를 막고, 방 목록을 불러올 때 실제로 지운다.
class LocalRoomStore implements RoomStore {
  LocalRoomStore({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;
  final DateTime Function() _clock;

  DateTime get _now => _clock().toUtc();

  @override
  bool get isCloud => false;

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Room _live(Room room) {
    if (room.isExpiredAt(_now)) throw StateError(roomExpiredMessage);
    return room;
  }

  /// 입력을 받을 수 있는 방인지 확인한다. 얼린 방과 완료된 방은 입력을 막는다.
  Room _editable(Room room) {
    _live(room);
    if (room.isCompleted) throw StateError(roomCompletedMessage);
    if (room.isFrozen) throw StateError(roomFrozenMessage);
    return room;
  }

  /// 방장이 [change]로 방 상태를 바꾼다. 연장·얼리기·녹이기·완료가 함께 쓴다.
  Future<Room> _ownerUpdate(
    Room room,
    Room Function(Room current, List<Room> all, String actor) change,
  ) async {
    final rooms = await _all();
    final index = rooms.indexWhere((r) => r.id == room.id);
    if (index < 0) throw StateError(roomMissingMessage);
    final actor = await actorId();
    final current = _live(rooms[index]);
    if (!current.owns(actor)) throw StateError('방장만 할 수 있어요.');
    final updated = change(
      current,
      rooms,
      actor,
    ).copyWith(version: current.version + 1);
    rooms[index] = updated;
    await _write(rooms);
    return updated;
  }

  @override
  Future<Room> extendRoom(Room room) => _ownerUpdate(room, (current, _, _) {
    _editable(current);
    if (current.extendsLeft <= 0) {
      throw StateError('이 방은 더 연장할 수 없어요. (최대 $roomExtendLimit회)');
    }
    return current.copyWith(
      lastActivityAt: _now,
      extendCount: current.extendCount + 1,
    );
  });

  @override
  Future<Room> freezeRoom(Room room) =>
      _ownerUpdate(room, (current, all, actor) {
        _editable(current);
        final frozen = all.where(
          (r) => r.isFrozen && r.owns(actor) && !r.isExpiredAt(_now),
        );
        if (frozen.length >= roomFreezeSlots) {
          throw StateError('방은 동시에 $roomFreezeSlots개까지만 얼릴 수 있어요.');
        }
        return current.copyWith(frozenAt: _now);
      });

  @override
  Future<Room> thawRoom(Room room) => _ownerUpdate(room, (current, _, _) {
    if (!current.isFrozen) throw StateError('얼린 방이 아니에요.');
    return current.copyWith(clearFrozen: true, lastActivityAt: _now);
  });

  @override
  Future<Room> completeRoom(Room room) => _ownerUpdate(room, (current, _, _) {
    _editable(current);
    if (current.expenses.isEmpty) {
      throw StateError('지출이 없는 방은 정산을 완료할 수 없어요.');
    }
    if (current.pendingRemainder > 0) {
      throw StateError('남은 잔돈의 부담자를 먼저 정해주세요.');
    }
    return current.copyWith(completedAt: _now);
  });

  @override
  Future<String> actorId() async {
    final prefs = await _prefs;
    var id = prefs.getString('toong_actor_id');
    if (id == null) {
      id = newId();
      await prefs.setString('toong_actor_id', id);
    }
    return id;
  }

  Future<List<Room>> _all() async {
    final prefs = await _prefs;
    final raw = prefs.getStringList('toong_rooms') ?? [];
    final now = _now;
    final rooms = raw
        .map((source) => Room.decode(source, fallbackActivity: now))
        .toList();
    // 마지막 입력 시각이 없던 이전 버전의 방은 지금부터 48시간을 센다.
    if (raw.any((source) => !source.contains('"last_activity_at"'))) {
      await _write(rooms);
    }
    return rooms;
  }

  /// 기한이 지난 방을 기기에서 지운다.
  Future<List<Room>> _purgeExpired() async {
    final rooms = await _all();
    final live = rooms.where((r) => !r.isExpiredAt(_now)).toList();
    if (live.length != rooms.length) await _write(live);
    return live;
  }

  Future<void> _write(List<Room> rooms) async {
    final prefs = await _prefs;
    await prefs.setStringList(
      'toong_rooms',
      rooms.map((r) => r.encode()).toList(),
    );
  }

  @override
  Future<List<Room>> listRooms() async {
    final actor = await actorId();
    return (await _purgeExpired())
        .where((r) => r.actorMember(actor) != null)
        .toList()
        .reversed
        .toList();
  }

  @override
  Future<Room> createRoom(String name, String nickname) async {
    final rooms = await _all();
    final actor = await actorId();
    final alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    String code;
    do {
      code = List.generate(
        7,
        (_) => alphabet[random.nextInt(alphabet.length)],
      ).join();
    } while (rooms.any((r) => r.code == code));
    final member = Member(id: newId(), name: nickname, actorId: actor);
    final room = Room(
      id: newId(),
      code: code,
      name: name,
      ownerMemberId: member.id,
      members: [member],
      expenses: [],
      version: 0,
      lastActivityAt: _now,
    );
    await _write([...rooms, room]);
    return room;
  }

  @override
  Future<Room> joinRoom(String code, String nickname) async {
    final rooms = await _all();
    final index = rooms.indexWhere((r) => r.code == code.toUpperCase());
    if (index < 0) throw StateError('방 코드를 찾을 수 없습니다.');
    final actor = await actorId();
    final room = _live(rooms[index]);
    if (room.actorMember(actor) != null) return room;
    _editable(room);
    final updated = room.copyWith(
      members: [
        ...room.members,
        Member(id: newId(), name: nickname, actorId: actor),
      ],
      version: room.version + 1,
      lastActivityAt: _now,
    );
    rooms[index] = updated;
    await _write(rooms);
    return updated;
  }

  @override
  Future<Room> getRoom(String id) async {
    final actor = await actorId();
    for (final room in await _all()) {
      if (room.id == id && room.actorMember(actor) != null) return _live(room);
    }
    throw StateError(roomMissingMessage);
  }

  @override
  Future<Room> saveRoom(Room room) async {
    final rooms = await _all();
    final index = rooms.indexWhere((r) => r.id == room.id);
    if (index < 0) throw StateError(roomMissingMessage);
    _editable(rooms[index]);
    if (!rooms[index].owns(await actorId())) {
      throw StateError('방장만 지출과 잔돈을 수정할 수 있습니다.');
    }
    if (rooms[index].version != room.version) {
      throw StateError('방 내용이 바뀌었습니다. 새로고침 후 다시 시도해주세요.');
    }
    if (jsonEncode(rooms[index].members.map((m) => m.toJson()).toList()) !=
        jsonEncode(room.members.map((m) => m.toJson()).toList())) {
      throw StateError('참여자 변경은 별도 절차로 진행해주세요.');
    }
    // 연장 횟수·얼림·완료 상태는 저장된 값을 따른다.
    final updated = rooms[index].copyWith(
      expenses: room.expenses,
      version: room.version + 1,
      lastActivityAt: _now,
    );
    rooms[index] = updated;
    await _write(rooms);
    return updated;
  }

  @override
  Future<Room> cloneRoom(Room source) async {
    final current = await getRoom(source.id);
    final actor = await actorId();
    final me = current.actorMember(actor);
    if (me == null) throw StateError('참여 중인 방만 복제할 수 있습니다.');
    final blank = await createRoom('${current.name} 복제', me.name);
    final cloned = Room(
      id: blank.id,
      code: blank.code,
      name: blank.name,
      ownerMemberId: me.id,
      members: current.members
          .map(
            (m) => m.copyWith(
              actorId: m.id == me.id ? actor : null,
              clearActor: m.id != me.id,
            ),
          )
          .toList(),
      expenses: current.expenses
          .map((e) => Expense.fromJson(e.toJson()))
          .toList(),
      version: blank.version,
      lastActivityAt: blank.lastActivityAt,
      sourceRoomId: current.id,
    );
    final rooms = await _all();
    final index = rooms.indexWhere((r) => r.id == blank.id);
    rooms[index] = cloned;
    await _write(rooms);
    return cloned;
  }

  @override
  Future<Room> linkMember(
    Room room,
    String historicalId,
    String joinedId,
  ) async {
    final current = _editable(await getRoom(room.id));
    if (!current.owns(await actorId())) throw StateError('방장만 기록을 연결할 수 있습니다.');
    final old = current.members.where((m) => m.id == historicalId).firstOrNull;
    final fresh = current.members.where((m) => m.id == joinedId).firstOrNull;
    if (old == null ||
        fresh?.actorId == null ||
        old.actorId != null ||
        current.expenses.any(
          (e) =>
              e.payerId == joinedId ||
              e.items.any((i) => i.memberIds.contains(joinedId)),
        )) {
      throw StateError('연결할 수 없는 참여자입니다.');
    }
    final updated = current.copyWith(
      members: current.members
          .where((m) => m.id != joinedId)
          .map(
            (m) =>
                m.id == historicalId ? m.copyWith(actorId: fresh!.actorId) : m,
          )
          .toList(),
    );
    final rooms = await _all();
    rooms[rooms.indexWhere((r) => r.id == room.id)] = updated.copyWith(
      version: current.version + 1,
      lastActivityAt: _now,
    );
    await _write(rooms);
    return rooms.firstWhere((r) => r.id == room.id);
  }
}

class CloudRoomStore implements RoomStore {
  CloudRoomStore(this.client);
  final SupabaseClient client;
  @override
  bool get isCloud => true;

  Future<void> _signIn() async {
    if (client.auth.currentUser == null) {
      await client.auth.signInAnonymously();
    }
  }

  @override
  Future<String> actorId() async {
    await _signIn();
    return client.auth.currentUser!.id;
  }

  Room _room(dynamic value) =>
      Room.fromJson(Map<String, dynamic>.from(value as Map));

  @override
  Future<List<Room>> listRooms() async {
    await _signIn();
    final rows = await client
        .from('rooms')
        .select('data')
        .order('created_at', ascending: false);
    return rows.map((row) => _room(row['data'])).toList();
  }

  /// 방이 없는 익명 사용자는 서버에서 정리된다. 정리된 사용자의 세션으로
  /// 방을 만들거나 입장하면 서버가 [_staleSessionCode]로 거절하므로,
  /// 새 익명 사용자로 다시 로그인해 한 번 더 시도한다.
  Future<Room> _withFreshSession(Future<dynamic> Function() call) async {
    await _signIn();
    try {
      return _room(await call());
    } on PostgrestException catch (error) {
      if (error.code != _staleSessionCode) rethrow;
      await client.auth.signOut(scope: SignOutScope.local);
      await client.auth.signInAnonymously();
      return _room(await call());
    }
  }

  static const _staleSessionCode = 'TG401';

  @override
  Future<Room> createRoom(String name, String nickname) => _withFreshSession(
    () => client.rpc(
      'create_toong_room',
      params: {'p_name': name, 'p_nickname': nickname},
    ),
  );

  @override
  Future<Room> joinRoom(String code, String nickname) => _withFreshSession(
    () => client.rpc(
      'join_toong_room',
      params: {'p_code': code, 'p_nickname': nickname},
    ),
  );

  Future<Room> _roomAction(String function, Room room) async {
    await _signIn();
    return _room(await client.rpc(function, params: {'p_room_id': room.id}));
  }

  @override
  Future<Room> extendRoom(Room room) => _roomAction('extend_toong_room', room);

  @override
  Future<Room> freezeRoom(Room room) => _roomAction('freeze_toong_room', room);

  @override
  Future<Room> thawRoom(Room room) => _roomAction('thaw_toong_room', room);

  @override
  Future<Room> completeRoom(Room room) =>
      _roomAction('complete_toong_room', room);

  @override
  Future<Room> getRoom(String id) async {
    await _signIn();
    // 기한이 지난 방은 서버 정책에서 보이지 않는다.
    final row = await client
        .from('rooms')
        .select('data')
        .eq('id', id)
        .maybeSingle();
    if (row == null) throw StateError(roomMissingMessage);
    return _room(row['data']);
  }

  @override
  Future<Room> saveRoom(Room room) async {
    await _signIn();
    return _room(
      await client.rpc(
        'save_toong_room',
        params: {
          'p_room_id': room.id,
          'p_version': room.version,
          'p_data': room.toJson(),
        },
      ),
    );
  }

  @override
  Future<Room> cloneRoom(Room room) async {
    await _signIn();
    return _room(
      await client.rpc('clone_toong_room', params: {'p_room_id': room.id}),
    );
  }

  @override
  Future<Room> linkMember(
    Room room,
    String historicalId,
    String joinedId,
  ) async {
    await _signIn();
    return _room(
      await client.rpc(
        'link_toong_member',
        params: {
          'p_room_id': room.id,
          'p_historical_id': historicalId,
          'p_joined_id': joinedId,
        },
      ),
    );
  }
}
