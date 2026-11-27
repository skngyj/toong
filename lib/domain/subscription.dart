/// 정기 구독 정산. 한 사람이 매달 결제하고 함께 쓰는 사람들이 나눠 낸다.
/// 이 기기에만 저장하며, 결제일 알림도 이 기기에만 온다.
library;

import 'bank.dart';

class SubscriptionMember {
  const SubscriptionMember({required this.id, required this.name});
  final String id;
  final String name;

  Map<String, dynamic> toJson() => {'id': id, 'name': name};
  factory SubscriptionMember.fromJson(Map<String, dynamic> json) =>
      SubscriptionMember(
        id: json['id'] as String,
        name: json['name'] as String,
      );
}

class Subscription {
  const Subscription({
    required this.id,
    required this.name,
    required this.amount,
    required this.day,
    required this.hour,
    required this.minute,
    required this.members,
    required this.payerId,
    required this.meId,
    required this.createdAt,
    this.shares,
    this.remindBefore = false,
    this.payerAccount,
    this.paid = const {},
    this.ledgerMonths = const [],
    this.notifyBase = 0,
  });

  final String id;

  /// 예: 넷플릭스
  final String name;

  /// 한 달 결제 금액.
  final int amount;

  /// 매달 결제일(1~31). 그 날이 없는 달은 마지막 날.
  final int day;

  /// 알림 시각.
  final int hour;
  final int minute;

  /// 함께 쓰는 사람들(결제하는 사람과 나 포함).
  final List<SubscriptionMember> members;
  final String payerId;

  /// 이 기기 주인.
  final String meId;
  final DateTime createdAt;

  /// 사람마다 직접 정한 금액(합이 [amount]). null이면 똑같이 나눈다.
  final Map<String, int>? shares;

  /// 결제일 전날에도 알릴지.
  final bool remindBefore;

  /// 결제하는 사람의 계좌. 요청 글과 송금하기에 쓴다.
  final BankAccount? payerAccount;

  /// 달('2026-11')마다 돈을 낸 사람 id.
  final Map<String, List<String>> paid;

  /// 가계부에 내 몫을 이미 넣은 달. 사용자가 지운 기록이 다시 생기지 않게 한다.
  final List<String> ledgerMonths;

  /// 알림 id의 시작값. 구독마다 다르다.
  final int notifyBase;

  String memberName(String id) =>
      members.where((m) => m.id == id).firstOrNull?.name ?? '알 수 없음';

  bool get iAmPayer => meId == payerId;

  /// 사람마다 이번 달 낼 금액. 똑같이 나누면 잔돈은 결제하는 사람이 낸다.
  Map<String, int> get shareOf {
    if (shares != null) {
      return {for (final m in members) m.id: shares![m.id] ?? 0};
    }
    final each = amount ~/ members.length;
    final left = amount - each * members.length;
    return {for (final m in members) m.id: each + (m.id == payerId ? left : 0)};
  }

  int get myShare => shareOf[meId] ?? 0;

  /// 결제하는 사람에게 보낼 사람들(결제하는 사람 제외, 0원 제외).
  List<SubscriptionMember> get senders => [
    for (final m in members)
      if (m.id != payerId && (shareOf[m.id] ?? 0) > 0) m,
  ];

  /// [month]에 돈을 낸 사람 id. 결제하는 사람은 늘 낸 것으로 본다.
  Set<String> paidIn(String month) => {...?paid[month], payerId};

  Subscription copyWith({
    String? name,
    int? amount,
    int? day,
    int? hour,
    int? minute,
    List<SubscriptionMember>? members,
    String? payerId,
    Map<String, int>? shares,
    bool clearShares = false,
    bool? remindBefore,
    BankAccount? payerAccount,
    bool clearAccount = false,
    Map<String, List<String>>? paid,
    List<String>? ledgerMonths,
    int? notifyBase,
  }) => Subscription(
    id: id,
    name: name ?? this.name,
    amount: amount ?? this.amount,
    day: day ?? this.day,
    hour: hour ?? this.hour,
    minute: minute ?? this.minute,
    members: members ?? this.members,
    payerId: payerId ?? this.payerId,
    meId: meId,
    createdAt: createdAt,
    shares: clearShares ? null : shares ?? this.shares,
    remindBefore: remindBefore ?? this.remindBefore,
    payerAccount: clearAccount ? null : payerAccount ?? this.payerAccount,
    paid: paid ?? this.paid,
    ledgerMonths: ledgerMonths ?? this.ledgerMonths,
    notifyBase: notifyBase ?? this.notifyBase,
  );

  /// [month]에 [memberId]가 낸 것으로 표시하거나 푼다.
  Subscription markPaid(String month, String memberId, bool value) {
    final set = {...?paid[month]};
    value ? set.add(memberId) : set.remove(memberId);
    return copyWith(paid: {...paid, month: set.toList()..sort()});
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'amount': amount,
    'day': day,
    'hour': hour,
    'minute': minute,
    'members': members.map((m) => m.toJson()).toList(),
    'payer_id': payerId,
    'me_id': meId,
    'created_at': createdAt.toIso8601String(),
    'shares': shares,
    'remind_before': remindBefore,
    'payer_account': payerAccount?.toJson(),
    'paid': paid,
    'ledger_months': ledgerMonths,
    'notify_base': notifyBase,
  };

