import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'account_ui.dart';
import 'data/nickname_store.dart';
import 'data/room_store.dart' show newId;
import 'data/subscription_store.dart';
import 'domain/bank.dart';
import 'domain/subscription.dart';
import 'reminders.dart';
import 'theme.dart';

String _won(int v) =>
    '${v.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',')}원';

/// "오전 9:00", "오후 9:30"
String timeLabel(int hour, int minute) {
  final half = hour < 12 ? '오전' : '오후';
  final h = hour % 12 == 0 ? 12 : hour % 12;
  return '$half $h:${minute.toString().padLeft(2, '0')}';
}

/// 정기 구독 목록.
class SubscriptionListPage extends StatefulWidget {
  const SubscriptionListPage({super.key});
  @override
  State<SubscriptionListPage> createState() => _SubscriptionListPageState();
}

class _SubscriptionListPageState extends State<SubscriptionListPage> {
  late Future<List<Subscription>> future = SubscriptionStore().list();

  void reload() => setState(() {
    future = SubscriptionStore().list();
  });

  Future<void> open(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    if (mounted) reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('정기 구독')),
    body: FutureBuilder(
      future: future,
      builder: (context, snapshot) {
        final items = snapshot.data;
        if (items == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final now = DateTime.now();
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [
            const Text(
              '넷플릭스처럼 한 사람이 결제하고 나눠 내는 구독을 등록하면, 결제일마다 '
              '누가 얼마를 보낼지 알려줘요. 이 기기에만 저장돼요.',
              style: TextStyle(color: toongSub),
            ),
            const SizedBox(height: 16),
            if (items.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('아직 등록한 구독이 없어요.'),
                ),
              ),
            for (final s in items)
              Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  contentPadding: const EdgeInsets.fromLTRB(18, 8, 12, 8),
                  title: Text(
                    s.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    '매달 ${s.day}일 · ${_won(s.amount)} · ${s.members.length}명\n'
                    '${s.iAmPayer ? '내가 결제 · 이번 달 ${s.senders.where((m) => s.paidIn(monthKey(now)).contains(m.id)).length}/${s.senders.length}명 보냄' : '내 몫 ${_won(s.myShare)} → ${s.memberName(s.payerId)}'}',
                  ),
                  isThreeLine: true,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => open(SubscriptionDetailPage(id: s.id)),
                ),
              ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () => open(const SubscriptionEditPage()),
              icon: const Icon(Icons.add),
              label: const Text('구독 추가'),
            ),
          ],
        );
      },
    ),
  );
}

/// 구독 등록·수정.
class SubscriptionEditPage extends StatefulWidget {
  const SubscriptionEditPage({super.key, this.initial});
  final Subscription? initial;
  @override
  State<SubscriptionEditPage> createState() => _SubscriptionEditPageState();
}

class _MemberDraft {
  _MemberDraft(this.id, String name, int? share)
    : name = TextEditingController(text: name),
      share = TextEditingController(text: share == null ? '' : '$share');
  final String id;
  final TextEditingController name;
  final TextEditingController share;
  void dispose() {
    name.dispose();
    share.dispose();
  }
}

class _SubscriptionEditPageState extends State<SubscriptionEditPage> {
  late final Subscription? s = widget.initial;
  late final name = TextEditingController(text: s?.name);
  late final amount = TextEditingController(
    text: s == null ? '' : '${s!.amount}',
  );
  late int day = s?.day ?? DateTime.now().day;
  late int hour = s?.hour ?? 10;
  late int minute = s?.minute ?? 0;
  late bool remindBefore = s?.remindBefore ?? false;
  late bool custom = s?.shares != null;
  late final List<_MemberDraft> members = s == null
      ? [_MemberDraft(newId(), '나', null), _MemberDraft(newId(), '', null)]
      : [
          for (final m in s!.members)
            _MemberDraft(m.id, m.name, s!.shares?[m.id]),
        ];
  late String meId = s?.meId ?? members.first.id;
  late String payerId = s?.payerId ?? members.first.id;
  late final account = AccountController(s?.payerAccount);
  bool busy = false;

  @override
  void initState() {
    super.initState();
    // 새 구독이면 저장된 닉네임과 내 계좌를 채운다.
    if (s == null) {
      NicknameStore().load().then((nick) {
        final me = members.first.name;
        if (nick != null && mounted && me.text == '나') {
          setState(() => me.text = nick);
        }
      });
      MyAccountStore().load().then((saved) {
        if (saved != null && mounted && account.isEmpty) {
          setState(() => account.fill(saved));
        }
      });
    }
  }

