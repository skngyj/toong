import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import 'data/ledger_store.dart';
import 'data/record_store.dart';
import 'data/room_store.dart';
import 'domain/draw.dart';
import 'domain/models.dart';
import 'domain/receipt.dart';
import 'domain/record.dart';
import 'domain/settlement.dart';
import 'freeze_effect.dart';
import 'ledger_page.dart';
import 'qr_page.dart';
import 'receipt_view.dart';
import 'theme.dart';

const _ink = toongInk;
const _soft = toongSoft;
const _danger = toongDanger;

String money(int value) =>
    '${value.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',')}원';

class ToongApp extends StatefulWidget {
  const ToongApp({super.key, required this.store, this.links});
  final RoomStore store;

  /// 앱을 연 방 링크(`toong://join/코드`)가 들어오는 스트림.
  final Stream<Uri>? links;

  @override
  State<ToongApp> createState() => _ToongAppState();
}

class _ToongAppState extends State<ToongApp> {
  final navigator = GlobalKey<NavigatorState>();
  StreamSubscription<Uri>? subscription;

  RoomStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    subscription = widget.links?.listen(openLink);
  }

  @override
  void dispose() {
    subscription?.cancel();
    super.dispose();
  }

  /// 방 링크로 들어오면 이미 참여한 방은 바로 열고, 아니면 닉네임만 묻는다.
  Future<void> openLink(Uri uri) async {
    final code = codeFromLink(uri);
    if (code == null) return;
    // 앱이 링크로 처음 켜졌을 때는 첫 화면이 그려진 뒤에 이동한다.
    await WidgetsBinding.instance.endOfFrame;
    Room? joined;
    try {
      joined = (await store.listRooms())
          .where((r) => r.code == code)
          .firstOrNull;
    } catch (_) {
      // 목록을 못 불러와도 입장 화면에서 다시 시도할 수 있다.
    }
    final context = navigator.currentContext;
    if (context == null || !context.mounted) return;
    if (joined != null) {
      navigator.currentState!.push(
        MaterialPageRoute(
          builder: (_) => RoomPage(store: store, roomId: joined!.id),
        ),
      );
      return;
    }
    if (!await guestNotice(context)) return;
    navigator.currentState?.push(
      MaterialPageRoute(
        builder: (_) =>
            EntryPage(store: store, creating: false, initialCode: code),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: navigator,
    title: '퉁',
    debugShowCheckedModeBanner: false,
    theme: toongTheme(),
    // 화면 아래 시스템 내비게이션 바(제스처 바·버튼)에 내용이 가리지 않게 한다.
    // Android 15부터는 앱이 화면 맨 아래까지 그려지므로 모든 화면에 아래 여백을 둔다.
    builder: (context, child) => ColoredBox(
      color: toongCanvas,
      child: SafeArea(
        top: false,
        left: false,
        right: false,
        child: child ?? const SizedBox.shrink(),
      ),
    ),
    home: HomePage(store: store),
  );
}

/// 확인·취소를 묻는 창. 두 버튼은 같은 크기로 확인을 왼쪽, 취소를 오른쪽에 놓고, 취소는 빨간 버튼이다.
Future<bool> askConfirm(
  BuildContext context, {
  required Widget title,
  required Widget content,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: title,
        content: content,
        actions: [dialogButtons(context)],
      ),
    ) ??
    false;

/// 창 아래의 "확인 / 취소" 버튼 한 줄. 취소는 [cancelValue](기본 false)를, 확인은
/// [confirmValue]가 있으면 그 값을, 없으면 true를 돌려주며 닫는다.
/// [canConfirm]이 false면 확인을 누를 수 없다.
Widget dialogButtons(
  BuildContext context, {
  Object? Function()? confirmValue,
  Object? cancelValue = false,
  bool canConfirm = true,
}) => Row(
  children: [
    Expanded(
      child: FilledButton(
        onPressed: canConfirm
            ? () => Navigator.pop(context, confirmValue?.call() ?? true)
            : null,
        child: const Text('확인'),
      ),
    ),
    const SizedBox(width: 12),
    Expanded(
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: _danger,
          foregroundColor: Colors.white,
        ),
        onPressed: () => Navigator.pop(context, cancelValue),
        child: const Text('취소'),
      ),
    ),
  ],
);

/// 글자 하나를 입력받는 창. 확인하면 입력한 글자(앞뒤 공백 제거)를, 취소하면 null을 돌려준다.
Future<String?> askText(
  BuildContext context, {
  required String title,
  required String label,
  String? hint,
  String? help,
  String initial = '',
  int? maxLength,
  String? suffix,
  bool digitsOnly = false,
}) => showDialog<String>(
  context: context,
  builder: (_) => _TextDialog(
    title: title,
    label: label,
    hint: hint,
    help: help,
    initial: initial,
    maxLength: maxLength,
    suffix: suffix,
    digitsOnly: digitsOnly,
  ),
);

/// [askText]의 창. 입력 칸의 컨트롤러를 창이 완전히 닫힌 뒤에 정리하도록 직접 가진다.
class _TextDialog extends StatefulWidget {
  const _TextDialog({
    required this.title,
    required this.label,
    required this.initial,
    required this.digitsOnly,
    this.hint,
    this.help,
    this.maxLength,
    this.suffix,
  });
  final String title;
  final String label;
  final String? hint;
  final String? help;
  final String initial;
  final int? maxLength;
  final String? suffix;
  final bool digitsOnly;
  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            autofocus: true,
            maxLength: widget.maxLength,
            keyboardType: widget.digitsOnly ? TextInputType.number : null,
            inputFormatters: widget.digitsOnly
                ? [FilteringTextInputFormatter.digitsOnly]
                : null,
            decoration: InputDecoration(
              labelText: widget.label,
              hintText: widget.hint,
              suffixText: widget.suffix,
            ),
          ),
          if (widget.help != null)
            Text(
              widget.help!,
              style: const TextStyle(fontSize: 13, color: toongSub),
            ),
        ],
      ),
    ),
    actions: [
      dialogButtons(
        context,
        confirmValue: () => controller.text.trim(),
        cancelValue: null,
      ),
    ],
  );
}

/// 아직 송금 완료로 체크하지 않은 송금 수. 잔돈 부담자가 정해지지 않아 정산을 계산할 수
/// 없으면 0(완료 자체가 막히므로 따로 묻지 않는다).
int unpaidTransfers(Room room) {
  if (room.pendingRemainder > 0 || room.expenses.isEmpty) return 0;
  try {
    return calculateSettlement(room).transfers
        .where((t) => !room.isPaid(t.from, t.to, t.amount))
        .length;
  } on StateError {
    return 0;
  }
}

/// 완료된 방을 이 기기에 남긴다. 정산 기록을 저장하고, 내 부담액을 가계부에
/// 지출 한 건당 한 줄로 넣는다. 그 때문에 이번 달 예산 단계를 넘었으면 알림 문구를 돌려준다.
Future<String?> keepCompleted(RoomStore store, Room room) async {
  if (!room.isCompleted) return null;
  await RecordStore().keep(room);
  final ledger = LedgerStore();
  if (!await ledger.importRoom(room, await store.actorId())) return null;
  return ledger.budgetAlert();
}

