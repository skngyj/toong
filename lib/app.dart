import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data/room_store.dart';
import 'domain/models.dart';
import 'domain/settlement.dart';

const _ink = Color(0xFF213025);
const _lime = Color(0xFFC8EE7D);
const _canvas = Color(0xFFF6F8F3);
const _soft = Color(0xFFECF1E6);

String money(int value) =>
    '${value.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',')}원';

class ToongApp extends StatelessWidget {
  const ToongApp({super.key, required this.store});
  final RoomStore store;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '퉁',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _lime,
        primary: _ink,
        surface: _canvas,
      ),
      scaffoldBackgroundColor: _canvas,
      appBarTheme: const AppBarTheme(
        backgroundColor: _canvas,
        foregroundColor: _ink,
        centerTitle: false,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: _lime,
          foregroundColor: _ink,
          minimumSize: const Size(double.infinity, 54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
    ),
    home: HomePage(store: store),
  );
}

Future<void> showFailure(BuildContext context, Object error) async {
  if (!context.mounted) return;
  final message = error is StateError ? error.message : error.toString();
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('진행할 수 없어요'),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('확인'),
        ),
      ],
    ),
  );
}

Future<bool> guestNotice(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('게스트 이용 안내'),
        content: const Text(
          '앱을 삭제하거나 기기를 바꾸면 이 방의 참여자·방장 권한을 되찾지 못할 수 있어요. 방 코드와 닉네임만으로 기존 권한을 복구할 수 없습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('확인했어요'),
          ),
        ],
      ),
    ) ??
    false;

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.store});
  final RoomStore store;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Spacer(flex: 2),
            const Text(
              '복잡한 정산,\n퉁으로 끝.',
              style: TextStyle(
                fontSize: 38,
                fontWeight: FontWeight.w800,
                height: 1.35,
                letterSpacing: -1.5,
                color: _ink,
              ),
            ),
            const Spacer(flex: 3),
            FilledButton(
              onPressed: () async {
                if (!await guestNotice(context) || !context.mounted) return;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EntryPage(store: store, creating: true),
                  ),
                );
              },
              child: const Text('새방 만들기'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () async {
                if (!await guestNotice(context) || !context.mounted) return;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EntryPage(store: store, creating: false),
                  ),
                );
              },
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 54),
              ),
              child: const Text('방 코드로 입장'),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => RoomListPage(store: store)),
              ),
              child: const Text('참여중인 방 목록'),
            ),
          ],
        ),
      ),
    ),
  );
}

class EntryPage extends StatefulWidget {
  const EntryPage({super.key, required this.store, required this.creating});
  final RoomStore store;
  final bool creating;
  @override
  State<EntryPage> createState() => _EntryPageState();
}

class _EntryPageState extends State<EntryPage> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController();
  final nickname = TextEditingController();
  bool busy = false;

  @override
  void dispose() {
    name.dispose();
    nickname.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    setState(() => busy = true);
    try {
      final room = widget.creating
          ? await widget.store.createRoom(
              name.text.trim(),
              nickname.text.trim(),
            )
          : await widget.store.joinRoom(
              name.text.trim().toUpperCase(),
              nickname.text.trim(),
            );
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => RoomPage(store: widget.store, roomId: room.id),
        ),
      );
    } catch (error) {
      if (mounted) await showFailure(context, error);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.creating ? '새방 만들기' : '방 코드로 입장')),
    body: Form(
      key: form,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            widget.creating ? '오늘의 정산 방을\n만들어볼까요?' : '친구가 기다리는\n방으로 가요.',
            style: Theme.of(context).textTheme.headlineMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 32),
          TextFormField(
            controller: name,
            textCapitalization: widget.creating
                ? TextCapitalization.sentences
                : TextCapitalization.characters,
            maxLength: widget.creating ? 30 : 8,
            decoration: InputDecoration(
              labelText: widget.creating ? '방 이름' : '방 코드',
              hintText: widget.creating ? '금요일 저녁 모임' : '예: ABC2345',
            ),
            validator: (v) => (v?.trim().isEmpty ?? true) ? '입력해주세요.' : null,
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: nickname,
            maxLength: 12,
            decoration: const InputDecoration(
              labelText: '내 닉네임',
              hintText: '친구들이 알아볼 이름',
            ),
            validator: (v) =>
                (v?.trim().isEmpty ?? true) ? '닉네임을 입력해주세요.' : null,
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: busy ? null : submit,
            child: Text(
              busy
                  ? '잠시만요…'
                  : widget.creating
                  ? '방 만들기'
                  : '입장하기',
            ),
          ),
        ],
      ),
    ),
  );
}

