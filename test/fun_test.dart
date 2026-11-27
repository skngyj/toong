import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toong/app.dart';
import 'package:toong/data/room_store.dart';
import 'package:toong/fun.dart';

import 'account_test.dart' show setup;

void main() {
  testWidgets('숫자는 굴러가다 새 값에서 멈추고, 애니메이션 줄이기면 바로 보인다', (tester) async {
    Widget app(int value, {bool calm = false}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: calm),
        child: Scaffold(
          body: RollingNumber(value: value, format: (v) => '$v원'),
        ),
      ),
    );
    await tester.pumpWidget(app(0));
    await tester.pumpWidget(app(10000));
    await tester.pump(const Duration(milliseconds: 100));
    final mid = tester.widget<Text>(find.byType(Text)).data!;
    expect(mid, isNot('10000원'));
    expect(mid, isNot('0원'));
    await tester.pumpAndSettle();
    expect(find.text('10000원'), findsOneWidget);

    await tester.pumpWidget(app(500, calm: true));
    expect(find.text('500원'), findsOneWidget);
  });

  testWidgets('마지막 송금을 체크하면 도장이 찍히고 "정산 끝!" 띠가 나온다', (tester) async {
    final (store, room, _, _) = await setup();
    await tester.pumpWidget(
      MaterialApp(
        home: SettlementPage(store: store, room: room),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('송금\n완료'), findsNothing);
    expect(find.textContaining('정산 끝!'), findsNothing);

    await tester.tap(find.byTooltip('민수 → 지수 송금 완료 표시'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '확인'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    // 찍히는 중에는 도장이 크게 떠 있다.
    expect(find.text('송금\n완료'), findsOneWidget);
    expect(find.byType(ConfettiBurst), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('정산 끝! 모두 퉁 쳤어요 🎉'), findsOneWidget);
    expect(find.text('모든 송금이 끝났어요.'), findsOneWidget);
  });

  testWidgets('빈 화면에는 그림과 안내가 나온다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(home: RoomListPage(store: LocalRoomStore())),
    );
    await tester.pumpAndSettle();
    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text('방을 만들거나 방 코드로 들어가 보세요.'), findsOneWidget);
  });

  testWidgets('시작 로고는 처음 켤 때만 모이는 효과를 보여준다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(ToongApp(store: LocalRoomStore()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.widget<LogoIntro>(find.byType(LogoIntro)).play, isTrue);
    await tester.pumpAndSettle();
    expect(
      (await SharedPreferences.getInstance()).getBool('toong_intro_seen'),
      isTrue,
    );

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(ToongApp(store: LocalRoomStore()));
    await tester.pumpAndSettle();
    expect(tester.widget<LogoIntro>(find.byType(LogoIntro)).play, isFalse);
  });
}
