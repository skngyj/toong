import 'models.dart';

class Transfer {
  const Transfer(this.from, this.to, this.amount);
  final String from;
  final String to;
  final int amount;
}

class Settlement {
  const Settlement({
    required this.paid,
    required this.owed,
    required this.balance,
    required this.transfers,
  });
  final Map<String, int> paid;
  final Map<String, int> owed;
  final Map<String, int> balance;
  final List<Transfer> transfers;
}

Settlement calculateSettlement(Room room) {
  final ids = room.members.map((m) => m.id).toSet();
  final paid = {for (final id in ids) id: 0};
  final owed = {for (final id in ids) id: 0};
  for (final expense in room.expenses) {
    if (!ids.contains(expense.payerId)) {
      throw StateError('결제자가 방에 없습니다.');
    }
    for (final item in expense.items) {
      if (item.amount <= 0 ||
          item.memberIds.isEmpty ||
          item.memberIds.toSet().length != item.memberIds.length ||
          item.memberIds.any((id) => !ids.contains(id))) {
        throw StateError('메뉴의 금액이나 부담자를 확인해주세요.');
      }
      paid[expense.payerId] = paid[expense.payerId]! + item.amount;
      final each = item.amount ~/ item.memberIds.length;
      for (final id in item.memberIds) {
        owed[id] = owed[id]! + each;
      }
      if (item.remainder != 0) {
        if (item.remainderMemberId == null ||
            !item.memberIds.contains(item.remainderMemberId)) {
          throw StateError('남은 잔돈의 부담자를 선택해주세요.');
        }
        final id = item.remainderMemberId!;
        owed[id] = owed[id]! + item.remainder;
      }
    }
  }
  final balance = {for (final id in ids) id: paid[id]! - owed[id]!};
  if (balance.values.fold(0, (a, b) => a + b) != 0) {
    throw StateError('정산 합계가 맞지 않습니다.');
  }
  final debtors = balance.entries
      .where((e) => e.value < 0)
      .map((e) => (id: e.key, left: -e.value))
      .toList();
  final creditors = balance.entries
      .where((e) => e.value > 0)
      .map((e) => (id: e.key, left: e.value))
      .toList();
  final transfers = <Transfer>[];
  var di = 0;
  var ci = 0;
  while (di < debtors.length && ci < creditors.length) {
    final amount = debtors[di].left < creditors[ci].left
        ? debtors[di].left
        : creditors[ci].left;
    transfers.add(Transfer(debtors[di].id, creditors[ci].id, amount));
    debtors[di] = (id: debtors[di].id, left: debtors[di].left - amount);
    creditors[ci] = (id: creditors[ci].id, left: creditors[ci].left - amount);
    if (debtors[di].left == 0) di++;
    if (creditors[ci].left == 0) ci++;
  }
  return Settlement(
    paid: paid,
    owed: owed,
    balance: balance,
    transfers: transfers,
  );
}
