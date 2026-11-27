import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toong/app.dart';
import 'package:toong/data/receipt_scanner.dart';
import 'package:toong/data/room_store.dart';
import 'package:toong/domain/receipt.dart';

/// 카페 영수증(쿠폰 할인 2,000원, 총액 28,000원)을 돌려주는 가짜 인식기.
class FakeScanner implements ReceiptScanner {
  FakeScanner(this.result);
  final ScannedReceipt result;
  int calls = 0;

  @override
  Future<ScannedReceipt> scan(
    Uint8List image, {
    String mimeType = 'image/jpeg',
  }) async {
    calls++;
    return result;
  }
}

ScannedReceipt cafe({int? total = 28000}) => ScannedReceipt.fromJson({
  'storeName': '카페 퉁퉁 신촌점',
  'items': [
    {'name': '아이스아메리카노', 'quantity': 3, 'unitPrice': 4500, 'amount': 13500},
    {'name': '카페라떼', 'quantity': 2, 'unitPrice': 5000, 'amount': 10000},
    {'name': '치즈케이크', 'quantity': 1, 'unitPrice': 6500, 'amount': 6500},
  ],
  'discounts': [
    {'name': '쿠폰할인', 'amount': 2000},
  ],
  'total': total,
});

void main() {
  group('영수증 결과 정리', () {
    test('할인을 메뉴 금액 비율로 나눠 빼고 합계를 총액에 맞춘다', () {
      final receipt = cafe();
      expect(receipt.itemsTotal, 30000);
      expect(receipt.netTotal, 28000);
      expect(receipt.difference, 0);
      final lines = receipt.toLines();
      expect(lines.map((l) => l.name), ['아이스아메리카노 ×3', '카페라떼 ×2', '치즈케이크']);
      // 13500·10000·6500에서 900·666·433을 빼고, 남은 1원은 가장 비싼 메뉴에서 뺀다.
      expect(lines.map((l) => l.amount), [12599, 9334, 6067]);
      expect(lines.fold(0, (a, l) => a + l.amount!), 28000);
    });

    test('할인이 메뉴 합보다 크면 반영하지 않고, 총액을 못 읽으면 차이는 null', () {
      final receipt = ScannedReceipt.fromJson({
        'items': [
          {'name': '콜라', 'quantity': 1, 'amount': 2000},
        ],
        'discounts': [
          {'name': '포인트', 'amount': 5000},
        ],
        'total': null,
      });
      expect(receipt.netTotal, 2000);
      expect(receipt.difference, isNull);
      expect(receipt.toLines().single.amount, 2000);
    });

    test('수량 표시를 붙여도 이름은 40자를 넘지 않는다', () {
      final item = ScannedItem(name: '가' * 40, quantity: 12, amount: 1200);
      expect(item.label('').length, 40);
      expect(item.label(''), endsWith(' ×12'));
    });

    test('가려진 이름은 "메뉴 N", 가려진 금액은 비워 두고 할인은 읽은 금액에만 나눈다', () {
      final receipt = ScannedReceipt.fromJson({
        'items': [
          {'name': null, 'quantity': 1, 'amount': 6000},
          {'name': '떡볶이', 'quantity': 1, 'amount': null},
          {'name': '', 'quantity': 2, 'amount': 4000},
        ],
        'discounts': [
          {'name': '쿠폰', 'amount': 1000},
        ],
        'total': null,
      });
      expect(receipt.hiddenCount, 3);
      final lines = receipt.toLines();
      expect(lines.map((l) => l.name), ['메뉴 1', '떡볶이', '메뉴 2 ×2']);
      expect(lines.map((l) => l.amount), [5400, null, 3600]);
      expect(lines.map((l) => (l.nameHidden, l.amountHidden)), [
        (true, false),
        (false, true),
        (true, false),
      ]);
      // 총액을 못 읽었으면 가려진 금액을 계산하지 않는다.
      expect(receipt.withGuessedAmount().items[1].amount, isNull);
    });

    test('금액이 하나만 가려졌으면 영수증 총액으로 계산해 채운다', () {
      ScannedReceipt receipt(int? total, List<int?> amounts) =>
          ScannedReceipt.fromJson({
            'items': [
              for (final (i, a) in amounts.indexed)
                {'name': '메뉴$i', 'quantity': 1, 'amount': a},
            ],
            'discounts': [
              {'name': '쿠폰', 'amount': 1000},
            ],
            'total': total,
          });
      // 총액 14,000 + 할인 1,000 − 읽은 메뉴 6,000 = 9,000
      final guessed = receipt(14000, [6000, null]).withGuessedAmount();
      expect(guessed.items[1].amount, 9000);
      expect(guessed.items[1].amountGuessed, isTrue);
      final lines = guessed.toLines();
      expect(lines[1].amountGuessed, isTrue);
      expect(lines.fold(0, (a, l) => a + l.amount!), 14000);
      // 두 개 이상 가려졌거나 계산이 1원 미만이면 그대로 둔다.
      expect(
        receipt(14000, [6000, null, null]).withGuessedAmount().items[1].amount,
        isNull,
      );
      expect(
        receipt(5000, [6000, null]).withGuessedAmount().items[1].amount,
        isNull,
      );
    });
  });

  testWidgets('체험 모드에서는 영수증 버튼이 보이지 않는다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = LocalRoomStore();
    final room = await store.createRoom('모임', '민수');
    await tester.pumpWidget(
      MaterialApp(
        home: ExpensePage(store: store, room: room),
      ),
    );
    expect(find.text('영수증 촬영'), findsNothing);
    expect(find.text('메뉴와 금액을 직접 입력해주세요.'), findsOneWidget);
  });

  testWidgets('영수증 사진을 고르면 항목이 채워지고 그대로 저장된다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final scanner = FakeScanner(cafe());
    final store = LocalRoomStore(receiptScanner: scanner);
    final room = await store.createRoom('모임', '민수');
    ImageSource? asked;
    pickReceiptPhoto = (source) async {
      asked = source;
      return (bytes: Uint8List(4), mimeType: 'image/jpeg');
    };
    await tester.pumpWidget(
      MaterialApp(
        home: ExpensePage(store: store, room: room),
      ),
    );
    expect(find.text('영수증 촬영'), findsOneWidget);

    await tester.tap(find.text('사진 선택'));
    await tester.pumpAndSettle();
    expect(asked, ImageSource.gallery);
    expect(scanner.calls, 1);
    expect(find.text('영수증에서 메뉴 3개를 읽었어요.'), findsOneWidget);
    expect(find.textContaining('할인 2,000원(쿠폰할인)'), findsOneWidget);
    expect(find.text('항목 합계가 영수증 총액 28,000원과 같아요.'), findsOneWidget);
    expect(find.widgetWithText(TextField, '카페 퉁퉁 신촌점'), findsOneWidget);
    expect(find.widgetWithText(TextField, '아이스아메리카노 ×3'), findsOneWidget);
    expect(find.widgetWithText(TextField, '12599'), findsOneWidget);

    // 금액을 고치면 총액과의 차이를 바로 보여준다.
    await tester.enterText(find.widgetWithText(TextField, '12599'), '13599');
    await tester.pump();
    expect(find.textContaining('28,000원보다 1,000원 많아요'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, '13599'), '12599');
    await tester.pump();

    await tester.ensureVisible(find.text('모든 항목에 모두 선택'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('모든 항목에 모두 선택'));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('저장하고 방으로'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('저장하고 방으로'));
    await tester.pumpAndSettle();
    final saved = await store.getRoom(room.id);
    expect(saved.expenses.single.title, '카페 퉁퉁 신촌점');
    expect(saved.total, 28000);
    expect(
      saved.expenses.single.items.every((i) => i.memberIds.length == 1),
      isTrue,
    );
  });

  testWidgets('이미 입력한 항목이 있으면 바꿀지 먼저 묻는다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final scanner = FakeScanner(cafe(total: null));
    final store = LocalRoomStore(receiptScanner: scanner);
    final room = await store.createRoom('모임', '민수');
    pickReceiptPhoto = (_) async =>
        (bytes: Uint8List(4), mimeType: 'image/jpeg');
    await tester.pumpWidget(
      MaterialApp(
        home: ExpensePage(store: store, room: room),
      ),
    );
    await tester.enterText(find.byType(TextField).at(1), '떡볶이');
    await tester.tap(find.text('영수증 촬영'));
    await tester.pumpAndSettle();
    expect(find.text('입력한 항목을 바꿀까요?'), findsOneWidget);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(scanner.calls, 0);
    expect(find.widgetWithText(TextField, '떡볶이'), findsOneWidget);

    await tester.tap(find.text('영수증 촬영'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();
    expect(scanner.calls, 1);
    expect(find.widgetWithText(TextField, '떡볶이'), findsNothing);
    expect(find.text('영수증 총액을 읽지 못했어요. 금액을 확인해주세요.'), findsOneWidget);
  });

  testWidgets('가려진 칸은 빨갛게 표시하고, 채우기 전에는 저장할 수 없다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    // 요약과 항목이 한 화면에 모두 보이도록 세로로 긴 화면을 쓴다.
    tester.view.physicalSize = const Size(800, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // 이름이 가려진 6,000원 메뉴와 금액이 가려진 떡볶이. 총액 14,000원으로 떡볶이 8,000원을 계산한다.
    final scanner = FakeScanner(
      ScannedReceipt.fromJson({
        'storeName': '퉁 분식',
        'items': [
          {'name': null, 'quantity': 1, 'amount': 6000},
          {'name': '떡볶이', 'quantity': 1, 'amount': null},
        ],
        'discounts': [],
        'total': 14000,
      }),
    );
    final store = LocalRoomStore(receiptScanner: scanner);
    final room = await store.createRoom('모임', '민수');
    pickReceiptPhoto = (_) async =>
        (bytes: Uint8List(4), mimeType: 'image/jpeg');
    await tester.pumpWidget(
      MaterialApp(
        home: ExpensePage(store: store, room: room),
      ),
    );
    await tester.tap(find.text('사진 선택'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, '메뉴 1'), findsOneWidget);
    expect(find.text('영수증에서 이름이 가려져 있어요. 알아보면 고쳐주세요.'), findsOneWidget);
    expect(find.text('가려져 읽지 못한 칸 1개가 있어요. 빨간 칸을 확인해주세요.'), findsOneWidget);
    // 금액이 하나만 가려져 총액으로 계산해 채운다.
    await tester.scrollUntilVisible(
      find.widgetWithText(TextField, '8000'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('가려진 금액을 영수증 총액으로 계산했어요. 확인해주세요.'), findsOneWidget);

    // 이름을 고치면 빨간 표시가 사라진다.
    await tester.scrollUntilVisible(
      find.widgetWithText(TextField, '메뉴 1'),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(find.widgetWithText(TextField, '메뉴 1'), '김밥');
    await tester.pump();
    expect(find.textContaining('이름이 가려져 있어요'), findsNothing);
    expect(find.textContaining('가려져 읽지 못한 칸'), findsNothing);

    // 금액을 지우면 저장할 수 없다.
    await tester.enterText(find.widgetWithText(TextField, '8000'), '');
    await tester.pump();
    expect(find.textContaining('총액으로 계산했어요'), findsNothing);
    expect(find.textContaining('6,000원 적어요'), findsNothing);
    expect(find.textContaining('8,000원 적어요'), findsOneWidget);
    expect(find.textContaining('가려져서 빠진 메뉴가 있을 수 있어요'), findsOneWidget);

    // 차액을 항목으로 더하면 이름이 빨간 "확인 필요 메뉴"가 생긴다.
    await tester.ensureVisible(find.text('차액 8,000원을 항목으로 추가'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('차액 8,000원을 항목으로 추가'));
    await tester.pump();
    expect(find.widgetWithText(TextField, '확인 필요 메뉴'), findsOneWidget);
    expect(find.text('항목 합계가 영수증 총액 14,000원과 같아요.'), findsOneWidget);

    await tester.ensureVisible(find.text('모든 항목에 모두 선택'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('모든 항목에 모두 선택'));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('저장하고 방으로'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('저장하고 방으로'));
    await tester.pumpAndSettle();
    expect(find.text('각 항목의 이름, 1원 이상 금액, 부담자를 확인해주세요.'), findsOneWidget);
    expect((await store.getRoom(room.id)).expenses, isEmpty);
  });

  testWidgets('메뉴를 하나도 못 읽으면 다시 찍기를 권하고 입력은 그대로 둔다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final scanner = FakeScanner(
      ScannedReceipt.fromJson({'items': [], 'discounts': [], 'total': null}),
    );
    final store = LocalRoomStore(receiptScanner: scanner);
    final room = await store.createRoom('모임', '민수');
    pickReceiptPhoto = (_) async =>
        (bytes: Uint8List(4), mimeType: 'image/jpeg');
    await tester.pumpWidget(
      MaterialApp(
        home: ExpensePage(store: store, room: room),
      ),
    );
    await tester.tap(find.text('영수증 촬영'));
    await tester.pumpAndSettle();
    expect(find.text('메뉴를 읽지 못했어요'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '확인'));
    await tester.pumpAndSettle();
    // 다시 찍기를 고르면 한 번 더 읽는다.
    expect(scanner.calls, 2);
    await tester.tap(find.widgetWithText(FilledButton, '취소'));
    await tester.pumpAndSettle();
    expect(find.text('메뉴를 읽지 못했어요'), findsNothing);
    expect(find.textContaining('영수증에서 메뉴'), findsNothing);
  });
}
