// 앱을 덜 심심하게 만드는 짧은 효과들. 모두 해당 부분 안에서만 움직이고,
// 휴대폰의 "애니메이션 줄이기"가 켜져 있으면 움직이지 않고 결과만 보여준다.
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

/// 휴대폰 설정에서 애니메이션을 줄였으면 true.
bool calmMotion(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// 숫자가 이전 값에서 새 값으로 빠르게 굴러가며 바뀐다.
class RollingNumber extends StatelessWidget {
  const RollingNumber({
    super.key,
    required this.value,
    required this.format,
    this.style,
  });
  final int value;
  final String Function(int value) format;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    if (calmMotion(context)) return Text(format(value), style: style);
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value.toDouble()),
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text(format(v.round()), style: style),
    );
  }
}

/// 누르면 살짝 작아졌다 돌아오고 가볍게 진동한다. 주요 버튼을 감싼다.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child});
  final Widget child;
  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool down = false;

  void set(bool value) {
    if (down == value) return;
    setState(() => down = value);
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) {
      HapticFeedback.selectionClick();
      set(true);
    },
    onPointerUp: (_) => set(false),
    onPointerCancel: (_) => set(false),
    child: AnimatedScale(
      scale: down && !calmMotion(context) ? 0.96 : 1,
      duration: const Duration(milliseconds: 110),
      curve: Curves.easeOut,
      child: widget.child,
    ),
  );
}

/// 처음 그려질 때 위에서 살짝 떨어지며 나타난다. [animate]가 false면 그대로 보인다.
class DropIn extends StatelessWidget {
  const DropIn({super.key, required this.child, this.animate = true});
  final Widget child;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    if (!animate || calmMotion(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutBack,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0, 1),
        child: Transform.translate(
          offset: Offset(0, -24 * (1 - t)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// 빨간 "송금완료" 도장. [paid]가 false → true로 바뀌면 "쿵" 찍히며 진동한다.
class PaidStamp extends StatefulWidget {
  const PaidStamp({super.key, required this.paid, this.size = 56});
  final bool paid;
  final double size;
  @override
  State<PaidStamp> createState() => _PaidStampState();
}

class _PaidStampState extends State<PaidStamp>
    with SingleTickerProviderStateMixin {
  late final AnimationController hit = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
    value: 1,
  );

  @override
  void didUpdateWidget(PaidStamp old) {
    super.didUpdateWidget(old);
    if (!old.paid && widget.paid) {
      hit.forward(from: 0).then((_) {
        if (mounted) HapticFeedback.heavyImpact();
      });
    }
  }

  @override
  void dispose() {
    hit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    if (!widget.paid) return SizedBox(width: s, height: s);
    return AnimatedBuilder(
      animation: hit,
      builder: (context, child) {
        // 크게 떠 있다가 내려찍히고 살짝 튄다.
        final t = calmMotion(context) ? 1.0 : hit.value;
        final scale = t < 0.6
            ? 2.2 - 1.3 * Curves.easeIn.transform(t / 0.6)
            : 0.9 + 0.1 * Curves.easeOut.transform((t - 0.6) / 0.4);
        return Opacity(
          opacity: (t * 2.5).clamp(0, 1),
          child: Transform.rotate(
            angle: -0.21,
            child: Transform.scale(scale: scale, child: child),
          ),
        );
      },
      child: Container(
        width: s,
        height: s,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: toongDanger, width: 2.4),
        ),
        child: Container(
          width: s - 8,
          height: s - 8,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: toongDanger, width: 1),
          ),
          child: Text(
            '송금\n완료',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: toongDanger,
              fontWeight: FontWeight.w900,
              fontSize: s * 0.22,
              height: 1.05,
            ),
          ),
        ),
      ),
    );
  }
}

/// [child] 영역 안에서만 종이 조각을 한 번 흩날린다. [burst]가 바뀔 때마다 다시 터진다.
/// 0이면 터지지 않는다.
class ConfettiBurst extends StatefulWidget {
  const ConfettiBurst({
    super.key,
    required this.child,
    required this.burst,
    this.count = 46,
  });
  final Widget child;
  final int burst;
  final int count;
  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<ConfettiBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController run = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void initState() {
    super.initState();
    if (widget.burst > 0) _start();
  }

  @override
  void didUpdateWidget(ConfettiBurst old) {
    super.didUpdateWidget(old);
    if (widget.burst != old.burst && widget.burst > 0) _start();
  }

