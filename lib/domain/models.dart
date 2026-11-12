import 'dart:convert';

/// 정산을 완료하지 않은 방은 마지막 입력 후 이 시간이 지나면 삭제된다.
const roomInactiveLimit = Duration(hours: 48);

/// 방 하나를 연장할 수 있는 횟수. 연장하면 남은 시간이 48시간으로 돌아간다.
const roomExtendLimit = 3;

/// 얼린 방은 삭제 시간이 멈추지만, 얼린 뒤 이 기간이 지나면 삭제된다.
const roomFreezeLimit = Duration(days: 7);

/// 한 사람이 동시에 얼려 둘 수 있는 방 수.
const roomFreezeSlots = 2;

/// 정산을 완료한 방은 이 시간이 지나면 삭제된다. 기록은 각자 기기에 남는다.
const roomCompletedLimit = Duration(hours: 12);

const roomFrozenMessage = '얼린 방입니다. 방장이 녹인 뒤에 입력할 수 있어요.';
const roomCompletedMessage = '정산이 완료된 방입니다. 고치려면 정산을 복제해주세요.';
const roomExpiredMessage = '48시간 동안 입력이 없어 삭제된 방입니다.';
const roomMissingMessage = '방을 찾을 수 없어요. 48시간 동안 입력이 없어 삭제되었을 수 있습니다.';
const roomExpiryNotice = '정산을 완료하지 않고 48시간 동안 입력이 없으면 방이 삭제됩니다.';

/// 방 링크. 누르면 앱이 열리고 닉네임만 입력해 같은 방에 입장한다.
///
/// 코드를 경로에 둔다. `?code=`로 두면 Supabase 로그인 콜백으로 오인된다.
String roomLink(String code) => 'toong://join/$code';

/// 방 링크에서 방 코드를 꺼낸다. 방 링크가 아니면 null.
String? codeFromLink(Uri uri) {
  if (uri.scheme != 'toong' || uri.host != 'join') return null;
  final code = uri.pathSegments.firstOrNull?.toUpperCase() ?? '';
  return RegExp(r'^[A-Z0-9]{6,8}$').hasMatch(code) ? code : null;
}

/// 삭제까지 남은 시간을 "1일 3시간", "5시간 20분", "12분" 형태로 보여준다.
String formatRemaining(Duration remaining) {
  if (remaining <= Duration.zero) return '곧 삭제';
  final days = remaining.inDays;
  final hours = remaining.inHours % 24;
  final minutes = remaining.inMinutes % 60;
  if (days > 0) return hours > 0 ? '$days일 $hours시간' : '$days일';
  if (hours > 0) return minutes > 0 ? '$hours시간 $minutes분' : '$hours시간';
  return minutes > 0 ? '$minutes분' : '1분 미만';
}

class Member {
  const Member({required this.id, required this.name, this.actorId});
  final String id;
  final String name;
  final String? actorId;

  Member copyWith({String? name, String? actorId, bool clearActor = false}) =>
      Member(
        id: id,
        name: name ?? this.name,
        actorId: clearActor ? null : actorId ?? this.actorId,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'actor_id': actorId,
  };
  factory Member.fromJson(Map<String, dynamic> json) => Member(
    id: json['id'] as String,
    name: json['name'] as String,
    actorId: json['actor_id'] as String?,
  );
}

class LineItem {
  const LineItem({
    required this.id,
    required this.name,
    required this.amount,
    required this.memberIds,
    this.remainderMemberId,
  });
  final String id;
  final String name;
  final int amount;
  final List<String> memberIds;
  final String? remainderMemberId;

  int get remainder => memberIds.isEmpty ? 0 : amount % memberIds.length;
  bool get needsRemainder => remainder > 0 && remainderMemberId == null;

  LineItem copyWith({
    String? name,
    int? amount,
    List<String>? memberIds,
    String? remainderMemberId,
    bool clearRemainder = false,
  }) => LineItem(
    id: id,
    name: name ?? this.name,
    amount: amount ?? this.amount,
    memberIds: memberIds ?? this.memberIds,
    remainderMemberId: clearRemainder
        ? null
        : remainderMemberId ?? this.remainderMemberId,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'amount': amount,
    'member_ids': memberIds,
    'remainder_member_id': remainderMemberId,
  };
  factory LineItem.fromJson(Map<String, dynamic> json) => LineItem(
    id: json['id'] as String,
    name: json['name'] as String,
    amount: (json['amount'] as num).toInt(),
    memberIds: List<String>.from(json['member_ids'] as List),
    remainderMemberId: json['remainder_member_id'] as String?,
  );
}

class Expense {
  const Expense({
    required this.id,
    required this.title,
    required this.payerId,
    required this.items,
  });
  final String id;
  final String title;
  final String payerId;
  final List<LineItem> items;
  int get total => items.fold(0, (sum, item) => sum + item.amount);

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'payer_id': payerId,
    'items': items.map((item) => item.toJson()).toList(),
  };
  factory Expense.fromJson(Map<String, dynamic> json) => Expense(
    id: json['id'] as String,
    title: json['title'] as String,
    payerId: json['payer_id'] as String,
    items: (json['items'] as List)
        .map(
          (item) => LineItem.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(),
  );
}

