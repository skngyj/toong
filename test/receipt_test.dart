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
  ScanMode? lastMode;

  @override
  Future<ScannedReceipt> scan(
    Uint8List image, {
    String mimeType = 'image/jpeg',
    ScanMode mode = ScanMode.receipt,
  }) async {
    calls++;
    lastMode = mode;
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
      expect(lines.fold(0, (a, l) => a + l.amount), 28000);
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
      expect(item.label.length, 40);
      expect(item.label, endsWith(' ×12'));
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

  test('메뉴판에서 고른 수량으로 주문 항목을 만든다', () {
    final menu = ScannedReceipt.fromJson({
      'storeName': '분식 퉁퉁',
      'items': [
        {'name': '떡볶이', 'quantity': 1, 'unitPrice': 5000, 'amount': 5000},
        {'name': '김밥', 'quantity': 1, 'unitPrice': 3000, 'amount': 3000},
        {'name': '라면', 'quantity': 1, 'unitPrice': 4000, 'amount': 4000},
      ],
    });
    final order = menu.order([2, 0, 1], paid: 14500);
    expect(order.storeName, '분식 퉁퉁');
    expect(order.toLines().map((l) => l.name), ['떡볶이 ×2', '라면']);
    expect(order.toLines().map((l) => l.amount), [10000, 4000]);
    expect(order.total, 14500);
    expect(order.difference, 500);
  });

  testWidgets('메뉴판을 찍으면 주문한 메뉴와 수량을 골라 항목을 채운다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final scanner = FakeScanner(
      ScannedReceipt.fromJson({
        'storeName': '분식 퉁퉁',
        'items': [
          {'name': '떡볶이', 'quantity': 1, 'unitPrice': 5000, 'amount': 5000},
          {'name': '김밥', 'quantity': 1, 'unitPrice': 3000, 'amount': 3000},
        ],
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
    await tester.tap(find.text('메뉴판'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('메뉴판 촬영'));
    await tester.pumpAndSettle();
    expect(scanner.lastMode, ScanMode.menu);
    expect(find.text('주문한 메뉴 고르기'), findsOneWidget);

    // 고른 메뉴가 없으면 확인을 누를 수 없다.
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '확인'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byTooltip('떡볶이 더하기'));
    await tester.tap(find.byTooltip('떡볶이 더하기'));
    await tester.tap(find.byTooltip('김밥 더하기'));
    await tester.pump();
    expect(find.text('고른 메뉴 2개 · 메뉴판 가격 합계 13,000원'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '12,000');
    await tester.ensureVisible(find.widgetWithText(FilledButton, '확인'));
    await tester.tap(find.widgetWithText(FilledButton, '확인'));
    await tester.pumpAndSettle();

    expect(find.text('메뉴판에서 고른 메뉴 2개를 넣었어요.'), findsOneWidget);
    expect(find.widgetWithText(TextField, '분식 퉁퉁'), findsOneWidget);
    expect(find.widgetWithText(TextField, '떡볶이 ×2'), findsOneWidget);
    expect(find.widgetWithText(TextField, '10000'), findsOneWidget);
    expect(find.textContaining('실제 결제액 12,000원보다 1,000원 많아요'), findsOneWidget);
  });
}
