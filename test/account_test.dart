import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toong/account_ui.dart';
import 'package:toong/app.dart';
import 'package:toong/data/room_store.dart';
import 'package:toong/domain/bank.dart';
import 'package:toong/domain/models.dart';

const kakao = BankAccount(
  bank: 'kakao',
  number: '3333-01-1234567',
  holder: '김지수',
);

/// 민수(방장, 기기 주인)·지수(다른 기기)·현우(방장이 추가, 미연결) 방.
/// 고깃집 30,000원을 지수가 결제하고 민수·지수가 나눠 민수가 지수에게 15,000원을 보낸다.
Future<(LocalRoomStore, Room, SharedPreferences, String owner)> setup() async {
  SharedPreferences.setMockInitialValues({});
  final store = LocalRoomStore();
  final prefs = await SharedPreferences.getInstance();
  var room = await store.createRoom('모임', '민수');
  final owner = prefs.getString('toong_actor_id')!;
  await prefs.setString('toong_actor_id', 'a2');
  room = await store.joinRoom(room.code, '지수');
  await prefs.setString('toong_actor_id', owner);
  room = await store.addMember(room, '현우');
  final [minsu, jisu, _] = room.members;
  room = await store.saveRoom(
    room.copyWith(
      expenses: [
        Expense(
          id: 'e1',
          title: '고깃집',
          payerId: jisu.id,
          items: [
            LineItem(
              id: 'i1',
              name: '삼겹살',
              amount: 30000,
              memberIds: [minsu.id, jisu.id],
            ),
          ],
        ),
      ],
    ),
  );
  return (store, room, prefs, owner);
}

