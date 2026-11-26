import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';

import 'domain/models.dart';
import 'domain/settlement.dart';
import 'theme.dart';

/// 영수증 글꼴. 나눔고딕코딩(고정폭)이라 금액 자리가 줄 맞춰 보인다.
const receiptFont = 'ReceiptMono';

const _stampRed = Color(0xFFD93A3A);

String _won(int value) => value.toString().replaceAllMapped(
  RegExp(r'\B(?=(\d{3})+(?!\d))'),
  (_) => ',',
);

String _two(int v) => v.toString().padLeft(2, '0');

String _stamp(DateTime time) {
  final t = time.toLocal();
  return '${t.year}-${_two(t.month)}-${_two(t.day)} ${_two(t.hour)}:${_two(t.minute)}';
}

/// 위·아래(또는 아래만) 가장자리를 톱니 모양으로 자른다.
class ZigzagClipper extends CustomClipper<Path> {
  const ZigzagClipper({this.top = true, this.bottom = true, this.tooth = 8});
  final bool top;
  final bool bottom;

  /// 톱니 하나의 높이. 폭은 그 두 배다.
  final double tooth;

  @override
  Path getClip(Size size) {
    final w = tooth * 2;
    final n = max(1, (size.width / w).round());
    final step = size.width / n;
    final path = Path();
    if (top) {
      path.moveTo(0, tooth);
      for (var i = 0; i < n; i++) {
        path
          ..lineTo(i * step + step / 2, 0)
          ..lineTo((i + 1) * step, tooth);
      }
    } else {
      path
        ..moveTo(0, 0)
        ..lineTo(size.width, 0);
    }
    if (bottom) {
      path.lineTo(size.width, size.height - tooth);
      for (var i = n; i > 0; i--) {
        path
          ..lineTo(i * step - step / 2, size.height)
          ..lineTo((i - 1) * step, size.height - tooth);
      }
    } else {
      path
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height);
    }
    return path..close();
  }

  @override
  bool shouldReclip(ZigzagClipper old) =>
      old.top != top || old.bottom != bottom || old.tooth != tooth;
}

/// 흰 영수증 종이. [tornTop]이 false면 윗변이 곧다(아직 출력기에 붙어 있는 상태).
class ReceiptPaper extends StatelessWidget {
  const ReceiptPaper({super.key, required this.child, this.tornTop = true});
  final Widget child;
  final bool tornTop;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      boxShadow: [
        BoxShadow(
          color: Color(0x14000000),
          blurRadius: 10,
          offset: Offset(0, 3),
        ),
      ],
    ),
    child: ClipPath(
      clipper: ZigzagClipper(top: tornTop),
      child: ColoredBox(
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 26, 22, 30),
          child: DefaultTextStyle.merge(
            style: const TextStyle(
              fontFamily: receiptFont,
              color: toongInk,
              fontSize: 13.5,
              height: 1.55,
            ),
            child: child,
          ),
        ),
      ),
    ),
  );
}

/// 영수증의 점선 구분선.
class ReceiptDivider extends StatelessWidget {
  const ReceiptDivider({super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: LayoutBuilder(
      builder: (context, c) {
        final n = (c.maxWidth / 7).floor();
        return Row(
          children: [
            for (var i = 0; i < n; i++)
              Expanded(
                child: Container(
                  height: 1.4,
                  margin: const EdgeInsets.symmetric(horizontal: 1.5),
                  color: toongLine,
                ),
              ),
          ],
        );
      },
    ),
  );
}

/// 왼쪽 글자와 오른쪽 금액 한 줄.
class ReceiptLine extends StatelessWidget {
  const ReceiptLine(
    this.left,
    this.right, {
    super.key,
    this.bold = false,
    this.muted = false,
    this.size,
  });
  final String left;
  final String right;
  final bool bold;
  final bool muted;
  final double? size;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
      color: muted ? toongSub : toongInk,
      fontSize: size,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(left, style: style)),
        const SizedBox(width: 12),
        Text(right, style: style),
      ],
    );
  }
}

/// 방 코드로 만든 장식용 바코드. 같은 방은 늘 같은 모양이다.
class ReceiptBarcode extends StatelessWidget {
  const ReceiptBarcode(this.code, {super.key});
  final String code;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      SizedBox(
        height: 40,
        width: double.infinity,
        child: CustomPaint(painter: _BarcodePainter(code)),
      ),
      const SizedBox(height: 4),
      Text(
        'TOONG-$code',
        style: const TextStyle(fontSize: 11, color: toongSub, letterSpacing: 1),
      ),
    ],
  );
}

