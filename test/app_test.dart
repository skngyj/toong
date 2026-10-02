import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toong/app.dart';
import 'package:toong/data/room_store.dart';

void main() {
  testWidgets('시작 화면과 게스트 주의 안내가 보인다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(ToongApp(store: LocalRoomStore()));
    expect(find.text('복잡한 정산,\n퉁으로 끝.'), findsOneWidget);
    expect(find.text('새방 만들기'), findsOneWidget);
    expect(find.text('방 코드로 입장'), findsOneWidget);
    expect(find.text('참여중인 방 목록'), findsOneWidget);
    await tester.tap(find.text('새방 만들기'));
    await tester.pumpAndSettle();
    expect(find.text('게스트 이용 안내'), findsOneWidget);
    expect(find.textContaining('기기를 바꾸면'), findsOneWidget);
    await tester.tap(find.text('확인했어요'));
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsNWidgets(2));
  });

  testWidgets('방 생성부터 수동 지출 정산까지 진행된다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(ToongApp(store: LocalRoomStore()));
    await tester.tap(find.text('새방 만들기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('확인했어요'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), '저녁 모임');
    await tester.enterText(find.byType(TextFormField).at(1), '민수');
    await tester.tap(find.text('방 만들기'));
    await tester.pumpAndSettle();
    expect(find.text('저녁 모임'), findsOneWidget);
    await tester.tap(find.text('지출 추가'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '음식점');
    await tester.enterText(find.byType(TextField).at(1), '김치찌개');
    await tester.enterText(find.byType(TextField).at(2), '10000');
    await tester.tap(find.text('민수').last);
    await tester.scrollUntilVisible(
      find.text('저장하고 방으로'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('저장하고 방으로'));
    await tester.pumpAndSettle();
    expect(find.text('10,000원'), findsWidgets);
    await tester.drag(find.byType(ListView).last, const Offset(0, -260));
    await tester.pumpAndSettle();
    await tester.tap(find.text('정산 결과 보기'));
    await tester.pumpAndSettle();
    expect(find.text('주고받을 돈이 없어요. 이미 셈셈!'), findsOneWidget);
  });
}
