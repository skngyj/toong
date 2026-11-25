import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toong/app.dart';
import 'package:toong/data/ledger_store.dart';
import 'package:toong/data/room_store.dart';
import 'package:toong/domain/ledger.dart';
import 'package:toong/domain/models.dart';
import 'package:toong/ledger_page.dart';

/// 민수(나, 방장)·지수 두 명의 완료된 방.
/// 고깃집 60,001원은 민수가 결제하고 둘이 나눔(잔돈 1원은 민수), 카페 9,000원은 지수가
/// 결제하고 지수 혼자 먹음. 민수의 몫은 고깃집 30,001원뿐이다.
Room completedRoom() {
  const me = Member(id: 'm1', name: '민수', actorId: 'me');
  const friend = Member(id: 'm2', name: '지수', actorId: 'friend');
  return Room(
    id: 'room-1',
    code: 'ABC2345',
    name: '금요일 모임',
    ownerMemberId: 'm1',
    members: const [me, friend],
    expenses: const [
      Expense(
        id: 'e1',
        title: '고깃집 신촌점',
        payerId: 'm1',
        items: [
          LineItem(
            id: 'i1',
            name: '삼겹살',
            amount: 60001,
            memberIds: ['m1', 'm2'],
            remainderMemberId: 'm1',
          ),
        ],
      ),
      Expense(
        id: 'e2',
        title: '스타벅스',
        payerId: 'm2',
        items: [
          LineItem(id: 'i2', name: '라떼', amount: 9000, memberIds: ['m2']),
        ],
      ),
    ],
    version: 3,
    lastActivityAt: DateTime.utc(2026, 11, 20, 12),
    completedAt: DateTime.utc(2026, 11, 20, 13),
  );
}

