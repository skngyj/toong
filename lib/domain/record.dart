import 'dart:convert';

import 'models.dart';
import 'settlement.dart';

String _won(int value) => value.toString().replaceAllMapped(
  RegExp(r'\B(?=(\d{3})+(?!\d))'),
  (_) => ',',
);

String _two(int value) => value.toString().padLeft(2, '0');

String _stamp(DateTime time) {
  final t = time.toLocal();
  return '${t.year}-${_two(t.month)}-${_two(t.day)} '
      '${_two(t.hour)}:${_two(t.minute)}';
}

/// 완료된 방에서 있었던 모든 거래를 사람이 읽는 텍스트로 만든다.
///
/// 지출마다 결제자·항목·금액·부담자·잔돈 부담자, 개인별 결제액·부담액·순잔액,
/// 최종 송금(누가 누구에게 얼마)을 담는다. 정산이 계산되지 않는 방이면 예외를 던진다.
String buildRecordText(Room room) {
  final settlement = calculateSettlement(room);
  final completedAt = room.completedAt ?? room.lastActivityAt;
  final lines = <String>[
    '[퉁 정산 기록] ${room.name} (방 코드 ${room.code})',
    '정산 완료: ${_stamp(completedAt)} · 방장 ${room.memberName(room.ownerMemberId)}',
    '참여자: ${room.members.map((m) => m.name).join(', ')}',
    '총액: ${_won(room.total)}원',
    '',
  ];
  for (final (index, expense) in room.expenses.indexed) {
    lines.add(
      '${index + 1}. ${expense.title} · 결제 ${room.memberName(expense.payerId)} · '
      '${_won(expense.total)}원',
    );
    for (final item in expense.items) {
      final each = item.amount ~/ item.memberIds.length;
      final names = item.memberIds.map(room.memberName).join(', ');
      final share = item.memberIds.length == 1
          ? names
          : '$names (각 ${_won(each)}원)';
      final remainder = item.remainder > 0
          ? ' · 잔돈 ${_won(item.remainder)}원 '
                '${room.memberName(item.remainderMemberId!)} 부담'
          : '';
      lines.add('   - ${item.name} ${_won(item.amount)}원 · $share$remainder');
    }
  }
  lines
    ..add('')
    ..add('개인별 정산');
  for (final member in room.members) {
    final balance = settlement.balance[member.id]!;
    final sign = balance > 0 ? '+' : '';
    lines.add(
      '- ${member.name}: 결제 ${_won(settlement.paid[member.id]!)}원 · '
      '부담 ${_won(settlement.owed[member.id]!)}원 · '
      '$sign${_won(balance)}원',
    );
  }
  lines
    ..add('')
    ..add('최종 송금');
  if (settlement.transfers.isEmpty) {
    lines.add('- 주고받을 돈이 없습니다.');
  }
  for (final transfer in settlement.transfers) {
    lines.add(
      '- ${room.memberName(transfer.from)} → ${room.memberName(transfer.to)} '
      '${_won(transfer.amount)}원',
    );
  }
  return lines.join('\n');
}

/// 기기에 보관하는 완료된 정산 기록. 서버 방이 삭제된 뒤에도 남는다.
class SettlementRecord {
  const SettlementRecord({
    required this.roomId,
    required this.name,
    required this.completedAt,
    required this.text,
  });
  final String roomId;
  final String name;
  final DateTime completedAt;
  final String text;

  factory SettlementRecord.fromRoom(Room room) => SettlementRecord(
    roomId: room.id,
    name: room.name,
    completedAt: room.completedAt!,
    text: buildRecordText(room),
  );

  Map<String, dynamic> toJson() => {
    'room_id': roomId,
    'name': name,
    'completed_at': completedAt.toUtc().toIso8601String(),
    'text': text,
  };
  factory SettlementRecord.fromJson(Map<String, dynamic> json) =>
      SettlementRecord(
        roomId: json['room_id'] as String,
        name: json['name'] as String,
        completedAt: DateTime.parse(json['completed_at'] as String).toUtc(),
        text: json['text'] as String,
      );
  static SettlementRecord decode(String source) =>
      SettlementRecord.fromJson(jsonDecode(source) as Map<String, dynamic>);
  String encode() => jsonEncode(toJson());
}
