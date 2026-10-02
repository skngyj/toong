import 'dart:convert';

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
  }) => Room(
    id: id,
    code: code,
    name: name,
    ownerMemberId: ownerMemberId,
    members: members ?? this.members,
    expenses: expenses ?? this.expenses,
    version: version ?? this.version,
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
  };
  factory Room.fromJson(Map<String, dynamic> json) => Room(
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
    sourceRoomId: json['source_room_id'] as String?,
  );
  static Room decode(String source) =>
      Room.fromJson(jsonDecode(source) as Map<String, dynamic>);
  String encode() => jsonEncode(toJson());
}