Future<void> showFailure(BuildContext context, Object error) async {
  if (!context.mounted) return;
  final message = switch (error) {
    StateError(:final message) => message,
    PostgrestException(:final message) => message,
    _ => error.toString(),
  };
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('진행할 수 없어요'),
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

Future<bool> guestNotice(BuildContext context) async => await askConfirm(
  context,
  title: const Text('게스트 이용 안내'),
  content: const Text(
    '앱을 삭제하거나 기기를 바꾸면 이 방의 참여자·방장 권한을 되찾지 못할 수 있어요. 방 코드와 닉네임만으로 기존 권한을 복구할 수 없습니다.\n\n$roomExpiryNotice',
  ),
);

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
            // 앱 아이콘과 같은 4조각 '퉁' 로고.
            Align(
              alignment: Alignment.centerLeft,
              child: Image.asset(
                'assets/logo.png',
                width: 64,
                height: 64,
                semanticLabel: '퉁 로고',
              ),
            ),
            const SizedBox(height: 22),
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
            TextButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const LedgerPage()),
              ),
              icon: const Icon(Icons.account_balance_wallet_outlined),
              label: const Text('내 가계부'),
            ),
          ],
        ),
      ),
    ),
  );
}

class EntryPage extends StatefulWidget {
  const EntryPage({
    super.key,
    required this.store,
    required this.creating,
    this.initialCode,
  });
  final RoomStore store;
  final bool creating;

  /// 방 링크로 들어왔을 때 미리 채워 둘 방 코드.
  final String? initialCode;
  @override
  State<EntryPage> createState() => _EntryPageState();
}

class _EntryPageState extends State<EntryPage> {
  final form = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.initialCode);
  final nickname = TextEditingController();
  final nicknameFocus = FocusNode();
  bool busy = false;

  @override
  void dispose() {
    name.dispose();
    nickname.dispose();
    nicknameFocus.dispose();
    super.dispose();
  }

  /// 친구 휴대폰의 방 QR을 찍어 방 코드를 채운다. 입장은 닉네임을 넣고 직접 누른다.
  Future<void> scan() async {
    final code = await scanRoomQr(context);
    if (code == null || !mounted) return;
    setState(() => name.text = code);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('QR에서 방 코드 $code를 읽었어요. 닉네임을 넣고 입장하세요.')),
    );
    if (nickname.text.trim().isEmpty) nicknameFocus.requestFocus();
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
              suffixIcon: widget.creating
                  ? null
                  : IconButton(
                      onPressed: scan,
                      tooltip: 'QR 스캔',
                      icon: const Icon(Icons.qr_code_scanner),
                    ),
            ),
            validator: (v) => (v?.trim().isEmpty ?? true) ? '입력해주세요.' : null,
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: nickname,
            focusNode: nicknameFocus,
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
  late Future<
    ({List<Room> rooms, List<SettlementRecord> records, String actor})
  >
  future;
  @override
  void initState() {
    super.initState();
    future = load();
  }

  /// 진행 중인 방과 이 기기에 저장된 완료 기록을 함께 불러온다.
  /// 완료된 방은 서버에서 지워지기 전에 기록으로 저장해 둔다.
  Future<({List<Room> rooms, List<SettlementRecord> records, String actor})>
  load() async {
    final records = RecordStore();
    final rooms = await widget.store.listRooms();
    String? alert;
    for (final room in rooms) {
      alert = await keepCompleted(widget.store, room) ?? alert;
    }
    if (alert != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => showBudgetAlert(context, alert),
      );
    }
    return (
      rooms: rooms.where((r) => !r.isCompleted).toList(),
      records: await records.list(),
      actor: await widget.store.actorId(),
    );
  }

  /// 방장이 방을 바로 삭제한다. 참여자 모두의 목록에서 사라진다.
  Future<void> delete(Room room) async {
    final accepted = await askConfirm(
      context,
      title: const Text('방을 삭제할까요?'),
      content: Text('「${room.name}」 방과 지출 내역이 모든 참여자에게서 사라져요. 되돌릴 수 없습니다.'),
    );
    if (!accepted || !mounted) return;
    try {
      await widget.store.deleteRoom(room);
      if (!mounted) return;
      setState(() {
        future = load();
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('방을 삭제했어요.')));
    } catch (error) {
      if (mounted) await showFailure(context, error);
    }
  }

  Future<void> open(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    if (!mounted) return;
    setState(() {
      future = load();
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('참여중인 방 목록')),
    body: FutureBuilder(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('목록을 불러오지 못했어요.\n${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final (:rooms, :records, :actor) = snapshot.data!;
        if (rooms.isEmpty && records.isEmpty) {
          return const Center(child: Text('아직 참여한 방이 없어요.'));
        }
        final now = DateTime.now();
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (rooms.isNotEmpty) const _SectionTitle('진행 중인 방'),
            for (final r in rooms)
              Card(
                child: ListTile(
                  leading: r.isFrozen ? const Icon(Icons.ac_unit) : null,
                  title: Text(r.name),
                  subtitle: Text(
                    '${r.members.length}명 · 지출 ${r.expenses.length}건 · '
                    '${r.isFrozen ? '얼림 · ' : ''}'
                    '삭제까지 ${formatRemaining(r.remainingAt(now))}',
                  ),
                  trailing: r.owns(actor)
                      ? IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: '방 삭제',
                          onPressed: () => delete(r),
                        )
                      : const Icon(Icons.chevron_right),
                  onTap: () =>
                      open(RoomPage(store: widget.store, roomId: r.id)),
                ),
              ),
            if (records.isNotEmpty) ...[
              if (rooms.isNotEmpty) const SizedBox(height: 16),
              const _SectionTitle('완료된 정산 기록'),
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  '이 기기에만 저장돼 있어요. 앱을 삭제하거나 기기를 바꾸면 사라집니다.',
                  style: TextStyle(fontSize: 13, color: toongSub),
                ),
              ),
            ],
            for (final record in records)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.receipt_long),
                  title: Text(record.name),
                  subtitle: Text('${formatDay(record.completedAt)} 완료'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => open(RecordPage(record: record)),
                ),
              ),
          ],
        );
      },
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );
}

String formatDay(DateTime time) {
  final t = time.toLocal();
  return '${t.year}.${t.month}.${t.day}';
}

/// 기기에 저장된 완료 정산 기록. 서버 방이 삭제된 뒤에도 볼 수 있다.
/// 영수증 모양으로 보여주고, 영수증을 그대로 찍어 사진 앱에 저장할 수 있다.
class RecordPage extends StatefulWidget {
  const RecordPage({super.key, required this.record});
  final SettlementRecord record;
  @override
  State<RecordPage> createState() => _RecordPageState();
}

class _RecordPageState extends State<RecordPage> {
  final receipt = GlobalKey<CapturableReceiptState>();
  bool saving = false;

  SettlementRecord get record => widget.record;

  Future<void> remove() async {
    final accepted = await askConfirm(
      context,
      title: const Text('기록을 지울까요?'),
      content: const Text('이 기기에서 지우면 되돌릴 수 없어요.'),
    );
    if (accepted != true) return;
    await RecordStore().remove(record.roomId);
    if (mounted) Navigator.pop(context);
  }

