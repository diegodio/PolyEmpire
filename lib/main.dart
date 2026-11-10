import 'dart:math';

import 'package:flame/game.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'game/config.dart';
import 'game/poly_empire_game.dart';
import 'ui/hud.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PolyEmpireApp());
}

class PolyEmpireApp extends StatelessWidget {
  const PolyEmpireApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PolyEmpire',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFE8C26A),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const GameScreen(),
    );
  }
}

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

enum _DragMode { none, pan, box, pinch }

class _GameScreenState extends State<GameScreen> {
  final game = PolyEmpireGame();
  final focus = FocusNode();

  PointerDeviceKind _kind = PointerDeviceKind.touch;
  int _buttons = kPrimaryButton;
  _DragMode _mode = _DragMode.none;
  Offset _dragStart = Offset.zero;
  double _lastScale = 1;

  @override
  void dispose() {
    focus.dispose();
    super.dispose();
  }

  bool get _mouse => _kind == PointerDeviceKind.mouse;

  void _onScaleStart(ScaleStartDetails d) {
    if (!game.started) return;
    _lastScale = 1;
    _dragStart = d.localFocalPoint;
    if (d.pointerCount >= 2) {
      _mode = _DragMode.pinch;
    } else if ((_mouse && _buttons == kPrimaryButton) ||
        (!_mouse && game.boxSelectMode)) {
      _mode = _DragMode.box;
    } else {
      _mode = _DragMode.pan;
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (!game.started) return;
    if (d.pointerCount >= 2 && _mode != _DragMode.pinch) {
      _mode = _DragMode.pinch;
      game.dragRect = null;
      _lastScale = d.scale;
    }
    switch (_mode) {
      case _DragMode.pinch:
        final f = d.scale / _lastScale;
        _lastScale = d.scale;
        game.zoomAt(f, d.localFocalPoint);
        game.pan(d.focalPointDelta);
      case _DragMode.box:
        game.dragRect = Rect.fromPoints(_dragStart, d.localFocalPoint);
        game.hover(d.localFocalPoint);
      case _DragMode.pan:
        game.pan(d.focalPointDelta);
      case _DragMode.none:
        break;
    }
  }

  void _onScaleEnd(ScaleEndDetails d) {
    if (_mode == _DragMode.box && game.dragRect != null) {
      final r = game.dragRect!;
      if (r.width > 6 || r.height > 6) game.selectInRect(r);
    }
    game.dragRect = null;
    _mode = _DragMode.none;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (!game.started) return KeyEventResult.ignored;
    final k = e.logicalKey;
    String? dir;
    if (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.keyA)
      dir = 'left';
    if (k == LogicalKeyboardKey.arrowRight || k == LogicalKeyboardKey.keyD)
      dir = 'right';
    if (k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.keyW)
      dir = 'up';
    if (k == LogicalKeyboardKey.arrowDown || k == LogicalKeyboardKey.keyS)
      dir = 'down';
    if (dir != null) {
      if (e is KeyUpEvent) {
        game.heldKeys.remove(dir);
      } else {
        game.heldKeys.add(dir);
      }
      return KeyEventResult.handled;
    }
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    if (k == LogicalKeyboardKey.escape) {
      if (game.placing != null) {
        game.placing = null;
      } else {
        game.selection.clear();
      }
    } else if (k == LogicalKeyboardKey.delete) {
      game.deleteSelection();
    } else if (k == LogicalKeyboardKey.keyH) {
      game.selectTownCenter();
    } else if (k == LogicalKeyboardKey.period) {
      game.selectNextIdleVillager();
    } else if (k == LogicalKeyboardKey.space) {
      game.simPaused = !game.simPaused;
    } else {
      return KeyEventResult.ignored;
    }
    game.hudTick.value++;
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1C222C),
      body: Focus(
        focusNode: focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Stack(
          children: [
            Positioned.fill(
              child: Listener(
                onPointerDown: (e) {
                  _kind = e.kind;
                  _buttons = e.buttons;
                  focus.requestFocus();
                },
                onPointerHover: (e) => game.hover(e.localPosition),
                onPointerSignal: (e) {
                  if (e is PointerScrollEvent && game.started) {
                    game.zoomAt(e.scrollDelta.dy > 0 ? 1 / 1.12 : 1.12,
                        e.localPosition);
                  }
                },
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) {
                    if (!game.started) return;
                    final touch = !_mouse;
                    if (touch && game.placing != null) {
                      // First tap previews, second tap on the same tile confirms.
                      final t = game.screenToTile(d.localPosition);
                      final tile = Point(t.dx.floor(), t.dy.floor());
                      if (game.hoverTile != tile) {
                        game.hoverTile = tile;
                        game.hudTick.value++;
                        return;
                      }
                    }
                    game.tap(d.localPosition,
                        mouse: _mouse,
                        shift: HardwareKeyboard.instance.isShiftPressed);
                    game.hudTick.value++;
                  },
                  onSecondaryTapUp: (d) {
                    game.secondaryTap(d.localPosition);
                    game.hudTick.value++;
                  },
                  onScaleStart: _onScaleStart,
                  onScaleUpdate: _onScaleUpdate,
                  onScaleEnd: _onScaleEnd,
                  child: GameWidget(game: game),
                ),
              ),
            ),
            Positioned.fill(
              child: ValueListenableBuilder<int>(
                valueListenable: game.hudTick,
                builder: (context, _, __) => game.started
                    ? Hud(game: game)
                    : MainMenu(onStart: (d) {
                        final q = Uri.base.queryParameters;
                        final seed = int.tryParse(q['seed'] ?? '');
                        game.startGame(
                            d, seed ?? DateTime.now().millisecondsSinceEpoch,
                            reveal: q['reveal'] == '1',
                            skipSeconds: double.tryParse(q['skip'] ?? '') ?? 0);
                        focus.requestFocus();
                      }),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MainMenu extends StatefulWidget {
  final void Function(Difficulty) onStart;
  const MainMenu({super.key, required this.onStart});

  @override
  State<MainMenu> createState() => _MainMenuState();
}

class _MainMenuState extends State<MainMenu> {
  Difficulty difficulty = Difficulty.normal;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF253247), Color(0xFF151A22)],
        ),
      ),
      child: Stack(children: [
        const Positioned.fill(child: CustomPaint(painter: _MenuBackdrop())),
        Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 460),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xE6151A23),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF3A4556)),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('POLYEMPIRE',
                    style: TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 4,
                        color: Color(0xFFE8C26A))),
                const Text('Estratégia em tempo real · low poly',
                    style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 20),
                const Text('Dificuldade',
                    style: TextStyle(color: Colors.white60)),
                const SizedBox(height: 8),
                SegmentedButton<Difficulty>(
                  segments: [
                    for (final d in Difficulty.values)
                      ButtonSegment(value: d, label: Text(difficultyNames[d]!)),
                  ],
                  selected: {difficulty},
                  onSelectionChanged: (s) =>
                      setState(() => difficulty = s.first),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Iniciar partida',
                        style: TextStyle(fontSize: 16)),
                    onPressed: () => widget.onStart(difficulty),
                  ),
                ),
                const SizedBox(height: 16),
                const ExpansionTile(
                  title: Text('Como jogar', style: TextStyle(fontSize: 14)),
                  childrenPadding: EdgeInsets.only(bottom: 8),
                  children: [
                    Text(helpText,
                        style: TextStyle(
                            fontSize: 12, height: 1.4, color: Colors.white70)),
                  ],
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

/// Decorative low-poly mountains for the menu.
class _MenuBackdrop extends CustomPainter {
  const _MenuBackdrop();

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = Random(7);
    final paint = Paint();
    for (int layer = 0; layer < 3; layer++) {
      final base = size.height * (0.55 + layer * 0.15);
      final color = Color.lerp(
          const Color(0xFF3A5A7A), const Color(0xFF2A4A2E), layer / 2)!;
      double x = -40;
      while (x < size.width + 40) {
        final w = 80.0 + rnd.nextDouble() * 140;
        final h = 60.0 + rnd.nextDouble() * 140 - layer * 20;
        final peak = Offset(x + w / 2, base - h);
        paint.color = Color.lerp(color, Colors.white, 0.08)!;
        canvas.drawPath(
            Path()
              ..moveTo(x, base)
              ..lineTo(peak.dx, peak.dy)
              ..lineTo(peak.dx, base)
              ..close(),
            paint);
        paint.color = Color.lerp(color, Colors.black, 0.25)!;
        canvas.drawPath(
            Path()
              ..moveTo(peak.dx, peak.dy)
              ..lineTo(x + w, base)
              ..lineTo(peak.dx, base)
              ..close(),
            paint);
        x += w * 0.7;
      }
      paint.color = Color.lerp(color, Colors.black, 0.35)!;
      canvas.drawRect(Rect.fromLTRB(0, base, size.width, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