  void _start() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || calmMotion(context)) return;
      HapticFeedback.mediumImpact();
      run.forward(from: 0);
    });
  }

  @override
  void dispose() {
    run.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      widget.child,
      Positioned.fill(
        child: IgnorePointer(
          child: ClipRect(
            child: AnimatedBuilder(
              animation: run,
              builder: (context, _) => run.isAnimating
                  ? CustomPaint(
                      painter: _ConfettiPainter(
                        t: run.value,
                        seed: widget.burst,
                        count: widget.count,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    ],
  );
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({required this.t, required this.seed, required this.count});
  final double t;
  final int seed;
  final int count;

  static const colors = [toongInk, Color(0xFF8A8A86), toongDanger];

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = Random(seed);
    final fade = t < 0.75 ? 1.0 : (1 - t) / 0.25;
    for (var i = 0; i < count; i++) {
      // 위쪽 가운데 근처에서 위로 터졌다가 떨어진다.
      final x0 = size.width * (0.3 + rnd.nextDouble() * 0.4);
      final y0 = size.height * (0.15 + rnd.nextDouble() * 0.2);
      final vx = (rnd.nextDouble() - 0.5) * size.width * 1.1;
      final vy = -size.height * (0.35 + rnd.nextDouble() * 0.5);
      final g = size.height * 1.6;
      final x = x0 + vx * t;
      final y = y0 + vy * t + g * t * t;
      final w = 4 + rnd.nextDouble() * 5;
      final h = w * (0.4 + rnd.nextDouble() * 0.5);
      final spin = (rnd.nextDouble() - 0.5) * 14;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(spin * t + rnd.nextDouble() * pi);
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: w, height: h),
        Paint()..color = colors[i % colors.length].withValues(alpha: fade),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t || old.seed != seed;
}

/// 빈 화면 그림: 위아래가 찢긴 빈 영수증과 한 줄 문구.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.message, this.hint});
  final String message;
  final String? hint;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 28),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 76,
          height: 96,
          child: CustomPaint(painter: _EmptyReceiptPainter()),
        ),
        const SizedBox(height: 14),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        if (hint != null) ...[
          const SizedBox(height: 4),
          Text(
            hint!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: toongSub, fontSize: 13),
          ),
        ],
      ],
    ),
  );
}

class _EmptyReceiptPainter extends CustomPainter {
  const _EmptyReceiptPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const teeth = 6;
    final w = size.width, h = size.height, d = 6.0;
    final step = w / teeth;
    final path = Path()..moveTo(0, d);
    for (var i = 0; i < teeth; i++) {
      path
        ..lineTo((i + 0.5) * step, 0)
        ..lineTo((i + 1) * step, d);
    }
    path.lineTo(w, h - d);
    for (var i = teeth; i > 0; i--) {
      path
        ..lineTo((i - 0.5) * step, h)
        ..lineTo((i - 1) * step, h - d);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = toongSoft);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..color = toongInk,
    );
    final line = Paint()
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = toongLine;
    for (final (y, len) in [(0.3, 0.6), (0.45, 0.45), (0.6, 0.55)]) {
      canvas.drawLine(
        Offset(w * 0.2, h * y),
        Offset(w * (0.2 + len), h * y),
        line,
      );
    }
    // 아래쪽 점선(합계 칸).
    for (var x = w * 0.2; x < w * 0.8; x += 7) {
      canvas.drawLine(Offset(x, h * 0.76), Offset(x + 3, h * 0.76), line);
    }
  }

  @override
  bool shouldRepaint(_EmptyReceiptPainter old) => false;
}

/// 화면 전환: 오른쪽에서 살짝 밀려오며 서서히 나타난다.
class SoftSlideTransitions extends PageTransitionsBuilder {
  const SoftSlideTransitions();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    final back = CurvedAnimation(
      parent: secondaryAnimation,
      curve: Curves.easeOutCubic,
    );
    return SlideTransition(
      position: Tween(
        begin: Offset.zero,
        end: const Offset(-0.06, 0),
      ).animate(back),
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0.12, 0),
          end: Offset.zero,
        ).animate(curved),
        child: FadeTransition(opacity: curved, child: child),
      ),
    );
  }
}

/// 시작 화면 로고: 4조각이 흩어져 있다가 "착" 모인다. [play]가 false면 모인 채로 보인다.
class LogoIntro extends StatelessWidget {
  const LogoIntro({super.key, required this.play, this.size = 64});
  final bool play;
  final double size;

  @override
  Widget build(BuildContext context) {
    Widget piece(Alignment corner, double t) {
      final spread = (1 - t) * size * 0.45;
      return Positioned.fill(
        child: Transform.translate(
          offset: Offset(corner.x * spread, corner.y * spread),
          child: ClipRect(
            clipper: _Quarter(corner),
            child: Image.asset('assets/logo.png', width: size, height: size),
          ),
        ),
      );
    }

    Widget logo(double t) => SizedBox(
      width: size,
      height: size,
      child: Opacity(
        opacity: t.clamp(0, 1),
        child: Stack(
          children: [
            for (final c in const [
              Alignment.topLeft,
              Alignment.topRight,
              Alignment.bottomLeft,
              Alignment.bottomRight,
            ])
              piece(c, t),
          ],
        ),
      ),
    );

    if (!play || calmMotion(context)) {
      return Semantics(
        label: '퉁 로고',
        child: Image.asset('assets/logo.png', width: size, height: size),
      );
    }
    return Semantics(
      label: '퉁 로고',
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 650),
        curve: Curves.easeOutBack,
        builder: (context, t, _) => logo(t),
        onEnd: HapticFeedback.lightImpact,
      ),
    );
  }
}

class _Quarter extends CustomClipper<Rect> {
  const _Quarter(this.corner);
  final Alignment corner;
  @override
  Rect getClip(Size size) => Rect.fromLTWH(
    corner.x < 0 ? 0 : size.width / 2,
    corner.y < 0 ? 0 : size.height / 2,
    size.width / 2,
    size.height / 2,
  );
  @override
  bool shouldReclip(_Quarter old) => old.corner != corner;
}
