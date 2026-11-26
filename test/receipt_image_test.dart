import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toong/app.dart';
import 'package:toong/domain/models.dart';
import 'package:toong/domain/record.dart';
import 'package:toong/receipt_view.dart';

Room completed() {
  const ms = [
    Member(id: 'a', name: '민수', actorId: 'x'),
    Member(id: 'b', name: '지수'),
  ];
  return Room(
    id: 'r',
    code: 'ABC2345',
    name: '금요일 모임!',
    ownerMemberId: 'a',
    members: ms,
    version: 2,
    lastActivityAt: DateTime(2026, 11, 26, 21),
    completedAt: DateTime(2026, 11, 26, 21, 40),
    expenses: const [
      Expense(
        id: 'e1',
        title: '고깃집',
        payerId: 'a',
        items: [
          LineItem(id: 'i1', name: '삼겹살', amount: 20000, memberIds: ['a', 'b']),
        ],
      ),
    ],
  );
}

void main() {
  test('사진 파일 이름은 방 이름의 기호를 빼고 날짜를 붙인다', () {
    expect(
      receiptFileName('금요일 모임!', DateTime(2026, 11, 26, 21, 40)),
      '퉁_금요일모임_20261126',
    );
    expect(receiptFileName('!!!', DateTime(2026, 1, 2)), '퉁_정산_20260102');
  });

  testWidgets('정산 기록의 영수증을 이미지로 찍어 사진 앱에 저장한다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final saved = <(Uint8List, String)>[];
    saveImageToGallery = (png, name) async => saved.add((png, name));
    await tester.pumpWidget(
      MaterialApp(
        home: RecordPage(record: SettlementRecord.fromRoom(completed())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('퉁 정산서'), findsOneWidget);
    expect(find.text('지수 → 민수'), findsOneWidget);

    await tester.ensureVisible(find.text('영수증 이미지 저장'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('영수증 이미지 저장'));
      // 캡처와 저장이 끝날 때까지 기다린다.
      for (var i = 0; i < 50 && saved.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pumpAndSettle();
    expect(saved, hasLength(1));
    final (png, name) = saved.single;
    expect(name, '퉁_금요일모임_20261126');
    // PNG 파일 머리(89 50 4E 47)
    expect(png.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    expect(find.text('영수증 이미지를 사진 앱에 저장했어요.'), findsOneWidget);
  });

  testWidgets('저장에 실패하면 이유를 알려준다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    saveImageToGallery = (png, name) async =>
        throw StateError('사진 앱 접근을 허용해야 영수증 이미지를 저장할 수 있어요.');
    await tester.pumpWidget(
      MaterialApp(
        home: RecordPage(record: SettlementRecord.fromRoom(completed())),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('영수증 이미지 저장'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('영수증 이미지 저장'));
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pumpAndSettle();
    expect(find.text('사진 앱 접근을 허용해야 영수증 이미지를 저장할 수 있어요.'), findsOneWidget);
  });
}
