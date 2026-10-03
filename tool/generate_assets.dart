import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:football_manager_sim/ui/theme/app_theme.dart';

/// Store asset generator.
///
/// Run: `flutter test tool/generate_assets.dart`
/// Output: docs/store/assets/*.png
void main() {
  // One independent test per asset: each gets a fresh widget tree and view
  // state, which avoids cross-capture hangs in the test binding.
  testWidgets('icon-512', (tester) async {
    await _capture(
      tester,
      const _Icon(),
      const Size(512, 512),
      'docs/store/assets/icon-512.png',
    );
  });

  testWidgets('feature-graphic', (tester) async {
    await _capture(
      tester,
      const _FeatureGraphic(),
      const Size(1024, 512),
      'docs/store/assets/feature-graphic.png',
    );
  });

  for (final (index, builder) in _screenshotBuilders.indexed) {
    testWidgets('screenshot-${_shots[index].name}', (tester) async {
      await _capture(
        tester,
        builder(),
        const Size(1080, 1920),
        'docs/store/assets/screenshot-${_shots[index].name}.png',
      );
    });
  }

  test('asset directory exists', () {
    // Sanity marker so the suite is green even when only regenerating some
    // assets; real verification is the presence of the PNG files.
    expect(Directory('docs/store/assets').existsSync(), isTrue);
  });
}

Future<void> _capture(
  WidgetTester tester,
  Widget widget,
  Size size,
  String path,
) async {
  Directory('docs/store/assets').createSync(recursive: true);
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  tester.platformDispatcher.textScaleFactorTestValue = 1.0;

  final key = GlobalKey();
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: const MediaQueryData(size: Size(1080, 1920)),
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: RepaintBoundary(key: key, child: widget),
        ),
      ),
    ),
  );
  // Fixed pumps instead of pumpAndSettle: nested MaterialApps in the
  // screenshot previews can keep scheduling frames and never settle.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));

  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  // toImage talks to the real raster thread, so it must run outside the
  // test binding's fake-async zone via runAsync.
  final bytes = await tester.runAsync<Uint8List>(() async {
    final image = await boundary.toImage(pixelRatio: 1.0);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  });
  File(path).writeAsBytesSync(bytes!);
  debugPrint('Wrote $path (${bytes.length} bytes)');
}

// ---------------------------------------------------------------------------
// Shared premium canvas
// ---------------------------------------------------------------------------

class _Canvas extends StatelessWidget {
  const _Canvas({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0B1220),
            Color(0xFF0F1B2E),
            Color(0xFF122240),
          ],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Radial pitch-green glow, top-left
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(-0.7, -0.8),
                radius: 1.1,
                colors: [
                  Color(0x3300C853),
                  Color(0x0000C853),
                ],
              ),
            ),
          ),
          // Cool secondary glow, bottom-right
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0.8, 0.9),
                radius: 1.0,
                colors: [
                  Color(0x2640C4FF),
                  Color(0x0040C4FF),
                ],
              ),
            ),
          ),
          child,
          const DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  radius: 1.4,
                  colors: [
                    Color(0x00000000),
                    Color(0x66000000),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Subtle pitch-line texture layer.
class _PitchLines extends StatelessWidget {
  const _PitchLines();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _PitchLinesPainter(),
      size: Size.infinite,
    );
  }
}

class _PitchLinesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x1400C853)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    // Perspective pitch lines: horizontal lines with increasing spacing.
    var y = size.height * 0.55;
    var gap = 14.0;
    while (y < size.height) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      y += gap;
      gap *= 1.25;
    }

    // Center circle arcs (perspective ellipses).
    final center = Offset(size.width * 0.5, size.height * 0.52);
    for (final rx in [90.0, 160.0, 250.0]) {
      canvas.drawOval(
        Rect.fromCenter(center: center, width: rx * 2, height: rx * 0.55),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// 1. App icon — layered shield + ball
// ---------------------------------------------------------------------------

class _Icon extends StatelessWidget {
  const _Icon();

  @override
  Widget build(BuildContext context) {
    return const _Canvas(
      child: Center(
        child: _Shield(),
      ),
    );
  }
}

class _Shield extends StatelessWidget {
  const _Shield();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 340,
      height: 340,
      child: CustomPaint(
        painter: _ShieldPainter(),
        child: const Center(child: _Ball(size: 150)),
      ),
    );
  }
}