class _BarcodePainter extends CustomPainter {
  _BarcodePainter(this.code);
  final String code;
  @override
  void paint(Canvas canvas, Size size) {
    final widths = <int>[];
    for (final unit in '*$code*'.codeUnits) {
      for (var b = 0; b < 4; b++) {
        widths.add(1 + ((unit >> b) & 1) + ((unit >> (b + 3)) & 1));
      }
    }
    final total = widths.fold(0, (a, b) => a + b);
    final unit = min(2.2, size.width * 0.7 / total);
    var x = (size.width - total * unit) / 2;
    final paint = Paint()..color = toongInk;
    for (var i = 0; i < widths.length; i++) {
      final w = widths[i] * unit;
      if (i.isEven) canvas.drawRect(Rect.fromLTWH(x, 0, w, size.height), paint);
      x += w;
    }
  }

  @override
  bool shouldRepaint(_BarcodePainter old) => old.code != code;
}

/// 빨간 "정산완료" 도장.
class ReceiptStamp extends StatelessWidget {
  const ReceiptStamp({super.key});
  @override
  Widget build(BuildContext context) => Transform.rotate(
    angle: -0.2,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: _stampRed, width: 2.2),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text(
        '정산완료',
        style: TextStyle(
          color: _stampRed,
          fontWeight: FontWeight.w700,
          fontSize: 13,
          letterSpacing: 2,
        ),
      ),
    ),
  );
}

/// 완료된 방의 정산서. 보낼 돈, 지출 내역, 개인별 결제·부담, 총액을 영수증처럼 보여준다.
class ReceiptContent extends StatelessWidget {
  const ReceiptContent({super.key, required this.room});
  final Room room;

  @override
  Widget build(BuildContext context) {
    final result = calculateSettlement(room);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Expanded(
              child: Text(
                '퉁 정산서',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 4,
                ),
              ),
            ),
            if (room.isCompleted) const ReceiptStamp(),
          ],
        ),
        const SizedBox(height: 4),
        Text(room.name, style: const TextStyle(fontWeight: FontWeight.w700)),
        Text(
          '${_stamp(room.completedAt ?? room.lastActivityAt)} · No.${room.code}',
          style: const TextStyle(fontSize: 12, color: toongSub),
        ),
        Text(
          '참여 ${room.members.map((m) => m.name).join(', ')}',
          style: const TextStyle(fontSize: 12, color: toongSub),
        ),
        const ReceiptDivider(),
        const Text('보낼 돈', style: TextStyle(fontWeight: FontWeight.w700)),
        if (result.transfers.isEmpty)
          const Text('주고받을 돈이 없어요.', style: TextStyle(color: toongSub)),
        for (final t in result.transfers)
          ReceiptLine(
            '${room.memberName(t.from)} → ${room.memberName(t.to)}',
            _won(t.amount),
            bold: true,
          ),
        const ReceiptDivider(),
        const Text('지출 내역', style: TextStyle(fontWeight: FontWeight.w700)),
        for (final e in room.expenses) ...[
          ReceiptLine(e.title, _won(e.total)),
          Text(
            '결제 ${room.memberName(e.payerId)} · ${e.items.length}개 항목',
            style: const TextStyle(fontSize: 11.5, color: toongSub),
          ),
        ],
        const ReceiptDivider(),
        const Text('개인별', style: TextStyle(fontWeight: FontWeight.w700)),
        for (final m in room.members)
          ReceiptLine(
            '${m.name} 결제 ${_won(result.paid[m.id]!)}',
            '부담 ${_won(result.owed[m.id]!)}',
            muted: true,
          ),
        const ReceiptDivider(),
        ReceiptLine('총액', '${_won(room.total)}원', bold: true, size: 17),
        const SizedBox(height: 16),
        ReceiptBarcode(room.code),
      ],
    );
  }
}

/// 예전에 저장된 기록(방 정보 없이 글자만 있는 기록)을 영수증처럼 보여준다.
class ReceiptTextContent extends StatelessWidget {
  const ReceiptTextContent({super.key, required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final line in text.split('\n'))
        if (line.trim().isEmpty) const ReceiptDivider() else Text(line),
    ],
  );
}

/// PNG 이미지를 사진 앱에 저장한다. 테스트에서 바꿔 끼운다.
Future<void> Function(Uint8List png, String name) saveImageToGallery =
    _saveWithGal;

Future<void> _saveWithGal(Uint8List png, String name) async {
  if (!await Gal.hasPermission() && !await Gal.requestPermission()) {
    throw StateError('사진 앱 접근을 허용해야 영수증 이미지를 저장할 수 있어요.');
  }
  try {
    await Gal.putImageBytes(png, name: name);
  } on GalException catch (error) {
    throw StateError(switch (error.type) {
      GalExceptionType.permissionDenied => '사진 앱 접근을 허용해야 영수증 이미지를 저장할 수 있어요.',
      GalExceptionType.notEnoughSpace => '휴대폰 저장 공간이 부족해요.',
      _ => '영수증 이미지를 저장하지 못했어요.',
    });
  }
}

