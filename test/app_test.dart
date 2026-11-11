import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toong/app.dart';
import 'package:toong/data/room_store.dart';
import 'package:toong/domain/models.dart';

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
    expect(find.textContaining('48시간 동안 입력이 없으면'), findsOneWidget);
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
    expect(find.text('삭제까지 1일 23시간'), findsOneWidget);
    expect(find.textContaining('48시간 동안 입력이 없으면'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('지출 추가'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
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
    await tester.scrollUntilVisible(
      find.text('정산 결과 보기'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('정산 결과 보기'));
    await tester.pumpAndSettle();
    expect(find.text('주고받을 돈이 없어요. 이미 셈셈!'), findsOneWidget);
  });

  /// 방을 만들고 10,000원 지출 하나를 넣은 방 화면까지 간다.
  Future<void> roomWithExpense(WidgetTester tester) async {
    await tester.tap(find.text('새방 만들기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('확인했어요'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), '저녁 모임');
    await tester.enterText(find.byType(TextFormField).at(1), '민수');
    await tester.tap(find.text('방 만들기'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('지출 추가'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
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
  }

  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('방장이 방을 연장하고 얼렸다 녹일 수 있다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(ToongApp(store: LocalRoomStore()));
    await roomWithExpense(tester);
    await tester.drag(find.byType(ListView).last, const Offset(0, 2000));
    await tester.pumpAndSettle();

    await tester.tap(find.text('연장 (3회 남음)'));
    await tester.pumpAndSettle();
    expect(find.text('연장 (2회 남음)'), findsOneWidget);

    await tester.tap(find.text('얼리기'));
    await tester.pumpAndSettle();
    expect(find.text('방을 얼릴까요?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '얼리기'));
    await tester.pumpAndSettle();
    expect(find.textContaining('얼린 방 · 삭제까지'), findsOneWidget);
    expect(find.text('지출 추가'), findsNothing);
    expect(find.text('정산 완료'), findsNothing);

    await tester.tap(find.text('녹이기'));
    await tester.pumpAndSettle();
    expect(find.textContaining('얼린 방'), findsNothing);
    expect(find.text('연장 (2회 남음)'), findsOneWidget);
  });

  testWidgets('정산을 완료하면 기록이 기기에 남고 목록에서 볼 수 있다', (tester) async {
    SharedPreferences.setMockInitialValues({});
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
    await tester.pumpWidget(ToongApp(store: LocalRoomStore()));
    await roomWithExpense(tester);

    await scrollTo(tester, find.text('정산 완료'));
    await tester.tap(find.text('정산 완료'));
    await tester.pumpAndSettle();
    expect(find.text('정산을 완료할까요?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '정산 완료'));
    await tester.pumpAndSettle();
    expect(find.text('지출 추가'), findsNothing);
    expect(find.text('정산 기록 보기'), findsOneWidget);

    // 홈으로 돌아가 목록을 열면 완료된 방은 기록으로만 보인다.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('참여중인 방 목록'));
    await tester.pumpAndSettle();
    expect(find.text('진행 중인 방'), findsNothing);
    expect(find.text('완료된 정산 기록'), findsOneWidget);
    await tester.tap(find.text('저녁 모임'));
    await tester.pumpAndSettle();
    expect(find.textContaining('[퉁 정산 기록] 저녁 모임'), findsOneWidget);
    expect(find.textContaining('1. 음식점 · 결제 민수 · 10,000원'), findsOneWidget);
    await tester.tap(find.text('기록 복사'));
    await tester.pumpAndSettle();
    expect(copied.single, contains('- 주고받을 돈이 없습니다.'));
  });

  testWidgets('방 링크로 들어오면 코드가 채워지고 닉네임만 입력해 입장한다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = LocalRoomStore();
    final room = await store.createRoom('친구 방', '지수');
    await prefs.setString('toong_actor_id', 'me');

    final links = StreamController<Uri>();
    addTearDown(links.close);
    await tester.pumpWidget(ToongApp(store: store, links: links.stream));

    // 방 링크가 아닌 주소는 무시한다.
    links.add(Uri.parse('toong://other/${room.code}'));
    await tester.pumpAndSettle();
    expect(find.text('게스트 이용 안내'), findsNothing);

    links.add(Uri.parse(roomLink(room.code)));
    await tester.pumpAndSettle();
    expect(find.text('게스트 이용 안내'), findsOneWidget);
    await tester.tap(find.text('확인했어요'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, room.code), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).at(1), '민수');
    await tester.tap(find.text('입장하기'));
    await tester.pumpAndSettle();
    expect(find.text('친구 방'), findsOneWidget);
    expect(find.text('방 링크 복사'), findsOneWidget);

    // 이미 참여한 방의 링크는 안내 없이 바로 방을 연다.
    await tester.pageBack();
    await tester.pumpAndSettle();
    links.add(Uri.parse(roomLink(room.code)));
    await tester.pumpAndSettle();
    expect(find.text('게스트 이용 안내'), findsNothing);
    expect(find.text('친구 방'), findsOneWidget);
  });
}
