import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toong/data/room_store.dart';
import 'package:toong/domain/models.dart';
import 'package:toong/domain/settlement.dart';

void main() {
  test('기존 참여자가 새 방으로 정산을 복제하고 과거 금액을 유지한다', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = LocalRoomStore();
    final original = await store.createRoom('모임', '민수');
    await prefs.setString('toong_actor_id', 'friend-actor');
    final joined = await store.joinRoom(original.code, '지수');
    final friend = joined.actorMember('friend-actor')!;
    await prefs.setString('toong_actor_id', original.members.single.actorId!);
    final withExpense = await store.saveRoom(
      joined.copyWith(
        expenses: [
          Expense(
            id: 'meal',
            title: '식사',
            payerId: original.ownerMemberId,
            items: [
              LineItem(
                id: 'menu',
                name: '메뉴',
                amount: 20000,
                memberIds: [original.ownerMemberId, friend.id],
              ),
            ],
          ),
        ],
      ),
    );
    await prefs.setString('toong_actor_id', 'friend-actor');
    final cloned = await store.cloneRoom(withExpense);
    expect(cloned.ownerMemberId, friend.id);
    expect(cloned.sourceRoomId, original.id);
    expect(cloned.code, isNot(original.code));
    expect(cloned.members.first.actorId, isNull);
    expect(cloned.total, 20000);
    expect(calculateSettlement(cloned).transfers.single.amount, 10000);
    expect(
      (await store.getRoom(original.id)).ownerMemberId,
      original.ownerMemberId,
    );
  });
}
