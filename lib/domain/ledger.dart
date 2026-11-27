import 'dart:convert';

import 'models.dart';

/// 가계부 기본 분류.
const ledgerCategories = ['식비', '카페', '술자리', '놀거리', '교통', '쇼핑', '구독', '기타'];

/// 지출 제목에서 분류를 추정한다. 맞는 말이 없으면 기타. 사용자가 나중에 바꿀 수 있다.
String guessCategory(String title) {
  final t = title.toLowerCase().replaceAll(' ', '');
  bool has(List<String> words) => words.any(t.contains);
  if (has([
    '카페',
    '커피',
    '스타벅스',
    '투썸',
    '이디야',
    '메가커피',
    '빽다방',
    '컴포즈',
    '디저트',
    '베이커리',
    '빵',
    '케이크',
    '라떼',
    '아메리카노',
  ])) {
    return '카페';
  }
  if (has(['술', '호프', '포차', '이자카야', '맥주', '소주', '와인', '펍', '2차'])) {
    return '술자리';
  }
  if (has([
    '노래방',
    '코인',
    'pc방',
    '피시방',
    '볼링',
    '당구',
    '방탈출',
    '영화',
    'cgv',
    '메가박스',
    '롯데시네마',
    '보드게임',
    '오락실',
  ])) {
    return '놀거리';
  }
  if (has([
    '택시',
    '버스',
    '지하철',
    '주유',
    'ktx',
    'srt',
    '기차',
    '톨게이트',
    '주차',
    '렌트',
    '카카오t',
  ])) {
    return '교통';
  }
  if (has([
    '마트',
    '편의점',
    '다이소',
    '쿠팡',
    '올리브영',
    '쇼핑',
    'gs25',
    'cu',
    '세븐일레븐',
    '이마트',
    '홈플러스',
  ])) {
    return '쇼핑';
  }
  if (has([
    '식당',
    '고기',
    '고깃',
    '삼겹',
    '갈비',
    '치킨',
    '피자',
    '국밥',
    '찌개',
    '분식',
    '떡볶이',
    '버거',
    '초밥',
    '스시',
    '김밥',
    '밥',
    '식사',
    '점심',
    '저녁',
    '아침',
    '배달',
    '면',
    '중식',
    '한식',
    '양식',
    '일식',
    '곱창',
    '족발',
    '보쌈',
    '마라',
    '샤브',
  ])) {
    return '식비';
  }
  return '기타';
}

/// 가계부 한 줄. 모두 이 기기에만 저장한다.
class LedgerEntry {
  const LedgerEntry({
    required this.id,
    required this.date,
    required this.title,
    required this.amount,
    required this.category,
    this.roomId,
    this.roomName,
  });
  final String id;

  /// 쓴 날(현지 시각 기준 날짜).
  final DateTime date;
  final String title;

  /// 내가 실제로 부담한 금액.
  final int amount;
  final String category;

  /// 정산에서 온 기록이면 그 방. 직접 기록이면 null.
  final String? roomId;
  final String? roomName;

  bool get fromRoom => roomId != null;

  LedgerEntry copyWith({
    DateTime? date,
    String? title,
    int? amount,
    String? category,
  }) => LedgerEntry(
    id: id,
    date: date ?? this.date,
    title: title ?? this.title,
    amount: amount ?? this.amount,
    category: category ?? this.category,
    roomId: roomId,
    roomName: roomName,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'date': '${date.year}-${_two(date.month)}-${_two(date.day)}',
    'title': title,
    'amount': amount,
    'category': category,
    'room_id': roomId,
    'room_name': roomName,
  };
  factory LedgerEntry.fromJson(Map<String, dynamic> json) => LedgerEntry(
    id: json['id'] as String,
    date: DateTime.parse(json['date'] as String),
    title: json['title'] as String,
    amount: (json['amount'] as num).toInt(),
    category: json['category'] as String,
    roomId: json['room_id'] as String?,
    roomName: json['room_name'] as String?,
  );
  static LedgerEntry decode(String source) =>
      LedgerEntry.fromJson(jsonDecode(source) as Map<String, dynamic>);
  String encode() => jsonEncode(toJson());
}

String _two(int value) => value.toString().padLeft(2, '0');

/// 날짜만 남긴다(시각은 버린다).
DateTime dayOf(DateTime time) {
  final t = time.toLocal();
  return DateTime(t.year, t.month, t.day);
}

/// 완료된 방에서 [memberId]가 실제로 부담한 금액을 지출 한 건당 한 줄로 만든다.
///
/// 대신 결제한 금액이 아니라 내 몫만 센다. 내 몫이 없는 지출은 넣지 않는다.
List<LedgerEntry> entriesFromRoom(Room room, String memberId) {
  final day = dayOf(room.completedAt ?? room.lastActivityAt);
  final entries = <LedgerEntry>[];
  for (final expense in room.expenses) {
    var mine = 0;
    for (final item in expense.items) {
      if (!item.memberIds.contains(memberId)) continue;
      mine += item.amount ~/ item.memberIds.length;
      if (item.remainderMemberId == memberId) mine += item.remainder;
    }
    if (mine <= 0) continue;
    entries.add(
      LedgerEntry(
        id: 'room:${room.id}:${expense.id}',
        date: day,
        title: expense.title,
        amount: mine,
        category: guessCategory(expense.title),
        roomId: room.id,
        roomName: room.name,
      ),
    );
  }
  return entries;
}

/// [month]가 속한 달의 기록만 고른다.
List<LedgerEntry> inMonth(List<LedgerEntry> entries, DateTime month) => entries
    .where((e) => e.date.year == month.year && e.date.month == month.month)
    .toList();

int sumOf(Iterable<LedgerEntry> entries) =>
    entries.fold(0, (sum, e) => sum + e.amount);

/// 분류별 합계. 금액이 큰 분류부터.
List<({String category, int amount})> categoryTotals(
  Iterable<LedgerEntry> entries,
) {
  final totals = <String, int>{};
  for (final e in entries) {
    totals[e.category] = (totals[e.category] ?? 0) + e.amount;
  }
  final list = [
    for (final MapEntry(:key, :value) in totals.entries)
      (category: key, amount: value),
  ]..sort((a, b) => b.amount.compareTo(a.amount));
  return list;
}

/// 예산 대비 사용 단계. 0: 80% 미만, 80: 80% 이상, 100: 예산 이상.
int budgetLevel(int spent, int? budget) {
  if (budget == null || budget <= 0) return 0;
  if (spent >= budget) return 100;
  if (spent * 10 >= budget * 8) return 80;
  return 0;
}
