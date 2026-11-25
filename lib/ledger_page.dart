import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'data/ledger_store.dart';
import 'data/record_store.dart';
import 'domain/ledger.dart';
import 'data/room_store.dart' show newId;

const _warnColor = Color(0xFFFFF1E6);
const _overColor = Color(0xFFE5484D);
const _okColor = Color(0xFFC8EE7D);
const _softColor = Color(0xFFECF1E6);

/// 예산 알림 창. 문구가 없으면 아무것도 하지 않는다.
Future<void> showBudgetAlert(BuildContext context, String? message) async {
  if (message == null || !context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('예산 알림'),
      content: Text(message),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('확인'),
        ),
      ],
    ),
  );
}

/// 개인 가계부. 정산 완료로 자동 기록된 내 부담액과 직접 기록한 지출을 월별로 보여준다.
/// 모든 기록은 이 기기에만 저장된다.
class LedgerPage extends StatefulWidget {
  const LedgerPage({super.key, this.now});

  /// 테스트에서 오늘 날짜를 고정할 때 쓴다.
  final DateTime? now;
  @override
  State<LedgerPage> createState() => _LedgerPageState();
}

class _LedgerPageState extends State<LedgerPage> {
  final store = LedgerStore();
  late DateTime month;
  List<LedgerEntry> entries = [];
  int? budget;
  bool loading = true;