void main() {
  group('가계부 계산', () {
    test('지출 한 건당 내가 실제로 부담한 금액만 한 줄로 만든다', () {
      final entries = entriesFromRoom(completedRoom(), 'm1');
      expect(entries, hasLength(1));
      expect(entries.single.title, '고깃집 신촌점');
      expect(entries.single.amount, 30001);
      expect(entries.single.category, '식비');
      expect(entries.single.roomName, '금요일 모임');

      final friend = entriesFromRoom(completedRoom(), 'm2');
      expect(friend.map((e) => (e.title, e.amount, e.category)), [
        ('고깃집 신촌점', 30000, '식비'),
        ('스타벅스', 9000, '카페'),
      ]);
    });

    test('제목으로 분류를 추정하고, 모르면 기타', () {
      expect(guessCategory('코인노래방'), '놀거리');
      expect(guessCategory('카카오T 택시'), '교통');
      expect(guessCategory('이자카야 2차'), '술자리');
      expect(guessCategory('다이소'), '쇼핑');
      expect(guessCategory('회비'), '기타');
    });

    test('예산 단계는 80% 미만, 80% 이상, 100% 이상', () {
      expect(budgetLevel(79999, 100000), 0);
      expect(budgetLevel(80000, 100000), 80);
      expect(budgetLevel(100000, 100000), 100);
      expect(budgetLevel(500000, null), 0);
    });
  });

  group('가계부 저장', () {
    test('정산 기록은 방마다 한 번만 넣고, 지운 기록은 다시 생기지 않는다', () async {
      SharedPreferences.setMockInitialValues({});
      final store = LedgerStore();
      expect(await store.importRoom(completedRoom(), 'me'), isTrue);
      expect(await store.importRoom(completedRoom(), 'me'), isFalse);
      final entries = await store.list();
      expect(entries.single.amount, 30001);

      await store.remove(entries.single.id);
      expect(await store.importRoom(completedRoom(), 'me'), isFalse);
      expect(await store.list(), isEmpty);
    });

    test('완료되지 않은 방이나 내가 없는 방은 넣지 않는다', () async {
      SharedPreferences.setMockInitialValues({});
      final store = LedgerStore();
      final open = completedRoom().copyWith();
      expect(
        await store.importRoom(
          Room.fromJson({...open.toJson(), 'completed_at': null}),
          'me',
        ),
        isFalse,
      );
      expect(await store.importRoom(completedRoom(), 'stranger'), isFalse);
    });

    test('예산 알림은 같은 달 같은 단계에서 한 번만 나온다', () async {
      SharedPreferences.setMockInitialValues({});
      final store = LedgerStore();
      final now = DateTime(2026, 11, 25);
      await store.setBudget(100000);
      Future<void> spend(int amount) => store.put(
        LedgerEntry(
          id: newId(),
          date: now,
          title: '지출',
          amount: amount,
          category: '기타',
        ),
      );

      await spend(50000);
      expect(await store.budgetAlert(now: now), isNull);
      await spend(35000);
      expect(await store.budgetAlert(now: now), contains('예산의 85%'));
      expect(await store.budgetAlert(now: now), isNull);
      await spend(20000);
      expect(await store.budgetAlert(now: now), contains('예산 100,000원을 넘었어요'));
      expect(await store.budgetAlert(now: now), isNull);
      // 다음 달은 새로 센다.
      expect(await store.budgetAlert(now: DateTime(2026, 12, 2)), isNull);
    });
  });

  testWidgets('정산을 완료하면 내 부담액이 가계부에 들어간다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = LocalRoomStore();
    await tester.pumpWidget(ToongApp(store: store));
    await tester.tap(find.text('새방 만들기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), '저녁 모임');
    await tester.enterText(find.byType(TextFormField).at(1), '민수');
    await tester.tap(find.text('방 만들기'));
    await tester.pumpAndSettle();
    final room = (await store.listRooms()).single;
    final me = room.members.single.id;
    await store.saveRoom(
      room.copyWith(
        expenses: [
          Expense(
            id: 'e1',
            title: '김밥천국',
            payerId: me,
            items: [
              LineItem(id: 'i1', name: '김밥', amount: 4000, memberIds: [me]),
            ],
          ),
        ],
      ),
    );
    await store.completeRoom(await store.getRoom(room.id));

    // 방 화면으로 돌아가 다시 불러오면 기록과 가계부가 저장된다.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('참여중인 방 목록'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('내 가계부'));
    await tester.pumpAndSettle();
    expect(find.text('김밥천국'), findsOneWidget);
    expect(find.textContaining('식비 · 저녁 모임'), findsOneWidget);
    expect(find.text('4,000원'), findsWidgets);

    // 정산에서 온 기록은 원래 정산 기록으로 이동할 수 있다.
    await tester.tap(find.text('김밥천국'));
    await tester.pumpAndSettle();
    expect(find.text('저녁 모임 정산에서 온 기록'), findsOneWidget);
    await tester.tap(find.text('정산 기록 보기'));
    await tester.pumpAndSettle();
    expect(find.textContaining('[퉁 정산 기록] 저녁 모임'), findsOneWidget);
  });

  testWidgets('직접 기록하고 예산의 80%를 넘으면 알려준다', (tester) async {
    SharedPreferences.setMockInitialValues({'toong_budget': 10000});
    final now = DateTime.now();
    await tester.pumpWidget(const MaterialApp(home: LedgerPage()));
    await tester.pumpAndSettle();
    expect(find.text('${now.year}년 ${now.month}월'), findsOneWidget);
    expect(find.textContaining('예산 10,000원 중 0% 썼어요'), findsOneWidget);

    await tester.tap(find.text('직접 기록'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '택시');
    await tester.enterText(find.byType(TextField).at(1), '8500');
    await tester.tap(find.widgetWithText(ChoiceChip, '교통'));
    await tester.pump();
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    expect(find.text('예산 알림'), findsOneWidget);
    expect(find.textContaining('이번 달 예산의 85%를 썼어요'), findsOneWidget);
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();
    expect(find.text('택시'), findsOneWidget);
    expect(find.textContaining('교통'), findsWidgets);
    expect(find.textContaining('예산 10,000원 중 85% 썼어요'), findsOneWidget);
  });
}