  @override
  void dispose() {
    name.dispose();
    amount.dispose();
    account.dispose();
    for (final m in members) {
      m.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    String? problem;
    final total = int.tryParse(amount.text.trim());
    final names = [for (final m in members) m.name.text.trim()];
    Map<String, int>? shares;
    if (name.text.trim().isEmpty) {
      problem = '구독 이름을 입력해주세요.';
    } else if (total == null || total < 1 || total > 10000000) {
      problem = '한 달 금액을 1원 이상 입력해주세요.';
    } else if (members.length < 2) {
      problem = '함께 쓰는 사람을 한 명 이상 추가해주세요.';
    } else if (names.any((n) => n.isEmpty || n.length > 12)) {
      problem = '이름을 1~12자로 입력해주세요.';
    } else if (names.toSet().length != names.length) {
      problem = '같은 이름이 있어요.';
    } else if (custom) {
      shares = {
        for (final m in members) m.id: int.tryParse(m.share.text.trim()) ?? -1,
      };
      final sum = shares.values.fold(0, (a, b) => a + b);
      if (shares.values.any((v) => v < 0)) {
        problem = '사람마다 금액을 입력해주세요. 안 내는 사람은 0으로 적어요.';
      } else if (sum != total) {
        problem = '사람마다 정한 금액의 합(${_won(sum)})이 한 달 금액(${_won(total)})과 달라요.';
      }
    }
    BankAccount? payerAccount;
    if (problem == null && !account.isEmpty) {
      try {
        payerAccount = account.read();
      } on StateError catch (e) {
        problem = e.message;
      }
    }
    if (problem != null) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('확인해주세요'),
          content: Text(problem!),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('확인'),
            ),
          ],
        ),
      );
      return;
    }
    setState(() => busy = true);
    final draft = Subscription(
      id: s?.id ?? newId(),
      name: name.text.trim(),
      amount: total!,
      day: day,
      hour: hour,
      minute: minute,
      members: [
        for (final (i, m) in members.indexed)
          SubscriptionMember(id: m.id, name: names[i]),
      ],
      payerId: payerId,
      meId: meId,
      createdAt: s?.createdAt ?? DateTime.now(),
      shares: shares,
      remindBefore: remindBefore,
      payerAccount: payerAccount,
      paid: s?.paid ?? const {},
      ledgerMonths: s?.ledgerMonths ?? const [],
      notifyBase: s?.notifyBase ?? 0,
    );
    final saved = await SubscriptionStore().save(draft);
    var allowed = true;
    try {
      allowed = await reminders.requestPermission();
      await reminders.schedule(saved);
    } catch (_) {
      allowed = false;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          allowed
              ? '매달 $day일 ${timeLabel(hour, minute)}에 알려드릴게요.'
              : '저장했어요. 알림을 받으려면 설정에서 퉁 알림을 허용해주세요.',
        ),
      ),
    );
    Navigator.pop(context, saved);
  }

  @override
  Widget build(BuildContext context) {
    final iAmPayer = meId == payerId;
    return Scaffold(
      appBar: AppBar(title: Text(s == null ? '구독 추가' : '구독 수정')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          TextField(
            controller: name,
            maxLength: 20,
            decoration: const InputDecoration(
              labelText: '구독 이름',
              hintText: '예: 넷플릭스',
            ),
          ),
          TextField(
            controller: amount,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: '한 달 금액 (원)'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: day,
            isExpanded: true,
            decoration: const InputDecoration(labelText: '결제일'),
            items: [
              for (var d = 1; d <= 31; d++)
                DropdownMenuItem(value: d, child: Text('매달 $d일')),
            ],
            onChanged: (v) => setState(() => day = v ?? day),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: hour,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '알림 시각'),
                  items: [
                    for (var h = 0; h < 24; h++)
                      DropdownMenuItem(
                        value: h,
                        child: Text(timeLabel(h, 0).replaceAll(':00', '시')),
                      ),
                  ],
                  onChanged: (v) => setState(() => hour = v ?? hour),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: minute,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '분'),
                  items: [
                    for (var m = 0; m < 60; m += 10)
                      DropdownMenuItem(
                        value: m,
                        child: Text('${m.toString().padLeft(2, '0')}분'),
                      ),
                  ],
                  onChanged: (v) => setState(() => minute = v ?? minute),
                ),
              ),
            ],
          ),
          if (day > 28)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                '그 날이 없는 달은 마지막 날에 알려요.',
                style: TextStyle(fontSize: 12.5, color: toongSub),
              ),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('결제일 전날에도 알리기'),
            value: remindBefore,
            onChanged: (v) => setState(() => remindBefore = v),
          ),
          const Divider(),
          const Text(
            '함께 쓰는 사람',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const Text(
            '결제하는 사람을 고르고, 나는 ‘나’ 표시를 눌러 정해요.',
            style: TextStyle(fontSize: 12.5, color: toongSub),
          ),
          const SizedBox(height: 8),
          for (final (i, m) in members.indexed) _memberRow(i, m),
          if (members.length < 20)
            TextButton.icon(
              onPressed: () =>
                  setState(() => members.add(_MemberDraft(newId(), '', null))),
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('사람 추가'),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('사람마다 금액 직접 정하기'),
            subtitle: Text(
              custom ? '합이 한 달 금액과 같아야 해요.' : '똑같이 나누고 잔돈은 결제하는 사람이 내요.',
              style: const TextStyle(fontSize: 12.5),
            ),
            value: custom,
            onChanged: (v) => setState(() => custom = v),
          ),
          const Divider(),
          Text(
            iAmPayer ? '송금받을 내 계좌 (선택)' : '결제하는 사람 계좌 (선택)',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          Text(
            iAmPayer ? '요청 글에 함께 넣어요.' : '넣어 두면 결제일에 ‘송금하기’로 바로 보낼 수 있어요.',
            style: const TextStyle(fontSize: 12.5, color: toongSub),
          ),
          const SizedBox(height: 8),
          AccountFields(controller: account),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: busy ? null : save,
            child: Text(busy ? '저장 중…' : '저장'),
          ),
        ],
      ),
    );
  }

  Widget _memberRow(int index, _MemberDraft m) {
    final total = int.tryParse(amount.text) ?? 0;
    final each = members.isEmpty ? 0 : total ~/ members.length;
    final left = total - each * members.length;
    final equalShare = each + (m.id == payerId ? left : 0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: m.name,
              decoration: InputDecoration(
                labelText: '이름 ${index + 1}',
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 6),
          if (custom)
            SizedBox(
              width: 92,
              child: TextField(
                controller: m.share,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: '금액',
                  isDense: true,
                ),
              ),
            )
          else
            SizedBox(
              width: 72,
              child: Text(
                _won(equalShare),
                textAlign: TextAlign.right,
                style: const TextStyle(color: toongSub, fontSize: 13),
              ),
            ),
          ChoiceChip(
            label: const Text('결제'),
            selected: payerId == m.id,
            onSelected: (_) => setState(() => payerId = m.id),
            visualDensity: VisualDensity.compact,
          ),
          ChoiceChip(
            label: const Text('나'),
            selected: meId == m.id,
            onSelected: (_) => setState(() => meId = m.id),
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            tooltip: '이름 ${index + 1} 빼기',
            onPressed: members.length <= 2 || m.id == meId || m.id == payerId
                ? null
                : () => setState(() {
                    members.removeAt(index);
                    m.dispose();
                  }),
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    );
  }
}