  DateTime get today => widget.now ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    month = DateTime(today.year, today.month);
    load();
  }

  Future<void> load() async {
    final list = await store.list();
    final limit = await store.budget();
    if (!mounted) return;
    setState(() {
      entries = list;
      budget = limit;
      loading = false;
    });
  }

  bool get isThisMonth =>
      month.year == today.year && month.month == today.month;

  void moveMonth(int delta) =>
      setState(() => month = DateTime(month.year, month.month + delta));

  Future<void> editBudget() async {
    final controller = TextEditingController(
      text: budget == null ? '' : '$budget',
    );
    final accepted = await showDialog<Object?>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('한 달 예산'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: '예산',
                hintText: '예: 300000',
                suffixText: '원',
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '이번 달 사용액이 예산의 80%와 100%를 넘으면 알려드려요. 비워 두면 예산을 없애요.',
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
          ],
        ),
        actions: [dialogButtons(context)],
      ),
    );
    final value = int.tryParse(controller.text);
    controller.dispose();
    if (accepted != true) return;
    await store.setBudget(value);
    await load();
    final alert = await store.budgetAlert();
    if (mounted) await showBudgetAlert(context, alert);
  }

  Future<void> openEntry([LedgerEntry? entry]) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => LedgerEntryPage(
          entry: entry,
          initialDate: isThisMonth ? today : month,
        ),
      ),
    );
    if (changed != true || !mounted) return;
    await load();
    final alert = await store.budgetAlert();
    if (mounted) await showBudgetAlert(context, alert);
  }

  @override
  Widget build(BuildContext context) {
    final monthly = inMonth(entries, month);
    final spent = sumOf(monthly);
    final totals = categoryTotals(monthly);
    return Scaffold(
      appBar: AppBar(title: const Text('내 가계부')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => openEntry(),
        icon: const Icon(Icons.edit_outlined),
        label: const Text('직접 기록'),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 96),
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: '이전 달',
                      icon: const Icon(Icons.chevron_left),
                      onPressed: () => moveMonth(-1),
                    ),
                    Expanded(
                      child: Text(
                        '${month.year}년 ${month.month}월',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '다음 달',
                      icon: const Icon(Icons.chevron_right),
                      onPressed: isThisMonth ? null : () => moveMonth(1),
                    ),
                  ],
                ),
                _SummaryCard(
                  spent: spent,
                  budget: budget,
                  onEditBudget: editBudget,
                ),
                if (totals.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text(
                    '분류별 합계',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  for (final t in totals)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          SizedBox(width: 56, child: Text(t.category)),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: LinearProgressIndicator(
                                value: spent == 0 ? 0 : t.amount / spent,
                                minHeight: 10,
                                backgroundColor: _softColor,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 96,
                            child: Text(
                              money(t.amount),
                              textAlign: TextAlign.right,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                const SizedBox(height: 16),
                const Text('기록', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                if (monthly.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      '이 달의 기록이 없어요.\n정산을 완료하면 내 부담액이 자동으로 기록돼요.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.black54),
                    ),
                  ),
                for (final e in monthly)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: Icon(
                        e.fromRoom
                            ? Icons.groups_outlined
                            : Icons.person_outline,
                      ),
                      title: Text(e.title),
                      subtitle: Text(
                        '${e.date.month}/${e.date.day} · ${e.category}'
                        '${e.fromRoom ? ' · ${e.roomName}' : ''}',
                      ),
                      trailing: Text(
                        money(e.amount),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onTap: () => openEntry(e),
                    ),
                  ),
                const Text(
                  '가계부는 이 기기에만 저장돼요. 앱을 삭제하거나 기기를 바꾸면 사라집니다.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.spent,
    required this.budget,
    required this.onEditBudget,
  });
  final int spent;
  final int? budget;
  final VoidCallback onEditBudget;

  @override
  Widget build(BuildContext context) {
    final level = budgetLevel(spent, budget);
    final ratio = budget == null ? 0.0 : (spent / budget!).clamp(0.0, 1.0);
    return Card(
      elevation: 0,
      color: level == 0 ? _softColor : _warnColor,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('쓴 돈', style: TextStyle(color: Colors.black54)),
            Text(
              money(spent),
              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            if (budget != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 10,
                  color: level == 100 ? _overColor : _okColor,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                level == 100
                    ? '예산 ${money(budget!)}을 ${money(spent - budget!)} 넘었어요.'
                    : '예산 ${money(budget!)} 중 ${spent * 100 ~/ budget!}% 썼어요. '
                          '${money(budget! - spent)} 남았어요.',
                style: TextStyle(
                  color: level == 0 ? Colors.black87 : _overColor,
                  fontWeight: level == 0 ? FontWeight.normal : FontWeight.bold,
                ),
              ),
            ],
            TextButton.icon(
              onPressed: onEditBudget,
              icon: const Icon(Icons.savings_outlined),
              label: Text(budget == null ? '한 달 예산 정하기' : '예산 바꾸기'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 가계부 기록 하나를 만들거나 고친다. 정산에서 온 기록은 분류만 바꾸고,
/// 원래 정산 기록으로 이동할 수 있다. 바뀌면 true를 돌려준다.
class LedgerEntryPage extends StatefulWidget {
  const LedgerEntryPage({super.key, this.entry, required this.initialDate});
  final LedgerEntry? entry;
  final DateTime initialDate;
  @override
  State<LedgerEntryPage> createState() => _LedgerEntryPageState();
}

class _LedgerEntryPageState extends State<LedgerEntryPage> {
  late final title = TextEditingController(text: widget.entry?.title ?? '');
  late final amount = TextEditingController(
    text: widget.entry == null ? '' : '${widget.entry!.amount}',
  );
  late String category = widget.entry?.category ?? '식비';
  late DateTime date = dayOf(widget.entry?.date ?? widget.initialDate);

  bool get fromRoom => widget.entry?.fromRoom ?? false;

  @override
  void dispose() {
    title.dispose();
    amount.dispose();
    super.dispose();
  }

  Future<void> pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => date = dayOf(picked));
  }

  Future<void> save() async {
    final value = int.tryParse(amount.text);
    if (title.text.trim().isEmpty ||
        value == null ||
        value < 1 ||
        value > 100000000) {
      return showFailure(context, StateError('내용과 1원 이상 금액을 입력해주세요.'));
    }
    final entry =
        widget.entry?.copyWith(
          title: fromRoom ? null : title.text.trim(),
          amount: fromRoom ? null : value,
          date: fromRoom ? null : date,
          category: category,
        ) ??
        LedgerEntry(
          id: newId(),
          date: date,
          title: title.text.trim(),
          amount: value,
          category: category,
        );
    await LedgerStore().put(entry);
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> remove() async {
    final accepted = await askConfirm(
      context,
      title: const Text('기록을 지울까요?'),
      content: Text(
        fromRoom ? '가계부에서만 지워요. 정산 기록은 그대로 남아요.' : '이 기기에서 지우면 되돌릴 수 없어요.',
      ),
    );
    if (!accepted) return;
    await LedgerStore().remove(widget.entry!.id);
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> openRecord() async {
    final records = await RecordStore().list();
    final record = records
        .where((r) => r.roomId == widget.entry!.roomId)
        .firstOrNull;
    if (!mounted) return;
    if (record == null) {
      return showFailure(context, StateError('이 기기에서 정산 기록을 찾지 못했어요.'));
    }
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RecordPage(record: record)),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.entry == null ? '직접 기록' : '기록 보기'),
      actions: [
        if (widget.entry != null)
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '기록 지우기',
            onPressed: remove,
          ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        if (fromRoom) ...[
          Card(
            elevation: 0,
            color: _softColor,
            child: ListTile(
              leading: const Icon(Icons.groups_outlined),
              title: Text('${widget.entry!.roomName} 정산에서 온 기록'),
              subtitle: const Text('내가 실제로 부담한 금액이에요. 분류만 바꿀 수 있어요.'),
            ),
          ),
          OutlinedButton.icon(
            onPressed: openRecord,
            icon: const Icon(Icons.receipt_long_outlined),
            label: const Text('정산 기록 보기'),
          ),
          const SizedBox(height: 16),
        ],
        TextField(
          controller: title,
          enabled: !fromRoom,
          maxLength: 40,
          decoration: const InputDecoration(
            labelText: '내용',
            hintText: '예: 점심 김밥',
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: amount,
          enabled: !fromRoom,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: '금액', suffixText: '원'),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: fromRoom ? null : pickDate,
          icon: const Icon(Icons.calendar_today_outlined),
          label: Text('${date.year}년 ${date.month}월 ${date.day}일'),
        ),
        const SizedBox(height: 16),
        const Text('분류', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final c in ledgerCategories)
              ChoiceChip(
                label: Text(c),
                selected: category == c,
                onSelected: (_) => setState(() => category = c),
              ),
          ],
        ),
        const SizedBox(height: 24),
        FilledButton(onPressed: save, child: const Text('저장')),
      ],
    ),
  );
}
