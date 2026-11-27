import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toong/data/ledger_store.dart';
import 'package:toong/data/subscription_store.dart';
import 'package:toong/domain/bank.dart';
import 'package:toong/domain/subscription.dart';
import 'package:toong/reminders.dart';
import 'package:toong/subscription_page.dart';

class FakeReminders implements Reminders {
  final scheduled = <String>[];
  final cancelled = <String>[];
  final shown = <String>[];
  int asked = 0;
  @override
  Future<bool> requestPermission() async {
    asked++;
    return true;
  }

  @override
  Future<void> schedule(Subscription sub, {DateTime? now}) async =>
      scheduled.add(sub.id);
  @override
  Future<void> cancel(Subscription sub) async => cancelled.add(sub.id);
  @override
  Future<void> showNow(Subscription sub) async => shown.add(sub.id);
}

/// 넷플릭스 17,000원, 매달 31일 오후 9시. 민수(나)가 결제하고 지수·현우와 나눈다.
Subscription netflix({
  String me = 'm1',
  String payer = 'm1',
  Map<String, int>? shares,
  BankAccount? account,
  DateTime? created,
}) => Subscription(
  id: 's1',
  name: '넷플릭스',
  amount: 17000,
  day: 31,
  hour: 21,
  minute: 0,
  members: const [
    SubscriptionMember(id: 'm1', name: '민수'),
    SubscriptionMember(id: 'm2', name: '지수'),
    SubscriptionMember(id: 'm3', name: '현우'),
  ],
  payerId: payer,
  meId: me,
  createdAt: created ?? DateTime(2026, 9, 5),
  shares: shares,
  payerAccount: account,
);

