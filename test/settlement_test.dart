import 'package:flutter_test/flutter_test.dart';
import 'package:toong/domain/models.dart';
import 'package:toong/domain/settlement.dart';

Room sampleRoom({int karaoke = 30000, String? remainderWinner}) {
  return Room(
    id: 'room',
    code: 'ABC2345',
    name: '모임',
    ownerMemberId: 'a',
    version: 0,
    members: const [
      Member(id: 'a', name: 'A'),
      Member(id: 'b', name: 'B'),
      Member(id: 'c', name: 'C'),
    ],
    expenses: [
      const Expense(
        id: 'food',
        title: '음식점',
        payerId: 'a',
        items: [
          LineItem(id: 'a-food', name: 'A 음식', amount: 25000, memberIds: ['a']),
          LineItem(id: 'b-food', name: 'B 음식', amount: 20000, memberIds: ['b']),
          LineItem(id: 'c-food', name: 'C 음식', amount: 15000, memberIds: ['c']),
        ],
      ),
      Expense(
        id: 'karaoke',
        title: '노래방',
        payerId: 'b',
        items: [
          LineItem(
            id: 'shared',
            name: '이용료',
            amount: karaoke,
            memberIds: const ['a', 'b', 'c'],
            remainderMemberId: remainderWinner,
          ),
        ],
      ),
    ],
  );
}

void main() {
  test('여러 결제자를 상계해 한 번의 송금만 안내한다', () {
    final result = calculateSettlement(sampleRoom());
    expect(result.paid, {'a': 60000, 'b': 30000, 'c': 0});
    expect(result.owed, {'a': 35000, 'b': 30000, 'c': 25000});
    expect(result.transfers.length, 1);
    expect(result.transfers.single.from, 'c');
    expect(result.transfers.single.to, 'a');
    expect(result.transfers.single.amount, 25000);
  });

  test('잔돈 부담자를 지정하기 전에는 최종 정산을 막는다', () {
    final room = sampleRoom(karaoke: 10001);
    expect(room.pendingRemainder, 2);
    expect(() => calculateSettlement(room), throwsStateError);
  });

  test('잔돈 2원은 선택한 한 사람에게 전부 더하고 합계가 보존된다', () {
    final room = sampleRoom(karaoke: 10001, remainderWinner: 'b');
    final result = calculateSettlement(room);
    expect(room.pendingRemainder, 0);
    expect(result.owed, {'a': 28333, 'b': 23335, 'c': 18333});
    expect(result.owed.values.reduce((a, b) => a + b), 70001);
    expect(result.balance.values.reduce((a, b) => a + b), 0);
  });

  test('새로 들어온 사람은 기존 항목에 자동 포함되지 않는다', () {
    final old = sampleRoom(karaoke: 10001, remainderWinner: 'b');
    final newRoom = old.copyWith(
      members: [
        ...old.members,
        const Member(id: 'd', name: 'D'),
      ],
    );
    expect(newRoom.expenses.last.items.single.memberIds, ['a', 'b', 'c']);
    expect(calculateSettlement(newRoom).owed['d'], 0);
  });
}