class Room {
  const Room({
    required this.id,
    required this.code,
    required this.name,
    required this.ownerMemberId,
    required this.members,
    required this.expenses,
    required this.version,
    required this.lastActivityAt,
    this.sourceRoomId,
    this.extendCount = 0,
    this.frozenAt,
    this.completedAt,
  });
  final String id;
  final String code;
  final String name;
  final String ownerMemberId;
  final List<Member> members;
  final List<Expense> expenses;
  final int version;
  final String? sourceRoomId;

  /// 마지막 입력(생성·입장·저장·기록 연결) 시각. 조회만으로는 바뀌지 않는다.
  final DateTime lastActivityAt;

  /// 방장이 `방 연장`을 누른 횟수.
  final int extendCount;

  /// 방을 얼린 시각. 얼리지 않았으면 null.
  final DateTime? frozenAt;

  /// 정산을 완료한 시각. 완료하지 않았으면 null.
  final DateTime? completedAt;

  bool get isFrozen => frozenAt != null;
  bool get isCompleted => completedAt != null;
  int get extendsLeft => roomExtendLimit - extendCount;

  /// 방이 삭제되는 시각. 완료 12시간 뒤, 얼린 지 7일 뒤, 그 외에는 마지막 입력 48시간 뒤.
  DateTime get expiresAt =>
      completedAt?.add(roomCompletedLimit) ??
      frozenAt?.add(roomFreezeLimit) ??
      lastActivityAt.add(roomInactiveLimit);
  bool isExpiredAt(DateTime now) => !now.isBefore(expiresAt);
  Duration remainingAt(DateTime now) {
    final left = expiresAt.difference(now);
    return left.isNegative ? Duration.zero : left;
  }

  int get total => expenses.fold(0, (sum, expense) => sum + expense.total);
  int get pendingRemainder => expenses.fold(
    0,
    (sum, expense) =>
        sum +
        expense.items
            .where((item) => item.needsRemainder)
            .fold(0, (a, item) => a + item.remainder),
  );
  Member? actorMember(String actorId) {
    for (final member in members) {
      if (member.actorId == actorId) return member;
    }
    return null;
  }

  String memberName(String id) {
    for (final member in members) {
      if (member.id == id) return member.name;
    }
    return '알 수 없는 참여자';
  }

  bool owns(String actorId) => actorMember(actorId)?.id == ownerMemberId;

  Room copyWith({
    List<Member>? members,
    List<Expense>? expenses,
    int? version,
    DateTime? lastActivityAt,
    int? extendCount,
    DateTime? frozenAt,
    bool clearFrozen = false,
    DateTime? completedAt,
  }) => Room(
    id: id,
    code: code,
    name: name,
    ownerMemberId: ownerMemberId,
    members: members ?? this.members,
    expenses: expenses ?? this.expenses,
    version: version ?? this.version,
    lastActivityAt: lastActivityAt ?? this.lastActivityAt,
    sourceRoomId: sourceRoomId,
    extendCount: extendCount ?? this.extendCount,
    frozenAt: clearFrozen ? null : frozenAt ?? this.frozenAt,
    completedAt: completedAt ?? this.completedAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'code': code,
    'name': name,
    'owner_member_id': ownerMemberId,
    'members': members.map((member) => member.toJson()).toList(),
    'expenses': expenses.map((expense) => expense.toJson()).toList(),
    'version': version,
    'source_room_id': sourceRoomId,
    'last_activity_at': lastActivityAt.toUtc().toIso8601String(),
    'extend_count': extendCount,
    'frozen_at': frozenAt?.toUtc().toIso8601String(),
    'completed_at': completedAt?.toUtc().toIso8601String(),
  };

  /// [fallbackActivity]는 이 필드가 생기기 전에 저장된 방에 쓰인다.
  factory Room.fromJson(
    Map<String, dynamic> json, {
    DateTime? fallbackActivity,
  }) => Room(
    id: json['id'] as String,
    code: json['code'] as String,
    name: json['name'] as String,
    ownerMemberId: json['owner_member_id'] as String,
    members: (json['members'] as List)
        .map(
          (member) => Member.fromJson(Map<String, dynamic>.from(member as Map)),
        )
        .toList(),
    expenses: (json['expenses'] as List)
        .map(
          (expense) =>
              Expense.fromJson(Map<String, dynamic>.from(expense as Map)),
        )
        .toList(),
    version: (json['version'] as num).toInt(),
    lastActivityAt: json['last_activity_at'] is String
        ? DateTime.parse(json['last_activity_at'] as String).toUtc()
        : (fallbackActivity ?? DateTime.now()).toUtc(),
    sourceRoomId: json['source_room_id'] as String?,
    extendCount: (json['extend_count'] as num?)?.toInt() ?? 0,
    frozenAt: _time(json['frozen_at']),
    completedAt: _time(json['completed_at']),
  );
  static DateTime? _time(Object? value) =>
      value is String ? DateTime.parse(value).toUtc() : null;
  static Room decode(String source, {DateTime? fallbackActivity}) =>
      Room.fromJson(
        jsonDecode(source) as Map<String, dynamic>,
        fallbackActivity: fallbackActivity,
      );
  String encode() => jsonEncode(toJson());
}