/// 사진처럼 찍어 저장할 수 있는 영수증. 찍을 때 화면이 하얗게 번쩍인다.
class CapturableReceipt extends StatefulWidget {
  const CapturableReceipt({super.key, required this.child});
  final Widget child;
  @override
  State<CapturableReceipt> createState() => CapturableReceiptState();
}

class CapturableReceiptState extends State<CapturableReceipt>
    with SingleTickerProviderStateMixin {
  final _boundary = GlobalKey();
  late final AnimationController _flash = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  )..addListener(() => setState(() {}));

  @override
  void dispose() {
    _flash.dispose();
    super.dispose();
  }

  /// 영수증(회색 여백 포함)을 3배 해상도 PNG로 찍는다.
  Future<Uint8List> capture() async {
    final boundary =
        _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 3);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    HapticFeedback.mediumImpact();
    _flash.forward(from: 0);
    return data!.buffer.asUint8List();
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      RepaintBoundary(
        key: _boundary,
        child: ColoredBox(
          color: toongSoft,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
            child: widget.child,
          ),
        ),
      ),
      if (_flash.isAnimating)
        Positioned.fill(
          child: IgnorePointer(
            child: ColoredBox(
              color: Colors.white.withValues(alpha: 1 - _flash.value),
            ),
          ),
        ),
    ],
  );
}

/// [receipt]를 찍어 사진 앱에 저장하고 결과를 알린다. 저장했으면 true.
Future<bool> saveReceiptImage(
  BuildContext context,
  GlobalKey<CapturableReceiptState> receipt,
  String name,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final png = await receipt.currentState!.capture();
    await saveImageToGallery(png, name);
    messenger.showSnackBar(
      const SnackBar(content: Text('영수증 이미지를 사진 앱에 저장했어요.')),
    );
    return true;
  } catch (error) {
    final message = error is StateError ? error.message : '영수증 이미지를 저장하지 못했어요.';
    messenger.showSnackBar(SnackBar(content: Text(message)));
    return false;
  }
}

/// 사진 앱에 저장할 파일 이름. 예: 퉁_금요일모임_20261126
String receiptFileName(String roomName, DateTime time) {
  final t = time.toLocal();
  final safe = roomName.replaceAll(RegExp(r'[^0-9A-Za-z가-힣]'), '');
  return '퉁_${safe.isEmpty ? '정산' : safe}_${t.year}${_two(t.month)}${_two(t.day)}';
}

/// 정산 완료 직후 영수증이 출력기에서 나오는 화면.
///
/// 종이가 "지지직" 하고 조금씩 끊기며 나온 뒤(짧은 진동), 다 나오면 "탁" 하고 뜯겨
/// 아래로 툭 떨어진다(강한 진동). 화면을 누르면 바로 끝까지 넘어간다.
class PrintReceiptPage extends StatefulWidget {
  const PrintReceiptPage({super.key, required this.room});
  final Room room;
  @override
  State<PrintReceiptPage> createState() => _PrintReceiptPageState();
}