  Future<void> saveImage() async {
    setState(() => saving = true);
    await saveReceiptImage(
      context,
      receipt,
      receiptFileName(record.name, record.completedAt),
    );
    if (mounted) setState(() => saving = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: toongSoft,
    appBar: AppBar(
      backgroundColor: toongSoft,
      title: const Text('정산 기록'),
      actions: [
        IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: '기록 지우기',
          onPressed: remove,
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 28),
      children: [
        // 완료된 정산은 영수증 모양으로 보여준다. 예전 기록은 저장된 글자로 그린다.
        CapturableReceipt(
          key: receipt,
          child: ReceiptPaper(
            child: record.room != null
                ? ReceiptContent(room: record.room!)
                : ReceiptTextContent(text: record.text),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Column(
            children: [
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: saving ? null : saveImage,
                icon: const Icon(Icons.download_outlined),
                label: Text(saving ? '저장 중…' : '영수증 이미지 저장'),
              ),
              const SizedBox(height: 4),
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: record.text));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('정산 기록을 글자로 복사했어요.')),
                    );
                  }
                },
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('글자로 복사'),
              ),
            ],
          ),
        ),
      ],
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
  Timer? ticker;

  @override
  void initState() {
    super.initState();
    refresh();
    // 삭제까지 남은 시간 표시를 갱신한다.
    ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
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
    ticker?.cancel();
    super.dispose();
  }

  Future<void> refresh({bool silent = false}) async {
    try {
      final current = await widget.store.getRoom(widget.roomId);
      final id = await widget.store.actorId();
      // 완료된 방은 서버에서 지워지기 전에 이 기기에 기록으로 남기고 가계부에 넣는다.
      final alert = await keepCompleted(widget.store, current);
      if (mounted) {
        setState(() {
          room = current;
          actor = id;
          loading = false;
        });
        await showBudgetAlert(context, alert);
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
    final accepted = await askConfirm(
      context,
      title: const Text('정산을 복제할까요?'),
      content: const Text(
        '원래 방은 그대로 두고 새 코드의 방을 만듭니다. 복제한 사람이 새 방장이 되며, 과거 참여자의 지출 기록은 유지됩니다.',
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

  /// 연장·얼리기·녹이기·완료처럼 방 상태를 바꾸는 방장 동작을 실행한다.
  Future<void> act(Future<Room> Function(Room room) action, String done) async {
    try {
      final updated = await action(room!);
      final alert = await keepCompleted(widget.store, updated);
      if (!mounted) return;
      setState(() => room = updated);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
      await showBudgetAlert(context, alert);
    } catch (error) {
      if (mounted) await showFailure(context, error);
    }
  }

  /// 방장이 정산할 사람을 이름으로 추가한다. 앱을 쓰지 않는 친구도 넣을 수 있다.
  Future<void> addMember() async {
    final name = await askText(
      context,
      title: '사람 추가',
      label: '이름',
      hint: '정산에 넣을 친구 이름',
      maxLength: 12,
      help:
          '앱을 쓰지 않는 친구도 넣을 수 있어요. 그 친구가 나중에 방에 들어오면 '
          '‘과거 참여자 기록 연결’로 합칠 수 있어요.',
    );
    if (name == null || name.isEmpty || !mounted) return;
    await act((room) => widget.store.addMember(room, name), '$name 님을 추가했어요.');
  }

  /// 방장이 참여자를 뺀다. 지출에 들어간 사람은 먼저 지출에서 빼야 한다.
  Future<void> removeMember(Member member) async {
    final r = room!;
    if (r.usesMember(member.id)) {
      return showFailure(
        context,
        StateError('${member.name} 님이 들어간 지출이 있어 뺄 수 없어요. 먼저 지출에서 빼주세요.'),
      );
    }
    if (!await confirm(
      '${member.name} 님을 뺄까요?',
      member.actorId == null
          ? '정산 인원에서 빠져요.'
          : '정산 인원에서 빠지고, ${member.name} 님은 이 방을 더 볼 수 없어요. '
                '방 코드로 다시 들어올 수는 있어요.',
    )) {
      return;
    }
    await act(
      (room) => widget.store.removeMember(room, member.id),
      '${member.name} 님을 뺐어요.',
    );
  }

  Future<bool> confirm(String title, String body) async =>
      await askConfirm(context, title: Text(title), content: Text(body));

  Future<void> freeze() async {
    if (!await confirm(
      '방을 얼릴까요?',
      '얼린 동안에는 삭제 시간이 멈추고, 지출 입력과 새 참여자 입장도 멈춰요. '
          '얼린 방은 ${roomFreezeLimit.inDays}일 안에 녹이지 않으면 삭제됩니다. '
          '방은 동시에 $roomFreezeSlots개까지 얼릴 수 있어요.',
    )) {
      return;
    }
    await act(widget.store.freezeRoom, '방을 얼렸어요.');
  }

  Future<void> complete() async {
    if (!await confirm(
      '정산을 완료할까요?',
      '완료하면 더 이상 수정할 수 없어요. 방은 ${roomCompletedLimit.inHours}시간 뒤 '
          '삭제되고, 정산 기록은 각자 기기에 저장됩니다. 친구들은 '
          '${roomCompletedLimit.inHours}시간 안에 이 방을 열어야 기록이 저장돼요.',
    )) {
      return;
    }
    // 아직 송금 완료로 체크하지 않은 송금이 있으면 한 번 더 묻는다.
    final unpaid = unpaidTransfers(room!);
    if (unpaid > 0 &&
        mounted &&
        !await confirm(
          '아직 체크하지 않은 송금이 있어요',
          '송금 완료로 체크하지 않은 송금이 $unpaid건 있어요. 그래도 정산을 완료할까요? '
              '완료한 뒤에도 정산 결과에서 체크할 수 있어요.',
        )) {
      return;
    }
    await act(
      widget.store.completeRoom,
      '정산을 완료했어요. 정산 기록과 내 부담액(가계부)을 이 기기에 저장했어요.',
    );
    final done = room;
    if (!mounted || done == null || !done.isCompleted) return;
    // 영수증이 출력기에서 나와 뜯기는 화면.
    await Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => PrintReceiptPage(room: done),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = room;
    final now = DateTime.now();
    final expired = r != null && r.isExpiredAt(now);
    final isOwner = r != null && actor != null && r.owns(actor!);
    // 기한이 지난 방은 삭제 작업 전이라도 수정·복제를 막는다.
    final manager = isOwner && !expired;
    // 얼린 방과 완료된 방은 입력을 받지 않는다.
    final owner = manager && !r.isFrozen && !r.isCompleted;
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
                            // 새 참여자가 들어올 수 있는 방에서만 입장 QR을 보여준다.
                            if (!r.isFrozen &&
                                !r.isCompleted &&
                                !r.isExpiredAt(now))
                              IconButton(
                                onPressed: () => showRoomQr(context, r),
                                icon: const Icon(Icons.qr_code_2),
                                tooltip: '입장 QR 보기',
                              ),
                          ],
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(text: roomLink(r.code)),
                            );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    '방 링크를 복사했어요. 친구에게 보내면 링크로 바로 들어올 수 있어요.',
                                  ),
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.link),
                          label: const Text('방 링크 복사'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                _ExpiryCard(
                  room: r,
                  now: now,
                  onExtend: owner && r.extendsLeft > 0
                      ? () => act(
                          widget.store.extendRoom,
                          '남은 시간을 ${roomInactiveLimit.inHours}시간으로 되돌렸어요.',
                        )
                      : null,
                  onFreeze: owner ? freeze : null,
                  onThaw: manager && r.isFrozen && !r.isCompleted
                      ? () => act(
                          widget.store.thawRoom,
                          '방을 녹였어요. 지금부터 ${roomInactiveLimit.inHours}시간을 다시 셉니다.',
                        )
                      : null,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final m in r.members)
                      Chip(
                        label: Text.rich(
                          TextSpan(
                            text:
                                '${m.name}${m.id == r.ownerMemberId ? ' · 방장' : ''}',
                            children: [
                              if (m.actorId == null)
                                const TextSpan(
                                  text: ' · 미연결',
                                  style: TextStyle(
                                    color: toongDanger,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        deleteIcon: const Icon(Icons.close, size: 18),
                        deleteButtonTooltipMessage: '${m.name} 빼기',
                        onDeleted: owner && m.id != r.ownerMemberId
                            ? () => removeMember(m)
                            : null,
                      ),
                    if (owner && r.members.length < roomMemberLimit)
                      ActionChip(
                        avatar: const Icon(Icons.person_add_alt_1, size: 18),
                        label: const Text('사람 추가'),
                        onPressed: addMember,
                      ),
                  ],
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
                if (!isOwner && !expired && !r.isFrozen && !r.isCompleted)
                  const Text('지출과 잔돈 부담자는 방장이 입력할 수 있어요.'),
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
                              : SettlementPage(store: widget.store, room: r),
                        ),
                  child: const Text('정산 결과 보기'),
                ),
                if (owner && r.expenses.isNotEmpty && r.pendingRemainder == 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: OutlinedButton.icon(
                      onPressed: complete,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 54),
                      ),
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('정산 완료'),
                    ),
                  ),
                if (r.isCompleted)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: OutlinedButton.icon(
                      onPressed: () => open(
                        RecordPage(record: SettlementRecord.fromRoom(r)),
                      ),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 54),
                      ),
                      icon: const Icon(Icons.receipt_long),
                      label: const Text('정산 기록 보기'),
                    ),
                  ),
                const SizedBox(height: 22),
                TextButton.icon(
                  onPressed: expired ? null : copyRoom,
                  icon: const Icon(Icons.copy_all),
                  label: const Text('이 방의 정산 복제하기'),
                ),
                if (!widget.store.isCloud)
                  const Padding(
                    padding: EdgeInsets.only(top: 18),
                    child: Text(
                      '체험 모드 · 이 기기에만 저장됩니다. 다른 기기와 연결하려면 서버 설정이 필요해요.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: toongSub),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _ExpiryCard extends StatelessWidget {
  const _ExpiryCard({
    required this.room,
    required this.now,
    this.onExtend,
    this.onFreeze,
    this.onThaw,
  });
  final Room room;
  final DateTime now;

  /// null이면 해당 버튼을 보여주지 않는다. 방장에게만 전달된다.
  final VoidCallback? onExtend;
  final VoidCallback? onFreeze;
  final VoidCallback? onThaw;

  @override
  Widget build(BuildContext context) {
    final expired = room.isExpiredAt(now);
    final remaining = room.remainingAt(now);
    final left = '삭제까지 ${formatRemaining(remaining)}';
    final urgent = !expired && remaining < const Duration(hours: 6);
    final (icon, title, body) = switch (room) {
      _ when expired => (
        Icons.block,
        room.isCompleted || room.isFrozen
            ? '보관 기간이 지나 삭제된 방입니다.'
            : roomExpiredMessage,
        '더 이상 입력·복제할 수 없어요. 필요한 내용은 지금 확인해주세요.',
      ),
      Room(isCompleted: true) => (
        Icons.check_circle_outline,
        '정산 완료 · $left',
        '정산 기록은 이 기기에 저장됐어요. 방은 완료 ${roomCompletedLimit.inHours}시간 뒤 삭제됩니다.',
      ),
      Room(isFrozen: true) => (
        Icons.ac_unit,
        '얼린 방 · $left',
        '얼린 동안에는 입력할 수 없어요. ${roomFreezeLimit.inDays}일 안에 녹이지 않으면 삭제됩니다.',
      ),
      _ => (Icons.timer_outlined, left, roomExpiryNotice),
    };
    final icy = room.isFrozen && !room.isCompleted && !expired;
    return Card(
      color: Colors.transparent,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: IceBox(
        frozen: icy,
        color: expired || urgent ? toongWarn : _soft,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: icy ? iceDeep : _ink, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      body,
                      style: const TextStyle(fontSize: 13, color: toongSub),
                    ),
                    if (onExtend != null || onFreeze != null || onThaw != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Wrap(
                          spacing: 8,
                          children: [
                            if (onExtend != null)
                              OutlinedButton.icon(
                                onPressed: onExtend,
                                icon: const Icon(Icons.update, size: 18),
                                label: Text('연장 (${room.extendsLeft}회 남음)'),
                              ),
                            if (onFreeze != null)
                              OutlinedButton.icon(
                                onPressed: onFreeze,
                                icon: const Icon(Icons.ac_unit, size: 18),
                                label: const Text('얼리기'),
                              ),
                            if (onThaw != null)
                              OutlinedButton.icon(
                                onPressed: onThaw,
                                icon: const Icon(
                                  Icons.wb_sunny_outlined,
                                  size: 18,
                                ),
                                label: const Text('녹이기'),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

typedef PickedPhoto = ({Uint8List bytes, String mimeType});

/// 영수증 사진을 찍거나 고른다. 긴 변을 1600px로 줄여 전송량과 인식 비용을 줄인다.
/// 위젯 테스트에서 바꿔 끼울 수 있게 변수로 둔다.
Future<PickedPhoto?> Function(ImageSource source) pickReceiptPhoto =
    _pickWithImagePicker;

Future<PickedPhoto?> _pickWithImagePicker(ImageSource source) async {
  final file = await ImagePicker().pickImage(
    source: source,
    maxWidth: 1600,
    maxHeight: 1600,
    imageQuality: 80,
  );
  if (file == null) return null;
  final mimeType =
      file.mimeType ??
      (file.name.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg');
  return (bytes: await file.readAsBytes(), mimeType: mimeType);
}

class _ItemDraft {
  _ItemDraft({
    required this.id,
    required String name,
    required int amount,
    required this.memberIds,
    this.remainderMemberId,
    this.nameHidden = false,
    this.amountHidden = false,
    this.amountGuessed = false,
  }) : name = TextEditingController(text: name),
       amount = TextEditingController(text: amount == 0 ? '' : '$amount');
  final String id;
  final TextEditingController name;
  final TextEditingController amount;
  final Set<String> memberIds;
  String? remainderMemberId;

  /// 영수증에서 이름이 가려져 "메뉴 1"처럼 임시 이름을 붙였으면 true. 고치면 false.
  bool nameHidden;

  /// 영수증에서 금액이 가려져 비워 뒀으면 true. 입력하면 false.
  bool amountHidden;

  /// 영수증 총액으로 계산해 채운 금액이면 true. 고치면 false.
  bool amountGuessed;

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

  /// 마지막으로 읽은 영수증. 항목 합계와 영수증 총액을 비교해 보여준다.
  ScannedReceipt? scanned;
  bool scanning = false;

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

  /// 영수증 사진을 읽어 항목을 채운다. 이미 입력한 항목이 있으면 바꿀지 먼저 묻는다.
  Future<void> scan(ImageSource source, {bool askReplace = true}) async {
    final scanner = widget.store.receiptScanner;
    if (scanner == null || scanning) return;
    final hasInput = items.any(
      (d) => d.name.text.trim().isNotEmpty || d.amount.text.trim().isNotEmpty,
    );
    if (hasInput && askReplace) {
      final replace = await askConfirm(
        context,
        title: const Text('입력한 항목을 바꿀까요?'),
        content: const Text('영수증에서 읽은 메뉴로 지금 항목을 모두 바꿉니다.'),
      );
      if (replace != true || !mounted) return;
    }
    final photo = await pickReceiptPhoto(source);
    if (photo == null || !mounted) return;
    setState(() => scanning = true);
    try {
      final receipt = (await scanner.scan(
        photo.bytes,
        mimeType: photo.mimeType,
      )).withGuessedAmount();
      if (!mounted) return;
      if (receipt.items.isEmpty) {
        // 하나도 못 읽었으면 입력한 항목은 그대로 두고 다시 찍기를 권한다.
        setState(() => scanning = false);
        final retake = await askConfirm(
          context,
          title: const Text('메뉴를 읽지 못했어요'),
          content: const Text(
            '가려진 부분 없이, 영수증이 화면에 꽉 차게 다시 찍어주세요. '
            '취소하면 직접 입력할 수 있어요.',
          ),
        );
        if (retake && mounted) await scan(source, askReplace: false);
        return;
      }
      setState(() {
        for (final draft in items) {
          draft.dispose();
        }
        items
          ..clear()
          ..addAll(
            receipt.toLines().map(
              (line) => _ItemDraft(
                id: newId(),
                name: line.name,
                amount: line.amount ?? 0,
                memberIds: {},
                nameHidden: line.nameHidden,
                amountHidden: line.amountHidden,
                amountGuessed: line.amountGuessed,
              ),
            ),
          );
        if (title.text.trim().isEmpty && receipt.storeName != null) {
          title.text = receipt.storeName!;
        }
        scanned = receipt;
      });
    } catch (error) {
      if (mounted) await showFailure(context, error);
    } finally {
      if (mounted) setState(() => scanning = false);
    }
  }

  /// 지금 입력된 항목 금액의 합. 숫자가 아닌 칸은 0으로 본다.
  int get draftTotal => items.fold(
    0,
    (sum, d) => sum + (int.tryParse(d.amount.text.replaceAll(',', '')) ?? 0),
  );

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
          remainderOdds: keepRemainder ? unchanged.remainderOdds : null,
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
        if (widget.store.receiptScanner == null)
          const Text('메뉴와 금액을 직접 입력해주세요.')
        else ...[
          const Text('영수증을 찍거나, 메뉴와 금액을 직접 입력해주세요.'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: scanning ? null : () => scan(ImageSource.camera),
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('영수증 촬영'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: scanning ? null : () => scan(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('사진 선택'),
                ),
              ),
            ],
          ),
          if (scanning)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(),
                  SizedBox(height: 6),
                  Text('영수증을 읽는 중이에요…'),
                ],
              ),
            ),
          if (scanned != null && !scanning)
            _ScanSummary(
              receipt: scanned!,
              currentTotal: draftTotal,
              hiddenLeft: items.fold(
                0,
                (sum, d) =>
                    sum + (d.nameHidden ? 1 : 0) + (d.amountHidden ? 1 : 0),
              ),
              amountsMissing: items.any((d) => d.amountHidden),
              onAddGap: (gap) => setState(
                () => items.add(
                  _ItemDraft(
                    id: newId(),
                    name: '확인 필요 메뉴',
                    amount: gap,
                    memberIds: {},
                    nameHidden: true,
                  ),
                ),
              ),
              onSelectAll: () => setState(() {
                for (final draft in items) {
                  draft.memberIds
                    ..clear()
                    ..addAll(widget.room.members.map((m) => m.id));
                  draft.remainderMemberId = null;
                }
              }),
            ),
        ],
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
              onChanged: (_) {
                if (item.nameHidden) setState(() => item.nameHidden = false);
              },
              decoration: _flagged(
                const InputDecoration(
                  labelText: '메뉴 또는 이용 내역',
                  hintText: '예: 치킨',
                ),
                item.nameHidden ? '영수증에서 이름이 가려져 있어요. 알아보면 고쳐주세요.' : null,
                toongDanger,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: item.amount,
              // 영수증 총액과의 차이 표시를 바로 갱신한다.
              onChanged: (_) => setState(() {
                item.amountHidden = false;
                item.amountGuessed = false;
              }),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: _flagged(
                const InputDecoration(
                  labelText: '항목 총액 (원)',
                  hintText: '24000',
                ),
                item.amountHidden
                    ? '영수증에서 금액이 가려져 있어요. 직접 입력해주세요.'
                    : item.amountGuessed
                    ? '가려진 금액을 영수증 총액으로 계산했어요. 확인해주세요.'
                    : null,
                item.amountHidden ? toongDanger : _orange,
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

/// 가려진 칸 안내 색(합계로 계산한 금액).
const _orange = Color(0xFFD9822B);

/// [message]가 있으면 테두리와 안내 글씨를 [color]로 칠한다.
InputDecoration _flagged(InputDecoration base, String? message, Color color) {
  if (message == null) return base;
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: BorderSide(color: color, width: 1.6),
  );
  return base.copyWith(
    helperText: message,
    helperMaxLines: 2,
    helperStyle: TextStyle(color: color, fontWeight: FontWeight.w600),
    enabledBorder: border,
    focusedBorder: border.copyWith(
      borderSide: BorderSide(color: color, width: 2.2),
    ),
  );
}

/// 영수증 인식 결과 요약: 읽은 메뉴 수, 반영한 할인, 영수증 총액과의 차이.
class _ScanSummary extends StatelessWidget {
  const _ScanSummary({
    required this.receipt,
    required this.currentTotal,
    required this.hiddenLeft,
    required this.amountsMissing,
    required this.onAddGap,
    required this.onSelectAll,
  });
  final ScannedReceipt receipt;

  /// 아직 고치지 않은 가려진 칸 수.
  final int hiddenLeft;

  /// 금액이 가려져 빈 칸이 남아 있으면 true. 차액 비교는 그 칸을 채운 뒤에 한다.
  final bool amountsMissing;

  /// 영수증 총액과의 차액만큼 "확인 필요 메뉴"를 더한다.
  final ValueChanged<int> onAddGap;

  /// 지금 입력된 항목 금액의 합. 사용자가 고치면 바뀐다.
  final int currentTotal;
  final VoidCallback onSelectAll;

  @override
  Widget build(BuildContext context) {
    final total = receipt.total;
    final gap = total == null ? null : total - currentTotal;
    final discount = receipt.discountTotal;
    final names = receipt.discounts.map((d) => d.name).join(', ');
    final (warn, check) = switch (gap) {
      null => (true, '영수증 총액을 읽지 못했어요. 금액을 확인해주세요.'),
      0 => (false, '항목 합계가 영수증 총액 ${money(total!)}과 같아요.'),
      > 0 => (
        true,
        '항목 합계가 영수증 총액 ${money(total!)}보다 ${money(gap)} 적어요. '
            '가려져서 빠진 메뉴가 있을 수 있어요.',
      ),
      _ => (
        true,
        '항목 합계가 영수증 총액 ${money(total!)}보다 ${money(-gap)} 많아요. 금액을 확인해주세요.',
      ),
    };
    return Card(
      margin: const EdgeInsets.only(top: 12),
      color: warn ? toongWarn : _soft,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '영수증에서 메뉴 ${receipt.items.length}개를 읽었어요.',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            if (discount > 0 && discount < receipt.itemsTotal)
              Text('할인 ${money(discount)}($names)을 메뉴 금액에 비율대로 나눠 반영했어요.'),
            if (discount > 0 && discount >= receipt.itemsTotal)
              Text('할인 ${money(discount)}이 메뉴 합보다 커서 반영하지 않았어요.'),
            if (hiddenLeft > 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  '가려져 읽지 못한 칸 $hiddenLeft개가 있어요. 빨간 칸을 확인해주세요.',
                  style: const TextStyle(
                    color: toongDanger,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            Text(
              amountsMissing && gap != null && gap > 0
                  ? '가려진 금액 칸을 채운 뒤 영수증 총액 ${money(total!)}과 다시 비교해요.'
                  : check,
            ),
            if (gap != null && gap > 0 && !amountsMissing)
              TextButton.icon(
                onPressed: () => onAddGap(gap),
                icon: const Icon(Icons.playlist_add),
                label: Text('차액 ${money(gap)}을 항목으로 추가'),
              ),
            const SizedBox(height: 4),
            const Text(
              '인식 결과가 틀릴 수 있어요. 항목을 확인하고 먹은 사람을 골라주세요.',
              style: TextStyle(fontSize: 13, color: toongSub),
            ),
            TextButton.icon(
              onPressed: onSelectAll,
              icon: const Icon(Icons.group_outlined),
              label: const Text('모든 항목에 모두 선택'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 잔돈 추첨에 쓰는 난수. 테스트에서 바꿔 끼운다.
Random drawRandom = Random.secure();

/// 잔돈 부담자를 뽑는 가챠(룰렛) 창. 후보를 고르고 돌리면 이름이 빠르게 돌다가
/// 한 명에서 멈춘다. 확인을 누르면 뽑힌 참여자의 id를 돌려준다.
/// 잔돈 추첨 결과. 확률을 직접 정했으면 [odds]에 후보별 비율이 있다.
typedef DrawResult = ({String memberId, Map<String, int>? odds});

/// 돌림판 칸 색. 흑백 테마에 맞춘 검정·회색 계열을 번갈아 쓴다.
const _wheelColors = [
  Color(0xFF111111),
  Color(0xFF8A8A86),
  Color(0xFF3A3A3A),
  Color(0xFFBDBDB8),
  Color(0xFF5E5E5B),
  Color(0xFFDADAD5),
];

class DrawDialog extends StatefulWidget {
  const DrawDialog({super.key, required this.room, required this.item});
  final Room room;
  final LineItem item;
  @override
  State<DrawDialog> createState() => _DrawDialogState();
}

class _DrawDialogState extends State<DrawDialog>
    with SingleTickerProviderStateMixin {
  late final Set<String> candidates = widget.item.memberIds.toSet();

  /// 후보별 확률 비율. [custom]이 꺼져 있으면 모두 1로 본다.
  late final Map<String, int> weights = {
    for (final id in widget.item.memberIds) id: 1,
  };
  bool custom = false;

  late final AnimationController spin =
      AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 3200),
        )
        ..addListener(() => setState(() {}))
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed) {
            HapticFeedback.heavyImpact();
          }
          setState(() {});
        });

  /// 이번 추첨에 쓴 후보(순서 고정), 비율, 뽑힌 사람의 위치, 돌림판이 멈출 회전량(바퀴 수).
  List<String> pool = [];
  List<int> poolWeights = [];
  int? winner;
  double turns = 0;
  int lastSlice = -1;

  @override
  void dispose() {
    spin.dispose();
    super.dispose();
  }

  bool get spinning => spin.isAnimating;
  bool get done => winner != null && spin.isCompleted;

  /// 지금 화면에 그릴 후보와 비율. 돌린 뒤에는 그때의 후보를 그대로 보여준다.
  List<String> get slices => winner != null
      ? pool
      : widget.item.memberIds.where(candidates.contains).toList();
  List<int> get sliceWeights => winner != null
      ? poolWeights
      : [for (final id in slices) custom ? weights[id]! : 1];

  /// 지금 돌림판이 돈 양(바퀴 수). 빠르게 돌다 점점 느려진다.
  double get rotation => Curves.easeOutQuart.transform(spin.value) * turns;

  /// 위쪽 화살표가 가리키는 칸의 위치.
  int? get pointed {
    final ws = sliceWeights;
    if (ws.isEmpty) return null;
    final total = ws.fold(0, (s, w) => s + w);
    // 판이 시계 방향으로 r바퀴 돌면 화살표 아래에는 원래 (1 - r) 위치가 온다.
    var at = (1 - rotation % 1) % 1 * total;
    for (var i = 0; i < ws.length; i++) {
      if (at < ws[i]) return i;
      at -= ws[i];
    }
    return ws.length - 1;
  }

  void roll() {
    pool = widget.item.memberIds.where(candidates.contains).toList();
    poolWeights = [for (final id in pool) custom ? weights[id]! : 1];
    winner = pickWeighted(poolWeights, drawRandom);
    // 뽑힌 칸 안의 한 지점(가장자리는 피함)이 화살표에 오도록 멈출 각도를 정한다.
    final total = poolWeights.fold(0, (s, w) => s + w);
    final start = poolWeights.take(winner!).fold(0, (s, w) => s + w);
    final inside = 0.2 + drawRandom.nextDouble() * 0.6;
    final target = (start + poolWeights[winner!] * inside) / total;
    turns = 6 + (1 - target);
    lastSlice = -1;
    spin.forward(from: 0);
  }

  void reset() => winner = null;

  @override
  Widget build(BuildContext context) {
    final members = widget.item.memberIds;
    final all = candidates.length == members.length;
    final now = pointed;
    if (spinning && now != null && now != lastSlice) {
      lastSlice = now;
      HapticFeedback.selectionClick();
    }
    final name = now == null ? null : widget.room.memberName(slices[now]);
    final ids = slices;
    final percents = weightPercents(sliceWeights);
    return AlertDialog(
      title: const Text('잔돈 추첨'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${widget.item.name}의 잔돈 ${money(widget.item.remainder)}을 낼 사람을 뽑아요.',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                FilterChip(
                  label: const Text('모두 선택'),
                  selected: all,
                  onSelected: spinning
                      ? null
                      : (_) => setState(() {
                          reset();
                          if (all) {
                            candidates.clear();
                          } else {
                            candidates.addAll(members);
                          }
                        }),
                ),
                for (final id in members)
                  FilterChip(
                    label: Text(widget.room.memberName(id)),
                    selected: candidates.contains(id),
                    onSelected: spinning
                        ? null
                        : (on) => setState(() {
                            reset();
                            on ? candidates.add(id) : candidates.remove(id);
                          }),
                  ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('확률 직접 정하기'),
              subtitle: const Text(
                '정한 확률은 결과와 함께 모두에게 보여요.',
                style: TextStyle(fontSize: 12),
              ),
              value: custom,
              onChanged: spinning
                  ? null
                  : (on) => setState(() {
                      reset();
                      custom = on;
                    }),
            ),
            if (custom) ...[
              for (final (i, id) in ids.indexed)
                _WeightRow(
                  color: _wheelColors[i % _wheelColors.length],
                  name: widget.room.memberName(id),
                  weight: weights[id]!,
                  percent: percents[i],
                  onChanged: spinning
                      ? null
                      : (w) => setState(() {
                          reset();
                          weights[id] = w;
                        }),
                ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: spinning
                      ? null
                      : () => setState(() {
                          reset();
                          weights.updateAll((_, _) => 1);
                        }),
                  child: const Text('모두 같게'),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Center(
              child: SizedBox(
                width: 220,
                height: 236,
                child: CustomPaint(
                  key: const Key('draw-wheel'),
                  painter: _WheelPainter(
                    textStyle:
                        Theme.of(context).textTheme.bodyMedium ??
                        const TextStyle(),
                    names: [for (final id in ids) widget.room.memberName(id)],
                    weights: sliceWeights,
                    rotation: rotation,
                    highlight: done ? winner : null,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: done ? _ink : _soft,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Text(
                winner == null ? '?' : name ?? '?',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                key: const Key('draw-slot'),
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: done ? Colors.white : _ink,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              done
                  ? '$name 님이 잔돈 ${money(widget.item.remainder)}을 내요!'
                  : candidates.isEmpty
                  ? '추첨할 사람을 한 명 이상 골라주세요.'
                  : custom
                  ? '후보 ${candidates.length}명 중 정한 확률대로 한 명을 뽑아요.'
                  : '후보 ${candidates.length}명 중 한 명을 뽑아요.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: spinning || candidates.isEmpty ? null : roll,
              icon: const Icon(Icons.casino_outlined),
              label: Text(done ? '다시 돌리기' : '돌리기'),
            ),
          ],
        ),
      ),
      actions: [
        dialogButtons(
          context,
          canConfirm: done,
          confirmValue: () => (
            memberId: pool[winner!],
            odds: custom && poolWeights.toSet().length > 1
                ? {for (final (i, id) in pool.indexed) id: poolWeights[i]}
                : null,
          ),
        ),
      ],
    );
  }
}

/// 후보 한 명의 확률 비율을 −/+로 정하는 줄.
class _WeightRow extends StatelessWidget {
  const _WeightRow({
    required this.color,
    required this.name,
    required this.weight,
    required this.percent,
    required this.onChanged,
  });
  final Color color;
  final String name;
  final int weight;
  final int percent;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: toongLine),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(child: Text(name, overflow: TextOverflow.ellipsis)),
      IconButton(
        visualDensity: VisualDensity.compact,
        tooltip: '$name 확률 낮추기',
        onPressed: onChanged == null || weight <= drawWeightMin
            ? null
            : () => onChanged!(weight - 1),
        icon: const Icon(Icons.remove_circle_outline, size: 20),
      ),
      SizedBox(
        width: 22,
        child: Text(
          '$weight',
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      IconButton(
        visualDensity: VisualDensity.compact,
        tooltip: '$name 확률 높이기',
        onPressed: onChanged == null || weight >= drawWeightMax
            ? null
            : () => onChanged!(weight + 1),
        icon: const Icon(Icons.add_circle_outline, size: 20),
      ),
      SizedBox(
        width: 42,
        child: Text(
          '$percent%',
          textAlign: TextAlign.right,
          style: const TextStyle(color: toongSub),
        ),
      ),
    ],
  );
}

/// 칸 크기가 확률과 같은 돌림판. 위쪽 삼각형이 가리키는 칸이 뽑힌다.
class _WheelPainter extends CustomPainter {
  _WheelPainter({
    required this.textStyle,
    required this.names,
    required this.weights,
    required this.rotation,
    required this.highlight,
  });

  /// 앱 글꼴을 그대로 쓰기 위한 기본 글자 모양.
  final TextStyle textStyle;
  final List<String> names;
  final List<int> weights;

  /// 돈 양(바퀴 수). 시계 방향.
  final double rotation;
  final int? highlight;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = min(size.width, size.height - 16) / 2;
    final center = Offset(size.width / 2, 16 + radius);
    final rect = Rect.fromCircle(center: center, radius: radius);
    if (names.isEmpty) {
      canvas.drawCircle(center, radius, Paint()..color = _soft);
    } else {
      final total = weights.fold(0, (s, w) => s + w);
      var start = -pi / 2 + rotation * 2 * pi;
      for (var i = 0; i < names.length; i++) {
        final sweep = weights[i] / total * 2 * pi;
        final color = _wheelColors[i % _wheelColors.length];
        final dim = highlight != null && highlight != i;
        canvas.drawArc(
          rect,
          start,
          sweep,
          true,
          Paint()..color = dim ? Color.lerp(color, Colors.white, 0.7)! : color,
        );
        if (names.length > 1) {
          canvas.drawLine(
            center,
            center + Offset(cos(start), sin(start)) * radius,
            Paint()
              ..color = Colors.white
              ..strokeWidth = 2,
          );
        }
        // 이름은 칸 가운데, 바깥쪽 2/3 지점에 칸 방향으로 쓴다.
        final mid = start + sweep / 2;
        final dark = color.computeLuminance() < 0.4;
        final label = TextPainter(
          text: TextSpan(
            text: names[i],
            style: textStyle.copyWith(
              fontSize: sweep < 0.5 ? 11 : 14,
              fontWeight: FontWeight.w700,
              color: dim
                  ? toongSub
                  : dark
                  ? Colors.white
                  : _ink,
            ),
          ),
          maxLines: 1,
          ellipsis: '…',
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: radius * 0.62);
        canvas.save();
        canvas.translate(center.dx, center.dy);
        canvas.rotate(mid);
        canvas.translate(radius * 0.62, 0);
        // 왼쪽 절반은 글자가 뒤집히지 않게 돌린다.
        final flip = cos(mid) < 0;
        if (flip) canvas.rotate(pi);
        label.paint(canvas, Offset(-label.width / 2, -label.height / 2));
        canvas.restore();
        start += sweep;
      }
      // 뽑힌 칸은 빨간 테두리로 강조한다.
      if (highlight != null) {
        final from =
            -pi / 2 +
            rotation * 2 * pi +
            weights.take(highlight!).fold(0, (s, w) => s + w) / total * 2 * pi;
        final sweep = weights[highlight!] / total * 2 * pi;
        canvas.drawPath(
          Path()
            ..moveTo(center.dx, center.dy)
            ..arcTo(rect.deflate(2.5), from, sweep, false)
            ..close(),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 5
            ..strokeJoin = StrokeJoin.round
            ..color = toongDanger,
        );
      }
    }
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = _ink,
    );
    canvas.drawCircle(center, 14, Paint()..color = Colors.white);
    canvas.drawCircle(
      center,
      14,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = _ink,
    );
    // 위쪽 화살표.
    final tip = Offset(center.dx, 16 + 14);
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(tip.dx - 12, 0)
        ..lineTo(tip.dx + 12, 0)
        ..close(),
      Paint()..color = toongDanger,
    );
  }

  @override
  bool shouldRepaint(_WheelPainter old) =>
      old.rotation != rotation ||
      old.highlight != highlight ||
      old.textStyle != textStyle ||
      old.names.join('|') != names.join('|') ||
      old.weights.join('|') != weights.join('|');
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

  Future<void> assign(
    String expenseId,
    String itemId,
    String memberId, {
    Map<String, int>? odds,
  }) async {
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
                              : item.withRemainder(memberId, odds: odds),
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
                ? '각 항목의 잔돈을 부담할 사람을 추첨하거나 직접 골라주세요. '
                      '정한 결과는 참여자 모두에게 똑같이 보여요.'
                : '방장이 잔돈 부담자를 정하면 정산 결과를 볼 수 있어요.',
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
                      style: const TextStyle(color: toongSub),
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
                    if (widget.canEdit) ...[
                      OutlinedButton.icon(
                        onPressed: busy
                            ? null
                            : () async {
                                final result = await showDialog<Object?>(
                                  context: context,
                                  barrierDismissible: false,
                                  builder: (_) =>
                                      DrawDialog(room: room, item: entry.item),
                                );
                                if (result is DrawResult) {
                                  await assign(
                                    entry.expense.id,
                                    entry.item.id,
                                    result.memberId,
                                    odds: result.odds,
                                  );
                                }
                              },
                        icon: const Icon(Icons.casino_outlined),
                        label: const Text('추첨으로 정하기'),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        '또는 직접 고르기',
                        style: TextStyle(fontSize: 13, color: toongSub),
                      ),
                      const SizedBox(height: 4),
                    ],
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
                MaterialPageRoute(
                  builder: (_) =>
                      SettlementPage(store: widget.store, room: room),
                ),
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

/// 최종 정산 결과. 누가 누구에게 얼마를 보내면 되는지 보여주고, 송금마다
/// 보내는 사람·받는 사람(또는 방장)이 "송금 완료"를 표시하거나 풀 수 있다.
class SettlementPage extends StatefulWidget {
  const SettlementPage({super.key, required this.store, required this.room});
  final RoomStore store;
  final Room room;
  @override
  State<SettlementPage> createState() => _SettlementPageState();
}

class _SettlementPageState extends State<SettlementPage> {
  late Room room = widget.room;
  String? actor;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    widget.store.actorId().then((id) {
      if (mounted) setState(() => actor = id);
    });
    refresh(silent: true);
  }

  /// 다른 사람이 표시한 송금 완료를 불러온다.
  Future<void> refresh({bool silent = false}) async {
    try {
      final fresh = await widget.store.getRoom(room.id);
      if (mounted) setState(() => room = fresh);
    } catch (error) {
      if (!silent && mounted) await showFailure(context, error);
    }
  }

  /// 이 송금에 표시할 수 있는지: 보내는 사람, 받는 사람, 방장.
  bool canMark(Transfer t) {
    final me = actor == null ? null : room.actorMember(actor!);
    if (me == null) return false;
    return me.id == t.from || me.id == t.to || room.owns(actor!);
  }

  Future<void> toggle(Transfer t, bool paid) async {
    final who =
        '${room.memberName(t.from)} → ${room.memberName(t.to)} ${money(t.amount)}';
    final accepted = await askConfirm(
      context,
      title: Text(paid ? '송금 완료 표시를 풀까요?' : '이 금액이 정산되었나요?'),
      content: Text(
        paid
            ? '$who을 다시 보내야 할 돈으로 표시해요.'
            : '$who을 송금 완료로 표시해요. 참여자 모두에게 똑같이 보여요.',
      ),
    );
    if (!accepted || !mounted) return;
    setState(() => busy = true);
    try {
      final updated = await widget.store.markTransfer(room, t, paid: !paid);
      // 완료된 방이면 기기에 저장된 정산 기록도 새 표시로 바꾼다.
      await RecordStore().replace(updated);
      if (mounted) setState(() => room = updated);
    } catch (error) {
      if (mounted) await showFailure(context, error);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (room.pendingRemainder > 0) {
      return Scaffold(
        appBar: AppBar(title: const Text('정산 결과')),
        body: const Center(child: Text('잔돈 부담자를 먼저 지정해주세요.')),
      );
    }
    final result = calculateSettlement(room);
    final done = result.transfers
        .where((t) => room.isPaid(t.from, t.to, t.amount))
        .length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('정산 결과'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '새로고침',
            onPressed: refresh,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
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
            if (result.transfers.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                done == result.transfers.length
                    ? '모든 송금이 끝났어요.'
                    : '송금 ${result.transfers.length}건 중 $done건 완료',
                style: const TextStyle(
                  color: toongSub,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 20),
            if (result.transfers.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('주고받을 돈이 없어요. 이미 셈셈!'),
                ),
              ),
            for (final transfer in result.transfers)
              _TransferCard(
                room: room,
                transfer: transfer,
                canMark: canMark(transfer) && !busy,
                onToggle: (paid) => toggle(transfer, paid),
              ),
            const SizedBox(height: 10),
            const Text(
              '송금은 사용 중인 은행 앱에서 진행해주세요. 보낸 뒤 체크하면 참여자 모두에게 보여요. '
              '보내는 사람, 받는 사람, 방장이 체크할 수 있어요.',
              style: TextStyle(color: toongSub),
            ),
            const SizedBox(height: 24),
            _RemainderSummary(room: room),
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
                  style: TextStyle(color: toongSub),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 잔돈 부담자 목록. 확률을 직접 정한 추첨이었으면 그 확률을 함께 보여준다.
class _RemainderSummary extends StatelessWidget {
  const _RemainderSummary({required this.room});
  final Room room;

  @override
  Widget build(BuildContext context) {
    final items = [
      for (final e in room.expenses)
        for (final item in e.items)
          if (item.remainder > 0 && item.remainderMemberId != null) item,
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    return ExpansionTile(
      title: const Text('잔돈 부담'),
      // 확률을 직접 정한 추첨이 있으면 처음부터 펼쳐 둔다.
      initiallyExpanded: items.any((i) => i.remainderOdds != null),
      children: [
        for (final item in items)
          ListTile(
            title: Text(
              '${item.name} 잔돈 ${money(item.remainder)} · '
              '${room.memberName(item.remainderMemberId!)} 부담',
            ),
            subtitle: item.remainderOdds == null
                ? null
                : Text(
                    '확률 직접 정한 추첨 · ${oddsLabel(room, item.remainderOdds!)}',
                    style: const TextStyle(color: toongDanger),
                  ),
          ),
      ],
    );
  }
}

/// 송금 한 건. 오른쪽 체크로 송금 완료를 표시한다.
class _TransferCard extends StatelessWidget {
  const _TransferCard({
    required this.room,
    required this.transfer,
    required this.canMark,
    required this.onToggle,
  });
  final Room room;
  final Transfer transfer;
  final bool canMark;

  /// 지금 완료 상태를 넘긴다(true면 풀기, false면 표시하기).
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final t = transfer;
    final mark = room.paidMark(t.from, t.to);
    final paid = mark != null && mark.amount == t.amount;
    // 지출이 바뀌어 금액이 달라진 표시.
    final stale = mark != null && !paid;
    final name = '${room.memberName(t.from)} → ${room.memberName(t.to)}';
    return Card(
      color: paid ? toongCanvas : _soft,
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: paid ? toongSub : _ink,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    money(t.amount),
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: paid ? toongSub : _ink,
                      decoration: paid ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  if (paid)
                    Text(
                      '송금 완료 · ${room.memberName(mark.by)} 확인',
                      style: const TextStyle(fontSize: 13, color: toongSub),
                    ),
                  if (stale)
                    Text(
                      '금액이 바뀌었어요. 전에 ${money(mark.amount)} 송금 완료로 표시됐어요.',
                      style: const TextStyle(fontSize: 13, color: toongDanger),
                    ),
                ],
              ),
            ),
            Tooltip(
              message: paid ? '$name 송금 완료 풀기' : '$name 송금 완료 표시',
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: canMark ? () => onToggle(paid) : null,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: paid ? _ink : Colors.transparent,
                      border: Border.all(
                        color: canMark || paid ? _ink : toongLine,
                        width: 2,
                      ),
                    ),
                    child: paid
                        ? const Icon(Icons.check, color: Colors.white, size: 24)
                        : null,
                  ),
                ),
              ),
            ),
          ],
        ),
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
