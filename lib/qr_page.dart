import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'domain/models.dart';
import 'theme.dart';

/// QR에 적힌 글에서 방 코드를 꺼낸다.
/// 방 링크(`toong://join/코드`)나 방 코드만 적힌 QR을 받는다. 아니면 null.
String? codeFromQr(String? raw) {
  final text = raw?.trim() ?? '';
  if (text.isEmpty) return null;
  final uri = Uri.tryParse(text);
  if (uri != null && uri.scheme.isNotEmpty) return codeFromLink(uri);
  final code = text.toUpperCase();
  return RegExp(r'^[A-Z0-9]{6,8}$').hasMatch(code) ? code : null;
}

/// 방 입장 QR을 아래에서 올라오는 창으로 보여준다.
Future<void> showRoomQr(BuildContext context, Room room) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: toongCanvas,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                room.name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                '친구가 퉁 앱의 ‘방 코드로 입장 → QR 스캔’으로 찍으면 돼요.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: toongSub),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: toongLine),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    QrImageView(
                      data: roomLink(room.code),
                      size: 232,
                      padding: EdgeInsets.zero,
                      // 가운데 로고가 가려도 읽히도록 오류 복원 단계를 가장 높게.
                      errorCorrectionLevel: QrErrorCorrectLevel.H,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: toongInk,
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: toongInk,
                      ),
                      semanticsLabel: '${room.name} 방 입장 QR',
                    ),
                    // 흰 바탕 위 퉁 로고.
                    Container(
                      width: 54,
                      height: 54,
                      padding: const EdgeInsets.all(6),
                      color: Colors.white,
                      child: Image.asset('assets/logo.png'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                room.code,
                style: const TextStyle(
                  fontSize: 26,
                  letterSpacing: 3,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: room.code));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('방 코드를 복사했어요.')),
                      );
                    }
                  },
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('코드 복사'),
                ),
              ),
            ],
          ),
        ),
      ),
    );

/// 카메라로 방 QR을 찍어 방 코드를 돌려준다. 취소하면 null.
/// 위젯 테스트에서 바꿔 끼울 수 있게 변수로 둔다.
Future<String?> Function(BuildContext context) scanRoomQr = (context) =>
    Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const QrScanPage()),
    );

/// 방 QR 스캐너. 가운데 네모 안에 QR을 맞추면 읽는다.
class QrScanPage extends StatefulWidget {
  const QrScanPage({super.key});
  @override
  State<QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends State<QrScanPage> {
  final controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool done = false;
  String? lastWrong;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void onDetect(BarcodeCapture capture) {
    if (done) return;
    for (final barcode in capture.barcodes) {
      final code = codeFromQr(barcode.rawValue);
      if (code != null) {
        done = true;
        HapticFeedback.mediumImpact();
        Navigator.pop(context, code);
        return;
      }
    }
    // 다른 QR이면 한 번만 알리고 계속 찍게 둔다.
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw != null && raw != lastWrong) {
      lastWrong = raw;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('퉁 방 QR이 아니에요. 방 화면의 QR을 찍어주세요.')),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final window = MediaQuery.sizeOf(context).shortestSide * 0.7;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('QR 스캔'),
        actions: [
          ValueListenableBuilder(
            valueListenable: controller,
            builder: (context, state, _) => IconButton(
              tooltip: '손전등',
              onPressed: state.isRunning ? controller.toggleTorch : null,
              icon: Icon(
                state.torchState == TorchState.on
                    ? Icons.flashlight_on
                    : Icons.flashlight_off,
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: controller,
            onDetect: onDetect,
            errorBuilder: (context, error) => _ScanError(error: error),
          ),
          IgnorePointer(child: CustomPaint(painter: _WindowPainter(window))),
          Positioned(
            left: 24,
            right: 24,
            bottom: 48,
            child: Text(
              '친구 휴대폰의 방 QR을 네모 안에 맞춰주세요.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanError extends StatelessWidget {
  const _ScanError({required this.error});
  final MobileScannerException error;

  @override
  Widget build(BuildContext context) {
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.no_photography_outlined,
                color: Colors.white,
                size: 40,
              ),
              const SizedBox(height: 14),
              Text(
                denied
                    ? '카메라 권한이 없어요.\n설정에서 카메라를 허용하거나 방 코드를 직접 입력해주세요.'
                    : '카메라를 열 수 없어요.\n방 코드를 직접 입력해주세요.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, height: 1.5),
              ),
              const SizedBox(height: 18),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: toongInk,
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text('코드 직접 입력'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 가운데 네모만 밝게 두고 바깥은 어둡게 덮는다.
class _WindowPainter extends CustomPainter {
  _WindowPainter(this.side);
  final double side;

  @override
  void paint(Canvas canvas, Size size) {
    final hole = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: size.center(Offset.zero).translate(0, -24),
        width: side,
        height: side,
      ),
      const Radius.circular(18),
    );
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        Path()..addRRect(hole),
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );
    canvas.drawRRect(
      hole,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_WindowPainter old) => old.side != side;
}