class _ShieldPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Drop shadow
    final shieldPath = _shieldPath(w, h);
    canvas.drawShadow(shieldPath, Colors.black, 24, false);

    // Shield body: multi-stop gradient with green edge
    final paint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF18243A),
          Color(0xFF0B1220),
          Color(0xFF0F1930),
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawPath(shieldPath, paint);

    // Green rim light (left-top edge)
    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF00E676), Color(0x1400C853)],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawPath(shieldPath, rim);
  }

  Path _shieldPath(double w, double h) {
    final path = Path()
      ..moveTo(w * 0.5, h * 0.03)
      ..lineTo(w * 0.92, h * 0.18)
      ..cubicTo(w * 0.94, h * 0.5, w * 0.88, h * 0.78, w * 0.5, h * 0.97)
      ..cubicTo(w * 0.12, h * 0.78, w * 0.06, h * 0.5, w * 0.08, h * 0.18)
      ..close();
    return path;
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _Ball extends StatelessWidget {
  const _Ball({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _BallPainter()),
    );
  }
}

class _BallPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width * 0.46;

    // Ball base with subtle top-light gradient.
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.3),
          colors: [Colors.grey.shade100, Colors.grey.shade400],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );

    final line = Paint()
      ..color = const Color(0xFF0B1220)
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.09;

    // Center pentagon.
    final pentagon = _polygon(c.translate(0, -r * 0.05), r * 0.32, 5, -1.5708);
    canvas.drawPath(pentagon, Paint()..color = const Color(0xFF0B1220));

    // Spokes to the ball edge.
    for (var i = 0; i < 5; i++) {
      final angle = -1.5708 + i * (2 * 3.14159 / 5) + 0.6283;
      final inner = Offset(
        c.dx + (r * 0.32) * _cos(angle),
        c.dy - r * 0.05 + (r * 0.32) * _sin(angle),
      );
      final outer = Offset(
        c.dx + r * 0.95 * _cos(angle),
        c.dy - r * 0.05 + r * 0.95 * _sin(angle),
      );
      canvas.drawLine(inner, outer, line);
    }
    canvas.drawCircle(c, r, line);
  }

  double _cos(double a) => _cosImpl(a);
  double _sin(double a) => _sinImpl(a);

  static double _cosImpl(double a) {
    // dart:math import kept out of painter for brevity; use internal approx.
    a = a % (2 * 3.141592653589793);
    return _trig(a, true);
  }

  static double _sinImpl(double a) {
    a = a % (2 * 3.141592653589793);
    return _trig(a - 1.5707963267948966, true);
  }

  static double _trig(double x, bool _) {
    // Taylor series approximation is fine for drawing.
    var term = 1.0;
    var sum = 1.0;
    for (var i = 1; i < 12; i++) {
      term *= -x * x / ((2 * i - 1) * (2 * i));
      sum += term;
    }
    return sum;
  }

  Path _polygon(Offset center, double radius, int sides, double startAngle) {
    final path = Path();
    for (var i = 0; i <= sides; i++) {
      final angle = startAngle + i * (2 * 3.141592653589793 / sides);
      final p = Offset(
        center.dx + radius * _cosImpl(angle),
        center.dy + radius * _sinImpl(angle),
      );
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// 2. Feature graphic 1024×512
// ---------------------------------------------------------------------------

class _FeatureGraphic extends StatelessWidget {
  const _FeatureGraphic();

  @override
  Widget build(BuildContext context) {
    return const _Canvas(
      child: Stack(
        fit: StackFit.expand,
        children: [
          _PitchLines(),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _GlassTitle(),
                SizedBox(height: 18),
                _Tagline(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassTitle extends StatelessWidget {
  const _GlassTitle();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 44, vertical: 22),
      decoration: BoxDecoration(
        color: const Color(0x1418243A),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0x3300C853), width: 1.5),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 30,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: const Text(
        'TOUCHLINE LEGEND',
        style: TextStyle(
          color: Colors.white,
          fontSize: 52,
          fontWeight: FontWeight.w900,
          letterSpacing: 6,
          shadows: [
            Shadow(color: Color(0x8800C853), blurRadius: 28),
          ],
        ),
      ),
    );
  }
}

class _Tagline extends StatelessWidget {
  const _Tagline();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'Your Tactics. Your Club. Your Legacy.',
      style: TextStyle(
        color: Color(0xFF9FB3CE),
        fontSize: 22,
        fontWeight: FontWeight.w500,
        letterSpacing: 2.5,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 3. Phone screenshots — real app widgets in a premium frame
// ---------------------------------------------------------------------------

class _Shot {
  const _Shot(this.name, this.title, this.caption);
  final String name;
  final String title;
  final String caption;
}

final List<_Shot> _shots = [
  _Shot('dashboard', 'Command your season', 'Standings · Form · Finances'),
  _Shot('match', 'Live match ticker', 'Goals · Momentum · Half-time calls'),
  _Shot('squad', 'Master your squad', 'Transfers · Tactics · Youth'),
];

final List<Widget Function()> _screenshotBuilders = [
  () => _ScreenshotFrame(shot: _shots[0], child: _DashboardPreview()),
  () => _ScreenshotFrame(shot: _shots[1], child: _MatchPreview()),
  () => _ScreenshotFrame(shot: _shots[2], child: _SquadPreview()),
];

class _ScreenshotFrame extends StatelessWidget {
  const _ScreenshotFrame({required this.child, required this.shot});

  final Widget child;
  final _Shot shot;

  @override
  Widget build(BuildContext context) {
    return _Canvas(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 150, vertical: 110),
        child: Column(
          children: [
            Text(
              shot.title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 44,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              shot.caption,
              style: const TextStyle(
                color: Color(0xFF00C853),
                fontSize: 20,
                fontWeight: FontWeight.w600,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 36),
            // Phone frame
            Expanded(
              child: Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(48),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x88000000),
                          blurRadius: 60,
                          offset: Offset(0, 24),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(48),
                      child: Container(
                        color: AppTheme.navy,
                        padding: const EdgeInsets.all(10),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(38),
                          child: FittedBox(
                            fit: BoxFit.fill,
                            child: SizedBox(
                              width: 390,
                              height: 780,
                              child: child,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Real app surfaces, mini-scaled for the phone frame.
ThemeData _shotTheme() => AppTheme.dark();

class _DashboardPreview extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _shotTheme(),
      home: Scaffold(
        appBar: AppBar(title: const Text('Home')),
        body: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Real Madrid C.F.',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text('La Liga · Matchday 12 of 38',
                        style: TextStyle(color: Colors.white54, fontSize: 11)),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: 0.32,
                        minHeight: 6,
                        backgroundColor: Colors.white10,
                        valueColor: const AlwaysStoppedAnimation(AppTheme.pitchGreen),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _statCard('Position', '3rd')),
                const SizedBox(width: 8),
                Expanded(child: _statCard('Points', '27')),
                const SizedBox(width: 8),
                Expanded(child: _statCard('Form', '7W 2D')),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _statCard('Budget', '€84M')),
                const SizedBox(width: 8),
                Expanded(child: _statCard('Wages', '€2.1M')),
              ],
            ),
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    _row('1', 'FC Barcelona', '31', true),
                    _row('2', 'Atlético Madrid', '29', false),
                    _row('3', 'Real Madrid C.F.', '27', true),
                    _row('4', 'Athletic Club', '25', false),
                    _row('5', 'Real Sociedad', '22', false),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statCard(String label, String value) => Card(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label.toUpperCase(),
                  style: TextStyle(color: Colors.white38, fontSize: 8.5, letterSpacing: 1)),
              const SizedBox(height: 4),
              Text(value,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      );

  Widget _row(String pos, String name, String pts, bool highlight) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: [
            SizedBox(
                width: 18,
                child: Text(pos,
                    style: TextStyle(fontSize: 11, color: Colors.white38))),
            Expanded(
              child: Text(
                name,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: highlight ? FontWeight.w700 : FontWeight.w400,
                  color: highlight ? AppTheme.pitchGreen : null,
                ),
              ),
            ),
            Text('$pts pts',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ],
        ),
      );
}

class _MatchPreview extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _shotTheme(),
      home: Scaffold(
        appBar: AppBar(title: const Text('Live · 67\'')),
        body: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Flexible(
                    child: Text('Real Madrid',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Text('2 - 1',
                        style: TextStyle(
                          fontSize: 38,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        )),
                  ),
                  const Flexible(
                    child: Text('Barcelona',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: 0.68,
                        minHeight: 8,
                        backgroundColor: Colors.white10,
                        valueColor: const AlwaysStoppedAnimation(AppTheme.pitchGreen),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: 0.34,
                        minHeight: 8,
                        backgroundColor: Colors.white10,
                        valueColor: const AlwaysStoppedAnimation(Color(0xFFEF5350)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  children: [
                    _event("67'", Icons.sports_soccer, 'GOAL! Mbappé slots it home', AppTheme.pitchGreen),
                    _event("61'", Icons.bolt, 'Sublime through ball splits the press', Color(0xFF40C4FF)),
                    _event("58'", Icons.style, 'Yellow card — tactical foul on the break', Color(0xFFFFB74D)),
                    _event("45'", Icons.sports, 'Half-time team talk applied', Colors.white38),
                    _event("39'", Icons.sports_soccer, 'GOAL! Lewandowski equalizes', AppTheme.pitchGreen),
                    _event("12'", Icons.sports_soccer, 'GOAL! Vinícius opens the scoring', AppTheme.pitchGreen),
                  ].reversed.toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _event(String minute, IconData icon, String text, Color color) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 30, child: Text(minute, style: const TextStyle(fontSize: 10, color: Colors.white38))),
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 11.5))),
          ],
        ),
      );
}

class _SquadPreview extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final players = [
      ('K. Mbappé', 'ST', 91, 98),
      ('J. Bellingham', 'CM', 89, 96),
      ('Vinícius Jr.', 'LW', 89, 95),
      ('T. Courtois', 'GK', 88, 93),
      ('A. Rüdiger', 'CB', 86, 88),
      ('F. Valverde', 'CM', 86, 89),
      ('Rodrygo', 'RW', 84, 88),
      ('M. Díaz', 'LB', 78, 81),
    ];

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _shotTheme(),
      home: DefaultTabController(
        length: 3,
        child: Scaffold(
        appBar: AppBar(
          title: const Text('Real Madrid'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.groups, size: 18), text: 'Squad'),
              Tab(icon: Icon(Icons.swap_horiz, size: 18), text: 'Market'),
              Tab(icon: Icon(Icons.flag, size: 18), text: 'Tactics'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            ListView(
              padding: const EdgeInsets.all(12),
              children: [
                for (final (name, pos, ovr, fitness) in players)
                  Card(
                    child: ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        radius: 16,
                        backgroundColor: AppTheme.pitchGreen.withValues(alpha: 0.16),
                        child: Text(
                          name.split(' ').map((w) => w[0]).take(2).join(),
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                        ),
                      ),
                      title: Text(name,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      subtitle: Text('$pos · Fitness $fitness',
                          style: const TextStyle(fontSize: 10.5, color: Colors.white38)),
                      trailing: Container(
                        width: 34,
                        height: 34,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppTheme.ovrColor(ovr).withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: AppTheme.ovrColor(ovr).withValues(alpha: 0.5)),
                        ),
                        child: Text('$ovr',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: Color.lerp(AppTheme.ovrColor(ovr), Colors.white, 0.55),
                            )),
                      ),
                    ),
                  ),
              ],
            ),
            const Center(child: Text('Market', style: TextStyle(color: Colors.white))),
            const Center(child: Text('Tactics', style: TextStyle(color: Colors.white))),
          ],
        ),
        ),
      ),
    );
  }
}