  factory Subscription.fromJson(Map<String, dynamic> json) => Subscription(
    id: json['id'] as String,
    name: json['name'] as String,
    amount: (json['amount'] as num).toInt(),
    day: (json['day'] as num).toInt(),
    hour: (json['hour'] as num).toInt(),
    minute: (json['minute'] as num).toInt(),
    members: [
      for (final m in json['members'] as List)
        SubscriptionMember.fromJson(Map<String, dynamic>.from(m as Map)),
    ],
    payerId: json['payer_id'] as String,
    meId: json['me_id'] as String,
    createdAt: DateTime.parse(json['created_at'] as String),
    shares: (json['shares'] as Map?)?.map(
      (k, v) => MapEntry(k as String, (v as num).toInt()),
    ),
    remindBefore: json['remind_before'] as bool? ?? false,
    payerAccount: BankAccount.fromJson(json['payer_account']),
    paid: {
      for (final MapEntry(:key, :value)
          in (json['paid'] as Map? ?? const {}).entries)
        key as String: List<String>.from(value as List),
    },
    ledgerMonths: List<String>.from(json['ledger_months'] as List? ?? const []),
    notifyBase: (json['notify_base'] as num?)?.toInt() ?? 0,
  );
}

/// '2026-11'처럼 달을 나타내는 글자.
String monthKey(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}';

/// [year]년 [month]월의 결제일. 그 날이 없는 달은 마지막 날이다.
DateTime billingDate(
  int year,
  int month,
  int day, {
  int hour = 0,
  int minute = 0,
}) {
  final last = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, day > last ? last : day, hour, minute);
}

/// [from] 뒤(같은 시각 포함하지 않음)로 다가오는 결제 알림 시각 [count]개.
List<DateTime> upcomingBillings(Subscription s, DateTime from, int count) {
  final result = <DateTime>[];
  var year = from.year, month = from.month;
  while (result.length < count) {
    final at = billingDate(year, month, s.day, hour: s.hour, minute: s.minute);
    if (at.isAfter(from)) result.add(at);
    month++;
    if (month > 12) {
      month = 1;
      year++;
    }
  }
  return result;
}

/// [from]부터 [to]까지(둘 다 포함) 지난 결제일들. 가계부 자동 기록에 쓴다.
List<DateTime> billingsBetween(Subscription s, DateTime from, DateTime to) {
  final result = <DateTime>[];
  var year = from.year, month = from.month;
  while (true) {
    final at = billingDate(year, month, s.day);
    if (at.isAfter(to)) break;
    if (!at.isBefore(DateTime(from.year, from.month, from.day))) result.add(at);
    month++;
    if (month > 12) {
      month = 1;
      year++;
    }
  }
  return result;
}

String _won(int v) =>
    '${v.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',')}원';

/// 결제일 알림 문구.
({String title, String body}) billingMessage(Subscription s) {
  if (s.iAmPayer) {
    final names = s.senders.map((m) => m.name).join('·');
    final shares = s.senders.map((m) => s.shareOf[m.id]!).toSet();
    final what = shares.length == 1
        ? '각 ${_won(shares.single)}'
        : s.senders
              .map((m) => '${m.name} ${_won(s.shareOf[m.id]!)}')
              .join(', ');
    return (
      title: '오늘은 ${s.name} 결제일이에요',
      body: s.senders.isEmpty
          ? '이번 달 ${_won(s.amount)}이 결제돼요.'
          : '$names 님에게 $what 받을 차례예요.',
    );
  }
  return (
    title: '오늘은 ${s.name} 결제일이에요',
    body: '${_won(s.myShare)}을 ${s.memberName(s.payerId)} 님에게 보낼 날이에요.',
  );
}

/// 결제일 전날 알림 문구.
({String title, String body}) reminderMessage(Subscription s) => (
  title: '내일은 ${s.name} 결제일이에요',
  body: s.iAmPayer
      ? '${_won(s.amount)}이 결제돼요. 함께 쓰는 사람들에게 미리 알려주세요.'
      : '${_won(s.myShare)}을 ${s.memberName(s.payerId)} 님에게 보낼 준비를 해주세요.',
);

/// 친구에게 보낼 요청 글.
String requestText(Subscription s, DateTime month) {
  final lines = <String>[
    '[퉁] ${month.month}월 ${s.name} ${_won(s.amount)} 정산',
    for (final m in s.senders)
      '- ${m.name} ${_won(s.shareOf[m.id]!)}'
          '${s.paidIn(monthKey(month)).contains(m.id) ? ' (보냄)' : ''}',
    '${s.memberName(s.payerId)} 님에게 보내주세요.',
  ];
  if (s.payerAccount != null) lines.add(s.payerAccount!.label);
  return lines.join('\n');
}