void main() {
  group('정기 구독 계산', () {
    test('결제일이 없는 달은 마지막 날, 윤년 2월도 맞춘다', () {
      expect(billingDate(2026, 2, 31), DateTime(2026, 2, 28));
      expect(billingDate(2028, 2, 31), DateTime(2028, 2, 29));
      expect(billingDate(2026, 4, 31), DateTime(2026, 4, 30));
      expect(billingDate(2026, 5, 31), DateTime(2026, 5, 31));
      final next = upcomingBillings(netflix(), DateTime(2026, 11, 30, 22), 4);
      expect(next, [
        DateTime(2026, 12, 31, 21),
        DateTime(2027, 1, 31, 21),
        DateTime(2027, 2, 28, 21),
        DateTime(2027, 3, 31, 21),
      ]);
      // 결제일 당일 알림 시각 전이면 오늘이 첫 알림이다.
      expect(
        upcomingBillings(netflix(), DateTime(2026, 12, 31, 9), 1).single,
        DateTime(2026, 12, 31, 21),
      );
    });

    test('똑같이 나누면 잔돈은 결제하는 사람이 내고, 직접 정할 수도 있다', () {
      final s = netflix();
      expect(s.shareOf, {'m1': 5668, 'm2': 5666, 'm3': 5666});
      expect(s.senders.map((m) => m.name), ['지수', '현우']);
      final custom = netflix(shares: {'m1': 7000, 'm2': 10000, 'm3': 0});
      expect(custom.senders.map((m) => m.name), ['지수']);
      expect(netflix(me: 'm2').myShare, 5666);
    });

    test('알림과 요청 글', () {
      expect(billingMessage(netflix()).body, '지수·현우 님에게 각 5,666원 받을 차례예요.');
      expect(billingMessage(netflix(me: 'm2')).body, '5,666원을 민수 님에게 보낼 날이에요.');
      expect(reminderMessage(netflix()).title, '내일은 넷플릭스 결제일이에요');
      final s = netflix(
        account: const BankAccount(
          bank: 'kakao',
          number: '3333-01-1234567',
          holder: '김민수',
        ),
      ).markPaid('2026-11', 'm2', true);
      expect(
        requestText(s, DateTime(2026, 11)),
        '[퉁] 11월 넷플릭스 17,000원 정산\n'
        '- 지수 5,666원 (보냄)\n'
        '- 현우 5,666원\n'
        '민수 님에게 보내주세요.\n'
        '카카오뱅크 3333-01-1234567 김민수',
      );
      expect(Subscription.fromJson(s.toJson()).paidIn('2026-11'), {'m1', 'm2'});
    });
  });

  test('지난 결제일마다 내 몫을 가계부에 한 번씩 넣는다', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SubscriptionStore();
    final saved = await store.save(netflix(me: 'm2'));
    expect(saved.notifyBase, 1);
    // 같은 구독을 다시 저장해도 알림 id는 그대로다.
    expect((await store.save(netflix(me: 'm2'))).notifyBase, 1);

    // 9월 5일 등록 → 9월 30일, 10월 31일 두 번.
    expect(await store.importToLedger(now: DateTime(2026, 11, 15)), 2);
    final ledger = LedgerStore();
    final entries = await ledger.list();
    expect(
      entries.map((e) => (e.date, e.amount, e.category, e.title)),
      unorderedEquals([
        (DateTime(2026, 9, 30), 5666, '구독', '넷플릭스'),
        (DateTime(2026, 10, 31), 5666, '구독', '넷플릭스'),
      ]),
    );
    // 다시 해도 늘지 않고, 지운 기록은 다시 생기지 않는다.
    await ledger.remove(entries.first.id);
    expect(await store.importToLedger(now: DateTime(2026, 11, 20)), 0);
    expect(await ledger.list(), hasLength(1));
    expect(await store.importToLedger(now: DateTime(2026, 11, 30)), 1);
  });

  testWidgets('구독을 등록하면 알림을 예약하고, 이번 달 낸 사람을 체크하고 요청 글을 복사한다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fake = FakeReminders();
    final original = reminders;
    reminders = fake;
    addTearDown(() => reminders = original);
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );

    await tester.pumpWidget(const MaterialApp(home: SubscriptionListPage()));
    await tester.pumpAndSettle();
    expect(find.text('아직 등록한 구독이 없어요.'), findsOneWidget);
    await tester.tap(find.text('구독 추가'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, '구독 이름'), '유튜브');
    await tester.enterText(
      find.widgetWithText(TextField, '한 달 금액 (원)'),
      '14900',
    );
    await tester.enterText(find.widgetWithText(TextField, '이름 2'), '지수');
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    final sub = (await SubscriptionStore().list()).single;
    expect(sub.name, '유튜브');
    expect(sub.iAmPayer, isTrue);
    expect(sub.shareOf.values, [7450, 7450]);
    expect(fake.asked, 1);
    expect(fake.scheduled, [sub.id]);
    expect(find.textContaining('유튜브'), findsOneWidget);

    await tester.tap(find.text('유튜브'));
    await tester.pumpAndSettle();
    expect(find.text('지수'), findsOneWidget);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    expect(find.text('7,450원 · 보냄'), findsOneWidget);
    await tester.tap(find.text('요청 글 복사'));
    await tester.pumpAndSettle();
    expect(copied.single, contains('- 지수 7,450원 (보냄)'));
    await tester.tap(find.text('알림 미리 보기'));
    await tester.pumpAndSettle();
    expect(fake.shown, [sub.id]);

    // 지우면 알림도 지운다.
    await tester.tap(find.byTooltip('구독 지우기'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '확인'));
    await tester.pumpAndSettle();
    expect(fake.cancelled, [sub.id]);
    expect(await SubscriptionStore().list(), isEmpty);
  });

  testWidgets('금액을 직접 정하면 합이 맞아야 저장된다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final original = reminders;
    reminders = FakeReminders();
    addTearDown(() => reminders = original);
    await tester.pumpWidget(const MaterialApp(home: SubscriptionEditPage()));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '구독 이름'), '멜론');
    await tester.enterText(
      find.widgetWithText(TextField, '한 달 금액 (원)'),
      '10000',
    );
    await tester.enterText(find.widgetWithText(TextField, '이름 2'), '지수');
    await tester.tap(find.text('사람마다 금액 직접 정하기'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '금액').at(0), '3000');
    await tester.enterText(find.widgetWithText(TextField, '금액').at(1), '6000');
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('합(9,000원)이 한 달 금액(10,000원)과 달라요'),
      findsOneWidget,
    );
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '금액').at(1), '7000');
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect((await SubscriptionStore().list()).single.shareOf.values, [
      3000,
      7000,
    ]);
  });

  testWidgets('나눠 내는 사람은 결제하는 사람 계좌로 송금하기를 쓴다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await SubscriptionStore().save(
      netflix(
        me: 'm2',
        account: const BankAccount(
          bank: 'kakao',
          number: '3333-01-1234567',
          holder: '김민수',
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SubscriptionDetailPage(id: 's1', now: DateTime(2026, 11, 30, 22)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('11월 정산'), findsOneWidget);
    expect(find.text('지수 (나)'), findsOneWidget);
    expect(find.text('5,666원 송금하기'), findsOneWidget);
    await tester.tap(find.text('5,666원 송금하기'));
    await tester.pumpAndSettle();
    expect(find.text('민수 님에게 5,666원 보내기'), findsOneWidget);
  });
}
