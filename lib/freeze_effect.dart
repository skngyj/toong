import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 얼린 방 상자 색.
const iceDeep = Color(0xFF2B7BB9);
const _iceLight = Color(0xFFE3F2FC);
const _iceMid = Color(0xFFB8DCF2);
const _warm = Color(0xFFFFA65C);

/// 방 남은 시간 상자에만 얼음·녹는 효과를 입힌다.
///
/// [frozen]이 false → true로 바뀌면 가장자리부터 서리가 자라며 얼고,
/// true → false로 바뀌면 따뜻한 빛과 함께 물방울이 흘러내리며 녹는다.
/// 처음부터 얼린 방이면 애니메이션 없이 얼린 모습으로 보인다.
class IceBox extends StatefulWidget {
  const IceBox({
    super.key,
    required this.frozen,
    required this.color,
    required this.child,
  });

  final bool frozen;

  /// 얼지 않았을 때 바탕색.
  final Color color;
  final Widget child;

  @override
  State<IceBox> createState() => _IceBoxState();
}

class _IceBoxState extends State<IceBox> with TickerProviderStateMixin {
  late final AnimationController freeze = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
    reverseDuration: const Duration(milliseconds: 1500),
    value: widget.frozen ? 1 : 0,
  );
  late final AnimationController thaw = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void didUpdateWidget(IceBox old) {
    super.didUpdateWidget(old);
    if (!old.frozen && widget.frozen) {
      thaw.value = 0;
      HapticFeedback.heavyImpact();
      freeze.forward(from: 0).then((_) {
        if (mounted) HapticFeedback.lightImpact();
      });
    } else if (old.frozen && !widget.frozen) {
      HapticFeedback.lightImpact();
      freeze.reverse(from: 1);
      thaw.forward(from: 0).then((_) => thaw.value = 0);
    }
  }

  @override
  void dispose() {
    freeze.dispose();
    thaw.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([freeze, thaw]),
      builder: (context, child) => CustomPaint(
        painter: IcePainter(
          base: widget.color,
          freeze: freeze.value,
          thaw: thaw.value,
        ),
        child: child,
      ),
      child: widget.child,
    );
  }
}

/// 서리·얼음 결정·눈송이(얼기)와 따뜻한 빛·물방울(녹기)을 그린다.
class IcePainter extends CustomPainter {
  IcePainter({required this.base, required this.freeze, required this.thaw});

  final Color base;

  /// 0이면 보통, 1이면 완전히 얼린 상태.
  final double freeze;

