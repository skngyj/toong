import 'dart:convert';

/// 정산을 완료하지 않은 방은 마지막 입력 후 이 시간이 지나면 삭제된다.
const roomInactiveLimit = Duration(hours: 48);

const roomExpiredMessage = '48시간 동안 입력이 없어 삭제된 방입니다.';
const roomMissingMessage = '방을 찾을 수 없어요. 48시간 동안 입력이 없어 삭제되었을 수 있습니다.';
const roomExpiryNotice = '정산을 완료하지 않고 48시간 동안 입력이 없으면 방이 삭제됩니다.';

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

  DateTime get expiresAt => lastActivityAt.add(roomInactiveLimit);
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
  );
  static Room decode(String source, {DateTime? fallbackActivity}) =>
      Room.fromJson(
        jsonDecode(source) as Map<String, dynamic>,
        fallbackActivity: fallbackActivity,
      );
  String encode() => jsonEncode(toJson());
}