class RoomListPage extends StatefulWidget {
  const RoomListPage({super.key, required this.store});
  final RoomStore store;
  @override
  State<RoomListPage> createState() => _RoomListPageState();
}

class _RoomListPageState extends State<RoomListPage> {
  late Future<List<Room>> future;
  @override
  void initState() {
    super.initState();
    future = widget.store.listRooms();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('참여중인 방 목록')),
    body: FutureBuilder<List<Room>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('목록을 불러오지 못했어요.\n${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final rooms = snapshot.data!;
        if (rooms.isEmpty) return const Center(child: Text('아직 참여한 방이 없어요.'));
        return ListView(
          padding: const EdgeInsets.all(20),
          children: rooms
              .map(
                (r) => Card(
                  child: ListTile(
                    title: Text(r.name),
                    subtitle: Text(
                      '${r.members.length}명 · 지출 ${r.expenses.length}건',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            RoomPage(store: widget.store, roomId: r.id),
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        );
      },
    ),
  );
}

class RoomPage extends StatefulWidget {
  const RoomPage({super.key, required this.store, required this.roomId});
  final RoomStore store;
  final String roomId;
  @override
  State<RoomPage> createState() => _RoomPageState();
}

class _RoomPageState extends State<RoomPage> {
  Room? room;
  String? actor;
  bool loading = true;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    refresh();
    if (widget.store.isCloud) {
      timer = Timer.periodic(
        const Duration(seconds: 10),
        (_) => refresh(silent: true),
      );
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> refresh({bool silent = false}) async {
    try {
      final current = await widget.store.getRoom(widget.roomId);
      final id = await widget.store.actorId();
      if (mounted) {
        setState(() {
          room = current;
          actor = id;
          loading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => loading = false);
        if (!silent) await showFailure(context, error);
      }
    }
  }

  Future<void> open(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    if (mounted) await refresh();
  }

  Future<void> copyRoom() async {
    final r = room!;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('정산을 복제할까요?'),
        content: const Text(
          '원래 방은 그대로 두고 새 코드의 방을 만듭니다. 복제한 사람이 새 방장이 되며, 과거 참여자의 지출 기록은 유지됩니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('복제하기'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    try {
      final copy = await widget.store.cloneRoom(r);
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RoomPage(store: widget.store, roomId: copy.id),
        ),
      );
    } catch (error) {
      if (mounted) await showFailure(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = room;
    final owner = r != null && actor != null && r.owns(actor!);
    return Scaffold(
      appBar: AppBar(
        title: Text(r?.name ?? '방'),
        actions: [
          if (r != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '새로고침',
              onPressed: refresh,
            ),
        ],
      ),
      body: loading || r == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('방 코드'),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                r.code,
                                style: const TextStyle(
                                  fontSize: 26,
                                  letterSpacing: 3,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () async {
                                await Clipboard.setData(
                                  ClipboardData(text: r.code),
                                );
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('방 코드를 복사했어요.'),
                                    ),
                                  );
                                }
                              },
                              icon: const Icon(Icons.copy),
                              tooltip: '방 코드 복사',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: r.members
                      .map(
                        (m) => Chip(
                          label: Text(
                            '${m.name}${m.id == r.ownerMemberId ? ' · 방장' : ''}${m.actorId == null ? ' · 미연결' : ''}',
                          ),
                        ),
                      )
                      .toList(),
                ),
                if (owner && r.members.any((m) => m.actorId == null))
                  TextButton.icon(
                    onPressed: () =>
                        open(LinkMemberPage(store: widget.store, room: r)),
                    icon: const Icon(Icons.link),
                    label: const Text('과거 참여자 기록 연결'),
                  ),
                const SizedBox(height: 22),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('함께 쓴 금액'),
                        Text(
                          money(r.total),
                          style: const TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  '지출 내역 · ${r.expenses.length}건',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (r.expenses.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(child: Text('아직 등록된 지출이 없어요.')),
                  ),
                for (final expense in r.expenses)
                  Card(
                    child: ListTile(
                      title: Text(expense.title),
                      subtitle: Text(
                        '${r.memberName(expense.payerId)} 결제 · ${expense.items.length}개 항목',
                      ),
                      trailing: Text(
                        money(expense.total),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onTap: owner
                          ? () => open(
                              ExpensePage(
                                store: widget.store,
                                room: r,
                                original: expense,
                              ),
                            )
                          : null,
                    ),
                  ),
                const SizedBox(height: 12),
                if (owner)
                  OutlinedButton.icon(
                    onPressed: () =>
                        open(ExpensePage(store: widget.store, room: r)),
                    icon: const Icon(Icons.add),
                    label: const Text('지출 추가'),
                  ),
                if (!owner) const Text('지출과 잔돈 부담자는 방장이 입력할 수 있어요.'),
                const SizedBox(height: 20),
                if (r.pendingRemainder > 0)
                  Text(
                    '남은 잔돈 ${money(r.pendingRemainder)}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: r.expenses.isEmpty
                      ? null
                      : () => open(
                          r.pendingRemainder > 0
                              ? RemainderPage(
                                  store: widget.store,
                                  room: r,
                                  canEdit: owner,
                                )
                              : SettlementPage(room: r),
                        ),
                  child: const Text('정산 결과 보기'),
                ),
                const SizedBox(height: 22),
                TextButton.icon(
                  onPressed: copyRoom,
                  icon: const Icon(Icons.copy_all),
                  label: const Text('이 방의 정산 복제하기'),
                ),
                if (!widget.store.isCloud)
                  const Padding(
                    padding: EdgeInsets.only(top: 18),
                    child: Text(
                      '체험 모드 · 이 기기에만 저장됩니다. 다른 기기와 연결하려면 서버 설정이 필요해요.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _ItemDraft {
  _ItemDraft({
    required this.id,
    required String name,
    required int amount,
    required this.memberIds,
    this.remainderMemberId,
  }) : name = TextEditingController(text: name),
       amount = TextEditingController(text: amount == 0 ? '' : '$amount');
  final String id;
  final TextEditingController name;
  final TextEditingController amount;
  final Set<String> memberIds;
  String? remainderMemberId;

  void dispose() {
    name.dispose();
    amount.dispose();
  }
}

class ExpensePage extends StatefulWidget {
  const ExpensePage({
    super.key,
    required this.store,
    required this.room,
    this.original,
  });
  final RoomStore store;
  final Room room;
  final Expense? original;
  @override
  State<ExpensePage> createState() => _ExpensePageState();
}

class _ExpensePageState extends State<ExpensePage> {
  late final TextEditingController title;
  late String payerId;
  final List<_ItemDraft> items = [];
  bool busy = false;

  @override
  void initState() {
    super.initState();
    title = TextEditingController(text: widget.original?.title ?? '');
    payerId = widget.original?.payerId ?? widget.room.ownerMemberId;
    if (widget.original != null) {
      for (final item in widget.original!.items) {
        items.add(
          _ItemDraft(
            id: item.id,
            name: item.name,
            amount: item.amount,
            memberIds: item.memberIds.toSet(),
            remainderMemberId: item.remainderMemberId,
          ),
        );
      }
    } else {
      items.add(_ItemDraft(id: newId(), name: '', amount: 0, memberIds: {}));
    }
  }

  @override
  void dispose() {
    title.dispose();
    for (final item in items) {
      item.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (title.text.trim().isEmpty || items.isEmpty) {
      return showFailure(context, StateError('지출 이름과 항목을 입력해주세요.'));
    }
    final built = <LineItem>[];
    for (final draft in items) {
      final amount = int.tryParse(draft.amount.text.replaceAll(',', '').trim());
      if (draft.name.text.trim().isEmpty ||
          amount == null ||
          amount < 1 ||
          amount > 100000000 ||
          draft.memberIds.isEmpty) {
        return showFailure(
          context,
          StateError('각 항목의 이름, 1원 이상 금액, 부담자를 확인해주세요.'),
        );
      }
      final selected = widget.room.members
          .where((m) => draft.memberIds.contains(m.id))
          .map((m) => m.id)
          .toList();
      final unchanged = widget.original?.items
          .where((i) => i.id == draft.id)
          .firstOrNull;
      final keepRemainder =
          unchanged != null &&
          unchanged.amount == amount &&
          unchanged.memberIds.join('|') == selected.join('|');
      built.add(
        LineItem(
          id: draft.id,
          name: draft.name.text.trim(),
          amount: amount,
          memberIds: selected,
          remainderMemberId: keepRemainder ? unchanged.remainderMemberId : null,
        ),
      );
    }
    final expense = Expense(
      id: widget.original?.id ?? newId(),
      title: title.text.trim(),
      payerId: payerId,
      items: built,
    );
    final expenses = [...widget.room.expenses];
    final index = expenses.indexWhere((e) => e.id == expense.id);
    if (index < 0) {
      expenses.add(expense);
    } else {
      expenses[index] = expense;
    }
    setState(() => busy = true);
    try {
      await widget.store.saveRoom(widget.room.copyWith(expenses: expenses));
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) await showFailure(context, error);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.original == null ? '지출 추가' : '지출 수정')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        const Text('메뉴와 금액을 직접 입력해주세요.'),
        const SizedBox(height: 18),
        TextField(
          controller: title,
          maxLength: 40,
          decoration: const InputDecoration(
            labelText: '장소 또는 지출 이름',
            hintText: '예: 저녁 식사',
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: payerId,
          decoration: const InputDecoration(labelText: '결제한 사람'),
          items: widget.room.members
              .map((m) => DropdownMenuItem(value: m.id, child: Text(m.name)))
              .toList(),
          onChanged: (value) {
            if (value != null) setState(() => payerId = value);
          },
        ),
        const SizedBox(height: 20),
        for (var index = 0; index < items.length; index++) _itemCard(index),
        OutlinedButton.icon(
          onPressed: () => setState(
            () => items.add(
              _ItemDraft(id: newId(), name: '', amount: 0, memberIds: {}),
            ),
          ),
          icon: const Icon(Icons.add),
          label: const Text('항목 추가'),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: busy ? null : save,
          child: Text(busy ? '저장 중…' : '저장하고 방으로'),
        ),
      ],
    ),
  );

  Widget _itemCard(int index) {
    final item = items[index];
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '항목 ${index + 1}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: '항목 삭제',
                  onPressed: () => setState(() {
                    items.removeAt(index);
                    item.dispose();
                  }),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: item.name,
              decoration: const InputDecoration(
                labelText: '메뉴 또는 이용 내역',
                hintText: '예: 치킨',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: item.amount,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: '항목 총액 (원)',
                hintText: '24000',
              ),
            ),
            const SizedBox(height: 16),
            const Text('먹거나 이용한 사람'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: widget.room.members
                  .map(
                    (m) => FilterChip(
                      label: Text(m.name),
                      selected: item.memberIds.contains(m.id),
                      onSelected: (selected) => setState(() {
                        if (selected) {
                          item.memberIds.add(m.id);
                        } else {
                          item.memberIds.remove(m.id);
                        }
                        item.remainderMemberId = null;
                      }),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class RemainderPage extends StatefulWidget {
  const RemainderPage({
    super.key,
    required this.store,
    required this.room,
    required this.canEdit,
  });
  final RoomStore store;
  final Room room;
  final bool canEdit;
  @override
  State<RemainderPage> createState() => _RemainderPageState();
}

class _RemainderPageState extends State<RemainderPage> {
  late Room room;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    room = widget.room;
  }

  Future<void> assign(String expenseId, String itemId, String memberId) async {
    if (!widget.canEdit) return;
    setState(() => busy = true);
    try {
      final expenses = room.expenses
          .map(
            (expense) => expense.id != expenseId
                ? expense
                : Expense(
                    id: expense.id,
                    title: expense.title,
                    payerId: expense.payerId,
                    items: expense.items
                        .map(
                          (item) => item.id != itemId
                              ? item
                              : item.copyWith(remainderMemberId: memberId),
                        )
                        .toList(),
                  ),
          )
          .toList();
      final saved = await widget.store.saveRoom(
        room.copyWith(expenses: expenses),
      );
      if (!mounted) return;
      setState(() => room = saved);
    } catch (error) {
      if (mounted) await showFailure(context, error);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = <({Expense expense, LineItem item})>[];
    for (final expense in room.expenses) {
      for (final item in expense.items) {
        if (item.needsRemainder) pending.add((expense: expense, item: item));
      }
    }
    return Scaffold(
      appBar: AppBar(title: const Text('남은 잔돈 정하기')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
        children: [
          Text(
            pending.isEmpty
                ? '잔돈 지정 완료'
                : '남은 잔돈 ${money(room.pendingRemainder)}',
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            widget.canEdit
                ? '각 항목의 잔돈을 부담할 사람을 골라주세요.'
                : '방장이 잔돈 부담자를 지정하면 정산 결과를 볼 수 있어요.',
          ),
          const SizedBox(height: 20),
          for (final entry in pending)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.expense.title,
                      style: const TextStyle(color: Colors.black54),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${entry.item.name} · ${money(entry.item.remainder)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (widget.canEdit)
                      Wrap(
                        spacing: 8,
                        children: entry.item.memberIds
                            .map(
                              (id) => ActionChip(
                                label: Text(room.memberName(id)),
                                onPressed: busy
                                    ? null
                                    : () => assign(
                                        entry.expense.id,
                                        entry.item.id,
                                        id,
                                      ),
                              ),
                            )
                            .toList(),
                      ),
                  ],
                ),
              ),
            ),
          if (pending.isEmpty)
            FilledButton(
              onPressed: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => SettlementPage(room: room)),
              ),
              child: const Text('최종 정산 보기'),
            ),
          if (!widget.canEdit && pending.isNotEmpty)
            OutlinedButton(
              onPressed: () async {
                final fresh = await widget.store.getRoom(room.id);
                if (mounted) setState(() => room = fresh);
              },
              child: const Text('새로고침'),
            ),
        ],
      ),
    );
  }
}

class SettlementPage extends StatelessWidget {
  const SettlementPage({super.key, required this.room});
  final Room room;

  @override
  Widget build(BuildContext context) {
    if (room.pendingRemainder > 0) {
      return Scaffold(
        appBar: AppBar(title: const Text('정산 결과')),
        body: const Center(child: Text('잔돈 부담자를 먼저 지정해주세요.')),
      );
    }
    final result = calculateSettlement(room);
    return Scaffold(
      appBar: AppBar(title: const Text('정산 결과')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
        children: [
          const Text(
            '이렇게 보내면\n정산 끝.',
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.bold,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 24),
          if (result.transfers.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('주고받을 돈이 없어요. 이미 셈셈!'),
              ),
            ),
          for (final transfer in result.transfers)
            Card(
              color: _soft,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${room.memberName(transfer.from)}  →  ${room.memberName(transfer.to)}',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      money(transfer.amount),
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 10),
          const Text(
            '송금은 사용 중인 은행 앱에서 진행해주세요.',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 24),
          ExpansionTile(
            title: const Text('개인별 계산 내역'),
            children: room.members
                .map(
                  (m) => ListTile(
                    title: Text(m.name),
                    subtitle: Text(
                      '결제 ${money(result.paid[m.id]!)} · 부담 ${money(result.owed[m.id]!)}',
                    ),
                    trailing: Text(
                      '${result.balance[m.id]! >= 0 ? '+' : ''}${money(result.balance[m.id]!)}',
                    ),
                  ),
                )
                .toList(),
          ),
          if (room.members.any((m) => m.actorId == null))
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: Text(
                '미연결 과거 참여자가 포함돼 있어요. 송금 대상과 금액을 확인해주세요.',
                style: TextStyle(color: Colors.black54),
              ),
            ),
        ],
      ),
    );
  }
}

class LinkMemberPage extends StatefulWidget {
  const LinkMemberPage({super.key, required this.store, required this.room});
  final RoomStore store;
  final Room room;
  @override
  State<LinkMemberPage> createState() => _LinkMemberPageState();
}

class _LinkMemberPageState extends State<LinkMemberPage> {
  late Room room;
  @override
  void initState() {
    super.initState();
    room = widget.room;
  }

  @override
  Widget build(BuildContext context) {
    final historical = room.members.where((m) => m.actorId == null).toList();
    final joined = room.members
        .where((m) => m.actorId != null && m.id != room.ownerMemberId)
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('과거 참여자 기록 연결')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            '새 방에 다시 들어온 친구를 과거 기록의 사람과 연결할 수 있어요. 연결되지 않아도 과거 금액은 정산에 남습니다.',
          ),
          const SizedBox(height: 20),
          if (joined.isEmpty) const Text('새 코드로 다시 들어온 친구가 아직 없어요.'),
          for (final member in historical)
            Card(
              child: ListTile(
                title: Text(member.name),
                subtitle: const Text('과거 기록 · 미연결'),
                trailing: PopupMenuButton<String>(
                  tooltip: '연결할 사람 선택',
                  enabled: joined.isNotEmpty,
                  onSelected: (id) async {
                    try {
                      final result = await widget.store.linkMember(
                        room,
                        member.id,
                        id,
                      );
                      if (mounted) setState(() => room = result);
                    } catch (error) {
                      if (context.mounted) await showFailure(context, error);
                    }
                  },
                  itemBuilder: (_) => joined
                      .map(
                        (m) => PopupMenuItem(value: m.id, child: Text(m.name)),
                      )
                      .toList(),
                ),
              ),
            ),
          OutlinedButton(
            onPressed: () async {
              try {
                final fresh = await widget.store.getRoom(room.id);
                if (mounted) setState(() => room = fresh);
              } catch (error) {
                if (context.mounted) await showFailure(context, error);
              }
            },
            child: const Text('참여자 새로고침'),
          ),
        ],
      ),
    );
  }
}