  /// 녹는 중 진행도. 0이면 효과 없음.
  final double thaw;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = base);
    if (freeze > 0) {
      final f = Curves.easeOut.transform(freeze);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              _iceLight.withValues(alpha: f),
              _iceMid.withValues(alpha: f),
            ],
          ).createShader(rect),
      );
      _shine(canvas, size, f);
      _haze(canvas, rect, f);
      _frost(canvas, size, freeze);
      _snowflakes(canvas, size, freeze);
      // 얼음 테두리.
      canvas.drawRect(
        rect.deflate(0.75),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = iceDeep.withValues(alpha: 0.45 * f),
      );
    }
    if (thaw > 0 && thaw < 1) {
      _warmth(canvas, size, thaw);
      _drops(canvas, size, thaw);
    }
  }

  /// 얼음 표면의 비스듬한 광택.
  void _shine(Canvas canvas, Size size, double f) {
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.45 * f);
    for (final (x, w) in [(0.18, 26.0), (0.26, 9.0), (0.72, 18.0)]) {
      final left = size.width * x;
      canvas.drawPath(
        Path()
          ..moveTo(left, 0)
          ..lineTo(left + w, 0)
          ..lineTo(left + w - size.height * 0.6, size.height)
          ..lineTo(left - size.height * 0.6, size.height)
          ..close(),
        paint,
      );
    }
  }

  /// 가장자리에 낀 하얀 서리 안개.
  void _haze(Canvas canvas, Rect rect, double f) {
    canvas.drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 18
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10)
        ..color = Colors.white.withValues(alpha: 0.9 * f),
    );
  }

  /// 네 모서리와 가장자리에서 안쪽으로 자라는 서리 결정.
  void _frost(Canvas canvas, Size size, double t) {
    final rnd = Random(7);
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..strokeCap = StrokeCap.round;
    final seeds = <(Offset, double)>[
      (Offset.zero, pi / 4),
      (Offset(size.width, 0), 3 * pi / 4),
      (Offset(0, size.height), -pi / 4),
      (Offset(size.width, size.height), -3 * pi / 4),
      for (var i = 1; i < 8; i++) ...[
        (Offset(size.width * i / 8, 0), pi / 2),
        (Offset(size.width * i / 8 + 18, size.height), -pi / 2),
      ],
      (Offset(0, size.height / 2), 0),
      (Offset(size.width, size.height / 2), pi),
    ];
    for (var i = 0; i < seeds.length; i++) {
      // 결정마다 조금씩 늦게 자란다.
      final start = i / seeds.length * 0.35;
      final g = ((t - start) / (1 - start)).clamp(0.0, 1.0);
      if (g == 0) continue;
      final (origin, angle) = seeds[i];
      final corner = i < 4;
      final length =
          (corner ? 58.0 : 20.0 + rnd.nextDouble() * 16) *
          Curves.easeOutCubic.transform(g);
      final jitter = (rnd.nextDouble() - 0.5) * 0.5;
      _branch(canvas, paint, origin, angle + jitter, length, corner ? 3 : 2);
    }
  }

  void _branch(
    Canvas canvas,
    Paint paint,
    Offset from,
    double angle,
    double length,
    int depth,
  ) {
    if (length < 2) return;
    final to = from + Offset(cos(angle), sin(angle)) * length;
    paint.strokeWidth = depth * 0.7 + 0.4;
    canvas.drawLine(from, to, paint);
    if (depth == 0) return;
    for (var k = 1; k <= 3; k++) {
      final p = Offset.lerp(from, to, k / 4)!;
      final side = length * (0.42 - k * 0.08);
      _branch(canvas, paint, p, angle + pi / 3, side, depth - 1);
      _branch(canvas, paint, p, angle - pi / 3, side, depth - 1);
    }
  }

  /// 상자 안에 흩어진 작은 눈송이.
  void _snowflakes(Canvas canvas, Size size, double t) {
    final rnd = Random(3);
    final paint = Paint()
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 7; i++) {
      final c = Offset(
        size.width * (0.45 + rnd.nextDouble() * 0.52),
        size.height * (0.12 + rnd.nextDouble() * 0.76),
      );
      final g = ((t - 0.3 - i * 0.06) / 0.4).clamp(0.0, 1.0);
      if (g == 0) continue;
      final r = (4.0 + rnd.nextDouble() * 4) * Curves.easeOutBack.transform(g);
      paint.color = Colors.white.withValues(alpha: 0.95 * g);
      for (var a = 0; a < 6; a++) {
        final d = Offset(cos(a * pi / 3), sin(a * pi / 3));
        canvas.drawLine(c - d * r, c + d * r, paint);
      }
    }
  }

  /// 녹을 때 아래에서 올라오는 따뜻한 주황빛.
  void _warmth(Canvas canvas, Size size, double t) {
    final glow = sin(pi * t);
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, 1.2),
          radius: 1.4,
          colors: [
            _warm.withValues(alpha: 0.6 * glow),
            _warm.withValues(alpha: 0),
          ],
        ).createShader(rect),
    );
  }

  /// 위에서 아래로 흘러내리는 물방울.
  void _drops(Canvas canvas, Size size, double t) {
    final rnd = Random(11);
    for (var i = 0; i < 14; i++) {
      final x = size.width * (0.06 + rnd.nextDouble() * 0.88);
      final delay = rnd.nextDouble() * 0.35;
      final speed = 0.8 + rnd.nextDouble() * 0.6;
      final g = ((t - delay) / (1 - delay)).clamp(0.0, 1.0);
      if (g == 0) continue;
      final y = -6 + Curves.easeIn.transform(g) * (size.height + 12) * speed;
      final r = 3.0 + rnd.nextDouble() * 2.4;
      final fade = (1 - g).clamp(0.0, 1.0);
      // 지나간 자국.
      canvas.drawLine(
        Offset(x, max(0, y - 22)),
        Offset(x, y),
        Paint()
          ..strokeWidth = r * 0.7
          ..strokeCap = StrokeCap.round
          ..color = iceDeep.withValues(alpha: 0.12 * fade),
      );
      final drop = Path()
        ..moveTo(x, y - r * 2.2)
        ..quadraticBezierTo(x + r, y - r * 0.6, x + r, y)
        ..arcToPoint(Offset(x - r, y), radius: Radius.circular(r))
        ..quadraticBezierTo(x - r, y - r * 0.6, x, y - r * 2.2)
        ..close();
      canvas.drawPath(
        drop,
        Paint()..color = const Color(0xFF6FB3E0).withValues(alpha: 0.85 * fade),
      );
      canvas.drawCircle(
        Offset(x - r * 0.35, y - r * 0.3),
        r * 0.3,
        Paint()..color = Colors.white.withValues(alpha: 0.8 * fade),
      );
    }
  }

  @override
  bool shouldRepaint(IcePainter old) =>
      old.freeze != freeze || old.thaw != thaw || old.base != base;
}
