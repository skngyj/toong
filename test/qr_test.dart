import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toong/app.dart';
import 'package:toong/data/room_store.dart';
import 'package:toong/qr_page.dart';

void main() {
  group('QR에서 방 코드 꺼내기', () {
    test('방 링크와 코드만 적힌 QR을 읽는다', () {
      expect(codeFromQr('toong://join/ABC2345'), 'ABC2345');
      expect(codeFromQr('  toong://join/abc2345 '), 'ABC2345');
      expect(codeFromQr('abc2345'), 'ABC2345');
    });

    test('퉁 방 QR이 아니면 null', () {
      expect(codeFromQr(null), isNull);
      expect(codeFromQr(''), isNull);
      expect(codeFromQr('https://example.com/join/ABC2345'), isNull);
      expect(codeFromQr('toong://room/ABC2345'), isNull);
      expect(codeFromQr('안녕하세요'), isNull);
      expect(codeFromQr('ABC-2345'), isNull);
    });
  });

  testWidgets('방 화면에서 입장 QR을 띄우고, 얼린 방에서는 숨긴다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = LocalRoomStore();
    final room = await store.createRoom('저녁 모임', '민수');
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
    await tester.pumpWidget(
      MaterialApp(
        home: RoomPage(store: store, roomId: room.id),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('입장 QR 보기'));
    await tester.pumpAndSettle();
    final qr = tester.widget<QrImageView>(find.byType(QrImageView));
    expect(qr.semanticsLabel, '저녁 모임 방 입장 QR');
    expect(find.text(room.code), findsWidgets);
    await tester.ensureVisible(find.text('코드 복사'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('코드 복사'));
    await tester.pumpAndSettle();
    expect(copied, [room.code]);
    expect(find.text('방 코드를 복사했어요.'), findsOneWidget);

    await store.freezeRoom(await store.getRoom(room.id));
    await tester.pumpWidget(
      MaterialApp(
        key: UniqueKey(),
        home: RoomPage(store: store, roomId: room.id),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('입장 QR 보기'), findsNothing);
  });

  testWidgets('QR을 찍으면 방 코드가 채워지고 닉네임만 넣어 입장한다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = LocalRoomStore();
    final room = await store.createRoom('저녁 모임', '민수');
    final original = scanRoomQr;
    addTearDown(() => scanRoomQr = original);
    String? next = room.code;
    scanRoomQr = (_) async => next;

    await tester.pumpWidget(ToongApp(store: store));
    await tester.tap(find.text('방 코드로 입장'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();

    // 취소하면 아무것도 바뀌지 않는다.
    next = null;
    await tester.tap(find.byTooltip('QR 스캔'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).at(0))
          .controller!
          .text,
      isEmpty,
    );

    next = room.code;
    await tester.tap(find.byTooltip('QR 스캔'));
    await tester.pumpAndSettle();
    expect(find.text(room.code), findsOneWidget);
    expect(find.textContaining('QR에서 방 코드 ${room.code}를 읽었어요'), findsOneWidget);
    // 바로 들어가지 않고 입장 화면에 머문다.
    expect(find.text('입장하기'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).at(1), '지수');
    await tester.tap(find.text('입장하기'));
    await tester.pumpAndSettle();
    expect(find.text('저녁 모임'), findsWidgets);
  });
}