class _PrintReceiptPageState extends State<PrintReceiptPage>
    with TickerProviderStateMixin {
  /// 종이가 나오는 시간과 끊기는 횟수.
  static const printTime = Duration(milliseconds: 2200);
  static const steps = 26;

  late final AnimationController feed = AnimationController(
    vsync: this,
    duration: printTime,
  );
  late final AnimationController tear = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );
  int lastStep = 0;
  bool torn = false;
  final receipt = GlobalKey<CapturableReceiptState>();
  bool saving = false;

  Future<void> saveImage() async {
    setState(() => saving = true);
    await saveReceiptImage(
      context,
      receipt,
      receiptFileName(
        widget.room.name,
        widget.room.completedAt ?? widget.room.lastActivityAt,
      ),
    );
    if (mounted) setState(() => saving = false);
  }

  @override
  void initState() {
    super.initState();
    feed
      ..addListener(onFeed)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) rip();
      });
    tear.addListener(() => setState(() {}));
    feed.forward();
  }

  void onFeed() {
    final step = (feed.value * steps).floor();
    if (step != lastStep) {
      lastStep = step;
      if (step.isOdd) HapticFeedback.selectionClick();
      setState(() {});
    }
  }

  void rip() {
    if (torn) return;
    HapticFeedback.mediumImpact();
    setState(() => torn = true);
    tear.forward(from: 0);
  }

  void skip() {
    if (feed.isAnimating) {
      feed.stop();
      feed.value = 1;
      rip();
    } else if (tear.isAnimating) {
      tear.value = 1;
    }
  }

  @override
  void dispose() {
    feed.dispose();
    tear.dispose();
    super.dispose();
  }

  /// 끊기며 나오는 진행도(0~1). 계단처럼 올라간다.
  double get fed => (feed.value * steps).floor() / steps;

  @override
  Widget build(BuildContext context) {
    final done = tear.isCompleted;
    // 뜯긴 뒤: 아래로 툭 떨어졌다 살짝 튀어 올라 자리 잡는다.
    final t = Curves.easeOutBack.transform(tear.value);
    final drop = torn ? 72 * t : 0.0;
    final tilt = torn ? -0.03 * sin(tear.value * pi) : 0.0;
    // 나오는 동안은 좌우로 아주 조금 떨린다.
    final shake = feed.isAnimating && lastStep.isOdd ? 0.8 : 0.0;
    final paper = ReceiptPaper(
      tornTop: torn,
      child: ReceiptContent(room: widget.room),
    );
    return Scaffold(
      backgroundColor: toongSoft,
      appBar: AppBar(
        backgroundColor: toongSoft,
        title: const Text('정산 완료'),
        automaticallyImplyLeading: done,
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: done ? null : skip,
        child: Stack(
          children: [
            // 출력기 몸통. 종이는 그 위에 겹쳐 그려 입구에서 나와 앞면을 덮으며 내려온다.
            const Positioned(left: 0, right: 0, top: 0, child: _Printer()),
            Positioned.fill(
              top: _Printer.slotY,
              child: done
                  ? SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(32, 58, 32, 24),
                      child: Column(
                        children: [
                          CapturableReceipt(key: receipt, child: paper),
                          const SizedBox(height: 14),
                          const Text(
                            '정산 기록과 내 부담액(가계부)을 이 기기에 저장했어요.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: toongSub, fontSize: 13),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: saving ? null : saveImage,
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(double.infinity, 50),
                            ),
                            icon: const Icon(Icons.download_outlined),
                            label: Text(saving ? '저장 중…' : '영수증 이미지 저장'),
                          ),
                          const SizedBox(height: 10),
                          FilledButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('확인'),
                          ),
                        ],
                      ),
                    )
                  : ClipRect(
                      child: OverflowBox(
                        alignment: Alignment.topCenter,
                        maxHeight: double.infinity,
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            50 + shake,
                            drop,
                            50 - shake,
                            0,
                          ),
                          child: Transform.rotate(
                            angle: tilt,
                            alignment: Alignment.topCenter,
                            child: FractionalTranslation(
                              translation: Offset(0, torn ? 0 : fed - 1),
                              child: paper,
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
            // 입구 틈. 종이 윗부분을 살짝 덮어 입구에서 나오는 것처럼 보이게 한다.
            const Positioned(
              left: _Printer.slotInset,
              right: _Printer.slotInset,
              top: _Printer.slotY - _Printer.slotHeight / 2,
              child: _Slot(),
            ),
            if (!done)
              const Positioned(
                left: 0,
                right: 0,
                bottom: 28,
                child: Text(
                  '영수증 출력 중… 누르면 건너뛰어요',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: toongSub, fontSize: 13),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 영수증 출력기 몸통. 입구 틈([slotY])은 앞면 위쪽에 있고 종이는 거기서 나온다.
class _Printer extends StatelessWidget {
  const _Printer();

  /// 화면 위에서 입구 틈 가운데까지의 거리.
  static const double slotY = 52;
  static const double slotHeight = 8;

  /// 화면 양옆에서 입구 틈까지의 거리. 종이(양옆 50)보다 조금 넓다.
  static const double slotInset = 40;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(20, 8, 20, 0),
    height: 104,
    decoration: const BoxDecoration(
      color: toongDark,
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(18),
        bottom: Radius.circular(12),
      ),
    ),
    alignment: Alignment.bottomRight,
    padding: const EdgeInsets.fromLTRB(0, 0, 16, 12),
    // 앞면 오른쪽 아래의 작은 전원 불빛.
    child: Container(
      width: 8,
      height: 8,
      decoration: const BoxDecoration(
        color: Color(0xFF7BE07B),
        shape: BoxShape.circle,
      ),
    ),
  );
}

/// 출력기 입구 틈.
class _Slot extends StatelessWidget {
  const _Slot();
  @override
  Widget build(BuildContext context) => Container(
    height: _Printer.slotHeight,
    decoration: BoxDecoration(
      color: Colors.black,
      borderRadius: BorderRadius.circular(4),
      boxShadow: const [
        BoxShadow(
          color: Color(0x55000000),
          blurRadius: 2,
          offset: Offset(0, 1),
        ),
      ],
    ),
  );
}