void main() {
  group('계좌', () {
    test('계좌번호 형식과 복사 글', () {
      expect(isValidAccountNumber('3333-01-1234567'), isTrue);
      expect(isValidAccountNumber('123456789012'), isTrue);
      expect(isValidAccountNumber('1234567'), isFalse);
      expect(isValidAccountNumber('1234-abcd-5678'), isFalse);
      expect(isValidAccountNumber('1' * 21), isFalse);
      expect(kakao.copyText, '카카오뱅크 3333011234567');
      expect(kakao.label, '카카오뱅크 3333-01-1234567 김지수');
      expect(bankName('nh'), 'NH농협은행');
      expect(bankName('ibk'), 'IBK기업은행');
      expect(banks.map((b) => b.code).toSet(), hasLength(banks.length));
    });

    test('본인과 방장(미연결 사람)만 계좌를 바꾸고, 저장·복제·빼기에 맞게 남거나 지워진다', () async {
      final (store, room0, prefs, owner) = await setup();
      var room = room0;
      final [minsu, jisu, hyunwoo] = room.members;

      // 방장은 자기 계좌와 미연결 현우 계좌를 넣는다.
      room = await store.setAccount(room, minsu.id, kakao);
      room = await store.setAccount(
        room,
        hyunwoo.id,
        const BankAccount(
          bank: 'nh',
          number: '302-1234-5678-91',
          holder: '이현우',
        ),
      );
      // 연결된 지수 계좌는 방장도 못 바꾼다.
      await expectLater(
        store.setAccount(room, jisu.id, kakao),
        throwsA(isA<StateError>()),
      );
      // 잘못된 값.
      await expectLater(
        store.setAccount(
          room,
          minsu.id,
          const BankAccount(bank: 'kb', number: '123', holder: '민수'),
        ),
        throwsA(isA<StateError>()),
      );
      // 지수는 자기 계좌만.
      await prefs.setString('toong_actor_id', 'a2');
      room = await store.setAccount(room, jisu.id, kakao);
      await expectLater(
        store.setAccount(room, minsu.id, null),
        throwsA(isA<StateError>()),
      );
      await prefs.setString('toong_actor_id', owner);

      // 지출 저장은 계좌를 바꾸지 못한다.
      room = await store.saveRoom(room.copyWith(accounts: {}));
      expect(
        room.accounts.keys,
        unorderedEquals([minsu.id, hyunwoo.id, jisu.id]),
      );
      // JSON으로 저장했다가 읽어도 같다.
      expect(Room.decode(room.encode()).accounts[hyunwoo.id]!.holder, '이현우');

      // 사람을 빼면 계좌도 지운다. 본인은 지울 수 있다.
      room = await store.removeMember(room, hyunwoo.id);
      expect(room.accounts.containsKey(hyunwoo.id), isFalse);
      room = await store.setAccount(room, minsu.id, null);
      expect(room.accounts.keys, [jisu.id]);

      // 복제한 방은 계좌를 물려받지 않는다.
      expect((await store.cloneRoom(room)).accounts, isEmpty);
    });
  });

  testWidgets('방을 만들 때 넣은 계좌는 방과 기기에 저장되고 다음에 자동으로 채워진다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = LocalRoomStore();
    await tester.pumpWidget(ToongApp(store: store));
    await tester.tap(find.text('새방 만들기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), '저녁 모임');
    await tester.enterText(find.byType(TextFormField).at(1), '민수');
    await tester.tap(find.text('송금받을 내 계좌 (선택)'));
    await tester.pumpAndSettle();

    // 일부만 넣으면 방을 만들지 않고 알려준다.
    await tester.enterText(
      find.widgetWithText(TextField, '계좌번호'),
      '3333011234567',
    );
    await tester.tap(find.text('방 만들기'));
    await tester.pumpAndSettle();
    expect(find.text('은행을 골라주세요.'), findsOneWidget);
    await tester.tap(find.text('확인').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('카카오뱅크').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '예금주'), '김민수');
    await tester.tap(find.text('방 만들기'));
    await tester.pumpAndSettle();

    final room = (await store.listRooms()).single;
    expect(room.accounts.values.single.label, '카카오뱅크 3333011234567 김민수');
    expect((await MyAccountStore().load())!.holder, '김민수');
    expect(find.text('내 계좌 카카오뱅크 3333011234567'), findsOneWidget);

    // 다음 방 만들기에서는 저장된 계좌가 채워져 있다.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('새방 만들기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, '3333011234567'), findsOneWidget);
    expect(find.widgetWithText(TextField, '김민수'), findsOneWidget);
  });

  testWidgets('보내는 사람만 송금하기로 계좌를 복사하고 은행 앱을 열고, 돌아오면 송금 완료를 묻는다', (
    tester,
  ) async {
    final (store, room0, prefs, owner) = await setup();
    final [minsu, jisu, _] = room0.members;
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
    final opened = <String>[];
    final original = openBankApp;
    addTearDown(() => openBankApp = original);
    openBankApp = (app) async {
      opened.add(app.package);
      return 'opened';
    };

    // 지수가 계좌를 아직 안 넣었으면 송금하기 대신 안내가 보인다.
    await tester.pumpWidget(
      MaterialApp(
        home: SettlementPage(store: store, room: room0),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('민수 → 지수'), findsOneWidget);
    expect(find.text('지수 님이 계좌를 아직 등록하지 않았어요.'), findsOneWidget);
    expect(find.text('송금하기'), findsNothing);

    await prefs.setString('toong_actor_id', 'a2');
    await store.setAccount(room0, jisu.id, kakao);
    await prefs.setString('toong_actor_id', owner);
    await tester.tap(find.byTooltip('새로고침'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('송금하기'));
    await tester.pumpAndSettle();
    expect(find.text('지수 님에게 15,000원 보내기'), findsOneWidget);
    expect(find.text('3333-01-1234567'), findsOneWidget);
    expect(find.text('NH올원뱅크'), findsOneWidget);
    expect(find.text('IBK기업은행'), findsOneWidget);

    await tester.tap(find.text('금액 복사'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('토스'));
    await tester.tap(find.text('토스'));
    await tester.pumpAndSettle();
    expect(copied, ['15000', '카카오뱅크 3333011234567']);
    expect(opened, ['com.viva.republica.toss']);

    // 은행 앱에서 돌아오면 송금 완료로 표시할지 묻는다.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('이 금액이 정산되었나요?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '확인'));
    await tester.pumpAndSettle();
    final saved = await store.getRoom(room0.id);
    expect(saved.isPaid(minsu.id, jisu.id, 15000), isTrue);
    expect(find.text('송금하기'), findsNothing);
  });

  testWidgets('받는 사람에게는 송금하기가 보이지 않는다', (tester) async {
    final (store, room0, prefs, owner) = await setup();
    final [_, jisu, _] = room0.members;
    await prefs.setString('toong_actor_id', 'a2');
    final room = await store.setAccount(room0, jisu.id, kakao);
    await tester.pumpWidget(
      MaterialApp(
        home: SettlementPage(store: store, room: room),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('민수 → 지수'), findsOneWidget);
    expect(find.text('송금하기'), findsNothing);
    expect(find.textContaining('계좌를 아직'), findsNothing);
  });
}