/// 구독 하나: 이번 달 낸 사람 체크, 요청 글 복사, 송금하기, 지난달 기록.
class SubscriptionDetailPage extends StatefulWidget {
  const SubscriptionDetailPage({super.key, required this.id, this.now});
  final String id;

  /// 테스트에서 오늘 날짜를 바꿔 끼운다.
  final DateTime? now;
  @override
  State<SubscriptionDetailPage> createState() => _SubscriptionDetailPageState();
}

class _SubscriptionDetailPageState extends State<SubscriptionDetailPage> {
  Subscription? sub;
  bool loaded = false;

  DateTime get now => widget.now ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final found = await SubscriptionStore().get(widget.id);
    if (mounted) {
      setState(() {
        sub = found;
        loaded = true;
      });
    }
  }

  /// 이번 결제 달. 아직 이번 달 결제일 전이면 지난달을 보여준다(등록한 달은 이번 달).
  DateTime get currentMonth {
    final s = sub!;
    final thisMonth = billingDate(now.year, now.month, s.day);
    final created = DateTime(s.createdAt.year, s.createdAt.month);
    final month = DateTime(now.year, now.month);
    if (!now.isBefore(thisMonth) || !month.isAfter(created)) return month;
    return DateTime(now.year, now.month - 1);
  }

  Future<void> toggle(String month, SubscriptionMember m, bool value) async {
    final updated = sub!.markPaid(month, m.id, value);
    await SubscriptionStore().save(updated);
    setState(() => sub = updated);
  }

  Future<void> edit() async {
    final saved = await Navigator.push<Subscription>(
      context,
      MaterialPageRoute(builder: (_) => SubscriptionEditPage(initial: sub)),
    );
    if (saved != null && mounted) setState(() => sub = saved);
  }

  Future<void> delete() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('구독을 지울까요?'),
        content: const Text('결제일 알림도 함께 지워져요. 가계부에 넣은 기록은 남아요.'),
        actions: [
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('확인'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: toongDanger,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('취소'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    if (yes != true) return;
    try {
      await reminders.cancel(sub!);
    } catch (_) {}
    await SubscriptionStore().remove(sub!.id);
    if (mounted) Navigator.pop(context);
  }

  Future<void> copyRequest(DateTime month) async {
    await Clipboard.setData(ClipboardData(text: requestText(sub!, month)));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('요청 글을 복사했어요. 단톡방에 붙여넣어 보내세요.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = sub;
    if (s == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('정기 구독')),
        body: Center(
          child: loaded
              ? const Text('지워진 구독이에요.')
              : const CircularProgressIndicator(),
        ),
      );
    }
    final month = currentMonth;
    final key = monthKey(month);
    final paid = s.paidIn(key);
    final next = upcomingBillings(s, now, 1).single;
    final history = [
      for (
        var m = DateTime(month.year, month.month - 1);
        !m.isBefore(DateTime(s.createdAt.year, s.createdAt.month));
        m = DateTime(m.year, m.month - 1)
      )
        m,
    ].take(12).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(s.name),
        actions: [
          IconButton(
            onPressed: edit,
            icon: const Icon(Icons.edit_outlined),
            tooltip: '수정',
          ),
          IconButton(
            onPressed: delete,
            icon: const Icon(Icons.delete_outline),
            tooltip: '구독 지우기',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          Text(
            '${_won(s.amount)} · 매달 ${s.day}일',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          Text(
            '결제 ${s.memberName(s.payerId)} · 다음 알림 ${next.month}월 ${next.day}일 '
            '${timeLabel(s.hour, s.minute)}${s.remindBefore ? ' (전날도)' : ''}',
            style: const TextStyle(color: toongSub),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${month.month}월 정산',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    '${s.memberName(s.payerId)} 님에게 보낼 돈',
                    style: const TextStyle(color: toongSub, fontSize: 13),
                  ),
                  for (final m in s.senders)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('${m.name}${m.id == s.meId ? ' (나)' : ''}'),
                      subtitle: Text(
                        '${_won(s.shareOf[m.id]!)}${paid.contains(m.id) ? ' · 보냄' : ''}',
                      ),
                      value: paid.contains(m.id),
                      onChanged: (v) => toggle(key, m, v ?? false),
                    ),
                  if (s.senders.isEmpty) const Text('나눠 낼 사람이 없어요.'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => copyRequest(month),
            icon: const Icon(Icons.copy),
            label: const Text('요청 글 복사'),
          ),
          if (!s.iAmPayer && s.payerAccount != null && !paid.contains(s.meId))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: FilledButton.icon(
                onPressed: () async {
                  final opened = await showSendSheet(
                    context,
                    to: s.memberName(s.payerId),
                    amount: s.myShare,
                    amountText: _won(s.myShare),
                    account: s.payerAccount!,
                  );
                  if (opened && mounted) {
                    final me = s.members.firstWhere((m) => m.id == s.meId);
                    await toggle(key, me, true);
                  }
                },
                icon: const Icon(Icons.send),
                label: Text('${_won(s.myShare)} 송금하기'),
              ),
            ),
          TextButton.icon(
            onPressed: () async {
              try {
                await reminders.showNow(s);
              } catch (_) {}
            },
            icon: const Icon(Icons.notifications_outlined),
            label: const Text('알림 미리 보기'),
          ),
          if (s.myShare > 0)
            Text(
              '결제일이 지나면 내 몫 ${_won(s.myShare)}을 가계부에 ‘구독’으로 적어요.',
              style: const TextStyle(fontSize: 12.5, color: toongSub),
            ),
          if (history.isNotEmpty) ...[
            const SizedBox(height: 18),
            const Text(
              '지난 달',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            for (final m in history)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${m.year}년 ${m.month}월'),
                trailing: Text(
                  '${s.senders.where((x) => s.paidIn(monthKey(m)).contains(x.id)).length}'
                  '/${s.senders.length}명 보냄',
                ),
              ),
          ],
        ],
      ),
    );
  }
}
