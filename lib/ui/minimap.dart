import 'dart:math';

import 'package:flutter/material.dart';

import '../game/config.dart';
import '../game/entities.dart';
import '../game/game_map.dart';
import '../game/poly_empire_game.dart';
import '../game/world.dart';

/// Diamond-shaped minimap matching the isometric view.
class Minimap extends StatelessWidget {
  final PolyEmpireGame game;
  final double width;
  const Minimap({super.key, required this.game, required this.width});

  @override
  Widget build(BuildContext context) {
    final side = width / sqrt2;
    void go(Offset local) {
      final n = GameWorld.mapSize;
      game.centerOn(local.dx / side * n, local.dy / side * n);
    }

    return Container(
      width: width + 12,
      height: width / 2 + 12,
      decoration: BoxDecoration(
        color: const Color(0xCC10141B),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF3A4556)),
      ),
      padding: const EdgeInsets.all(6),
      child: SizedBox(
        width: width,
        height: width / 2,
        child: Center(
          child: OverflowBox(
            maxWidth: side,
            maxHeight: side,
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..scale(1.0, 0.5)
                ..rotateZ(pi / 4),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => go(d.localPosition),
                onPanUpdate: (d) => go(d.localPosition),
                child: CustomPaint(
                  size: Size(side, side),
                  painter: _MinimapPainter(game),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MinimapPainter extends CustomPainter {
  final PolyEmpireGame game;
  _MinimapPainter(this.game);

  @override
  void paint(Canvas canvas, Size size) {
    final w = game.sim;
    if (w == null) return;
    final n = GameWorld.mapSize;
    final c = size.width / n;
    final paint = Paint();
    canvas.drawRect(Offset.zero & size, paint..color = const Color(0xFF2E3644));
    for (int y = 0; y < n; y++) {
      for (int x = 0; x < n; x++) {
        final i = w.map.idx(x, y);
        if (w.explored[i] == 0) continue;
        Color col = switch (w.map.terrain[i]) {
          Terrain.grass => const Color(0xFF6FA84A),
          Terrain.dirt => const Color(0xFFA08A5E),
          Terrain.sand => const Color(0xFFD6C27F),
          Terrain.water => const Color(0xFF3A7FC0),
        };
        final e = w.map.occupant[i];
        if (e is ResourceNode) {
          col = switch (e.kind) {
            ResourceKind.tree => const Color(0xFF2C6A2E),
            ResourceKind.gold => const Color(0xFFF0C030),
            ResourceKind.stone => const Color(0xFFB0B4B8),
            ResourceKind.berries => const Color(0xFFD04A6A),
          };
        }
        if (w.visible[i] == 0) col = Color.lerp(Colors.black, col, 0.6)!;
        paint.color = col;
        canvas.drawRect(Rect.fromLTWH(x * c, y * c, c + 0.4, c + 0.4), paint);
      }
    }
    for (final b in w.buildings) {
      if (!b.alive) continue;
      if (b.owner != GameWorld.human &&
          w.explored[w.map.idx(b.tx, b.ty)] == 0) {
        continue;
      }
      paint.color = w.players[b.owner].color;
      canvas.drawRect(
          Rect.fromLTWH(b.tx * c, b.ty * c, b.size * c, b.size * c), paint);
    }
    for (final u in w.units) {
      if (!u.alive) continue;
      if (u.owner != GameWorld.human && !w.isVisibleTo(GameWorld.human, u)) {
        continue;
      }
      paint.color = Color.lerp(w.players[u.owner].color, Colors.white, 0.25)!;
      canvas.drawRect(
          Rect.fromCenter(
              center: Offset(u.x * c, u.y * c),
              width: c * 1.6,
              height: c * 1.6),
          paint);
    }
    // Alerts
    for (final m in w.messages) {
      if (!m.alert || m.x == null || w.time - m.time > 4) continue;
      final r = ((w.time - m.time) % 1) * 8 * c;
      canvas.drawCircle(
          Offset(m.x! * c, m.y! * c),
          r + c * 2,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = c
            ..color = Colors.redAccent);
    }
    // Camera view.
    final corners = game.viewCornersTiles();
    final path = Path()..moveTo(corners[0].dx * c, corners[0].dy * c);
    for (final p in corners.skip(1)) {
      path.lineTo(p.dx * c, p.dy * c);
    }
    path.close();
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = c * 0.8
          ..color = Colors.white);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
