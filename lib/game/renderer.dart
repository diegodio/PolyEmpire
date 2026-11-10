import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

import 'config.dart';
import 'entities.dart';
import 'game_map.dart';
import 'iso.dart';
import 'poly_empire_game.dart';
import 'world.dart';

const _grassA = Color(0xFF96CC62);
const _grassB = Color(0xFF79AD4A);
const _dirtA = Color(0xFFC2A46E);
const _dirtB = Color(0xFFA68857);
const _sandA = Color(0xFFEAD89A);
const _sandB = Color(0xFFD3BE7C);
const _waterA = Color(0xFF3F92D4);
const _waterB = Color(0xFF3786C6);
const _fogA = Color(0xFF3D4757);
const _fogB = Color(0xFF2C3341);

const _wallBeige = Color(0xFFDCC29A);
const _wallWood = Color(0xFFB98A58);
const _stoneWall = Color(0xFFB9B4A8);
const _darkStone = Color(0xFF8F8A80);
const _wood = Color(0xFF8A5A33);
const _skin = Color(0xFFF0C49A);

class WorldRenderer {
  final PolyEmpireGame game;
  final Poly p = Poly();
  WorldRenderer(this.game);

  GameWorld get w => game.sim!;

  // Reusable vertex buffers for the terrain.
  Float32List _pos = Float32List(0);
  Int32List _col = Int32List(0);

  void render(Canvas canvas, Size size) {
    if (game.sim == null) return;
    p.canvas = canvas;
    canvas.drawRect(
        Offset.zero & size, Paint()..color = const Color(0xFF1C222C));
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(game.zoom);
    canvas.translate(-game.camX, -game.camY);

    // Visible world rect in pixels.
    final halfW = size.width / 2 / game.zoom,
        halfH = size.height / 2 / game.zoom;
    final view = Rect.fromLTRB(game.camX - halfW - 80, game.camY - halfH - 40,
        game.camX + halfW + 80, game.camY + halfH + 120);

    _drawTerrain(canvas, view);
    _drawPlacement();
    _drawEntities(view);
    _drawProjectiles();
    _drawEffects();
    _drawOverlays(view);

    canvas.restore();

    // Selection rectangle (screen space).
    final sel = game.dragRect;
    if (sel != null) {
      canvas.drawRect(sel, Paint()..color = const Color(0x3346E06A));
      canvas.drawRect(
          sel,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = const Color(0xFF46E06A));
    }
  }

  // ---------------------------------------------------------------------------
  // Terrain
  // ---------------------------------------------------------------------------

  void _drawTerrain(Canvas canvas, Rect view) {
    final map = w.map;
    final n = map.size;
    // Tile bounds that may intersect the view.
    final c0 = unIso(view.left, view.top), c1 = unIso(view.right, view.top);
    final c2 = unIso(view.left, view.bottom),
        c3 = unIso(view.right, view.bottom);
    final minX = max(0, [c0.dx, c1.dx, c2.dx, c3.dx].reduce(min).floor() - 1);
    final maxX =
        min(n - 1, [c0.dx, c1.dx, c2.dx, c3.dx].reduce(max).ceil() + 1);
    final minY = max(0, [c0.dy, c1.dy, c2.dy, c3.dy].reduce(min).floor() - 1);
    final maxY =
        min(n - 1, [c0.dy, c1.dy, c2.dy, c3.dy].reduce(max).ceil() + 1);

    final count = (maxX - minX + 1) * (maxY - minY + 1);
    if (_pos.length < count * 12) {
      _pos = Float32List(count * 12);
      _col = Int32List(count * 6);
    }
    int vi = 0, ci = 0;
    final t = game.timeSeconds;
    for (int y = minY; y <= maxY; y++) {
      for (int x = minX; x <= maxX; x++) {
        final top = iso(x.toDouble(), y.toDouble());
        if (top.dx < view.left - hw || top.dx > view.right + hw) continue;
        if (top.dy < view.top - hh * 2 || top.dy > view.bottom) continue;
        final i = map.idx(x, y);
        final checker = (x + y) & 1 == 0;
        final explored = w.explored[i] == 1;
        final vis = w.visible[i] == 1;
        Color base;
        double lf = 1.03, rf = 0.95;
        if (!explored) {
          base = checker ? _fogA : _fogB;
          lf = 1.12;
          rf = 0.86;
        } else {
          switch (map.terrain[i]) {
            case Terrain.grass:
              base = checker ? _grassA : _grassB;
            case Terrain.dirt:
              base = checker ? _dirtA : _dirtB;
            case Terrain.sand:
              base = checker ? _sandA : _sandB;
            case Terrain.water:
              base = checker ? _waterA : _waterB;
              final s = sin(t * 1.6 + x * 0.8 + y * 0.55) * 0.06;
              lf += s;
              rf += s;
          }
          final v = 0.96 + map.shade[i] * 0.08;
          lf *= v;
          rf *= v;
          if (!vis) {
            lf *= 0.55;
            rf *= 0.55;
          }
        }
        final l = shadeColor(base, lf).value;
        final r = shadeColor(base, rf).value;
        final tx = top.dx, ty = top.dy;
        // Left triangle: top, bottom, left
        _pos[vi++] = tx;
        _pos[vi++] = ty;
        _pos[vi++] = tx;
        _pos[vi++] = ty + hh * 2;
        _pos[vi++] = tx - hw;
        _pos[vi++] = ty + hh;
        // Right triangle: top, right, bottom
        _pos[vi++] = tx;
        _pos[vi++] = ty;
        _pos[vi++] = tx + hw;
        _pos[vi++] = ty + hh;
        _pos[vi++] = tx;
        _pos[vi++] = ty + hh * 2;
        _col[ci++] = l;
        _col[ci++] = l;
        _col[ci++] = l;
        _col[ci++] = r;
        _col[ci++] = r;
        _col[ci++] = r;
      }
    }
    if (vi == 0) return;
    final verts = Vertices.raw(
      VertexMode.triangles,
      Float32List.sublistView(_pos, 0, vi),
      colors: Int32List.sublistView(_col, 0, ci),
    );
    canvas.drawVertices(verts, BlendMode.dst, Paint());
    verts.dispose();

    // Hover highlight.
    final h = game.hoverTile;
    if (h != null && game.placing == null && map.inBounds(h.x, h.y)) {
      p.outline(_tileDiamond(h.x.toDouble(), h.y.toDouble(), 1, 1),
          const Color(0x88FFFFFF), 1.2);
    }
  }

  List<Offset> _tileDiamond(double x, double y, double sx, double sy) => [
        iso(x, y),
        iso(x + sx, y),
        iso(x + sx, y + sy),
        iso(x, y + sy),
      ];

  void _drawPlacement() {
    final type = game.placing;
    final h = game.hoverTile;
    if (type == null || h == null) return;
    final s = buildingDefs[type]!.size;
    final tx = h.x - (s - 1) ~/ 2, ty = h.y - (s - 1) ~/ 2;
    final ok = game.canPlaceAt(type, tx, ty);
    for (int y = ty; y < ty + s; y++) {
      for (int x = tx; x < tx + s; x++) {
        final good = w.map.buildable(x, y) &&
            w.explored[w.map.idx(x.clamp(0, 63), y.clamp(0, 63))] == 1;
        p.fill(_tileDiamond(x.toDouble(), y.toDouble(), 1, 1),
            good ? const Color(0x6640E060) : const Color(0x77E04040));
      }
    }
    final ghost = Building(type: type, owner: 0, tx: tx, ty: ty, progress: 1);
    _drawBuildingShape(ghost, ok ? 0.55 : 0.3);
  }

  // ---------------------------------------------------------------------------
  // Entities
  // ---------------------------------------------------------------------------

  void _drawEntities(Rect view) {
    final list = <Entity>[];
    bool inView(double x, double y) {
      final s = iso(x, y);
      return view.contains(s);
    }

    for (final r in w.resources) {
      if (!inView(r.cx, r.cy)) continue;
      if (w.explored[w.map.idx(r.tx, r.ty)] == 0) continue;
      list.add(r);
    }
    for (final b in w.buildings) {
      if (!inView(b.cx, b.cy)) continue;
      if (b.owner != GameWorld.human && !_buildingExplored(b)) continue;
      list.add(b);
    }
    for (final u in w.units) {
      if (!inView(u.x, u.y)) continue;
      if (u.owner != GameWorld.human && !w.isVisibleTo(GameWorld.human, u)) {
        continue;
      }
      list.add(u);
    }
    // Farms are flat, draw them first.
    list.sort((a, b) {
      final fa = a is Building && a.type == BuildingType.farm;
      final fb = b is Building && b.type == BuildingType.farm;
      if (fa != fb) return fa ? -1 : 1;
      return a.depth().compareTo(b.depth());
    });
    final selected = game.selection.toSet();
    for (final e in list) {
      if (selected.contains(e)) _drawSelectionRing(e);
      if (e is ResourceNode) {
        _drawResource(e);
      } else if (e is Building) {
        _drawBuilding(e);
      } else if (e is Unit) {
        _drawUnit(e);
      }
    }
    // Health bars on top.
    for (final e in list) {
      if (e is ResourceNode) continue;
      final sel = selected.contains(e);
      if (!sel && e.hp >= e.maxHp) continue;
      if (e is Building && !e.complete && !sel) continue;
      _drawHealthBar(e);
    }
  }

  bool _buildingExplored(Building b) {
    for (int y = b.ty; y < b.ty + b.size; y++) {
      for (int x = b.tx; x < b.tx + b.size; x++) {
        if (w.explored[w.map.idx(x, y)] == 1) return true;
      }
    }
    return false;
  }

  Color _teamColor(int owner) =>
      owner < 0 ? const Color(0xFFE0D060) : w.players[owner].color;

  void _drawSelectionRing(Entity e) {
    final c = e.owner == GameWorld.human
        ? const Color(0xFF6CFF7A)
        : (e.owner < 0 ? const Color(0xFFFFE37A) : const Color(0xFFFF6A6A));
    if (e is Unit) {
      final b = iso(e.x, e.y);
      p.ovalStroke(b, e.def.cls == UnitClass.cavalry ? 15 : 11,
          e.def.cls == UnitClass.cavalry ? 7.5 : 5.5, c, 1.6);
    } else if (e is Building) {
      p.outline(
          _tileDiamond(e.minX, e.minY, e.size.toDouble(), e.size.toDouble()),
          c,
          2);
    } else if (e is ResourceNode) {
      p.outline(_tileDiamond(e.minX, e.minY, 1, 1), c, 1.6);
    }
  }

  void _drawHealthBar(Entity e) {
    double z;
    if (e is Unit) {
      z = e.def.cls == UnitClass.cavalry ? 36 : 30;
    } else {
      z = _buildingHeight((e as Building).type) + 10;
    }
    final c = iso(e.cx, e.cy, z);
    final wdt = e is Building ? 14.0 + e.size * 10 : 18.0;
    final frac = (e.hp / e.maxHp).clamp(0.0, 1.0);
    final r = Rect.fromLTWH(c.dx - wdt / 2, c.dy, wdt, 3.5);
    p.paint.color = const Color(0xCC000000);
    p.canvas.drawRect(r.inflate(1), p.paint);
    p.paint.color = frac > 0.5
        ? const Color(0xFF55E05A)
        : (frac > 0.25 ? const Color(0xFFF0C040) : const Color(0xFFE04040));
    p.canvas.drawRect(Rect.fromLTWH(r.left, r.top, wdt * frac, 3.5), p.paint);
    if (e.owner >= 0) {
      p.paint.color = _teamColor(e.owner);
      p.canvas.drawRect(Rect.fromLTWH(r.left - 4, r.top, 3, 3.5), p.paint);
    }
  }

  // --- Resources -------------------------------------------------------------

  void _drawResource(ResourceNode r) {
    final b = iso(r.cx, r.cy);
    final v = r.variant;
    switch (r.kind) {
      case ResourceKind.tree:
        p.oval(b.translate(1, 2), 13, 6, const Color(0x33000000));
        final chopped = r.amount < resourceKindAmount[ResourceKind.tree]!;
        p.box(r.cx - 0.05, r.cy - 0.05, r.cx + 0.05, r.cy + 0.05, 0, 12,
            const Color(0xFF7A4E2C));
        final green =
            Color.lerp(const Color(0xFF2F8A3A), const Color(0xFF4E9A2E), v)!;
        final s = (0.85 + v * 0.3) * (chopped ? 0.8 + r.amount / 500 : 1);
        if (v < 0.55) {
          // Pine: stacked cones.
          p.cone(b, 15 * s, 8 * s, 30 * s, shadeColor(green, 0.85));
          p.cone(b, 12 * s, 20 * s, 40 * s, green);
          p.cone(b, 8 * s, 31 * s, 48 * s, shadeColor(green, 1.12));
        } else {
          // Round deciduous: faceted blob.
          final c = b.translate(0, -26 * s);
          final rr = 14 * s;
          final pts = [
            c.translate(0, -rr * 1.1),
            c.translate(rr * 0.95, -rr * 0.35),
            c.translate(rr * 0.8, rr * 0.6),
            c.translate(0, rr * 0.95),
            c.translate(-rr * 0.85, rr * 0.55),
            c.translate(-rr, -rr * 0.3),
          ];
          final mid = c.translate(-rr * 0.15, -rr * 0.1);
          final shades = [1.25, 1.0, 0.78, 0.7, 0.92, 1.12];
          for (int i = 0; i < 6; i++) {
            p.fill(
                [mid, pts[i], pts[(i + 1) % 6]], shadeColor(green, shades[i]));
          }
        }
      case ResourceKind.gold:
      case ResourceKind.stone:
        final gold = r.kind == ResourceKind.gold;
        final col = gold ? const Color(0xFFE8B83A) : const Color(0xFFA3A8AE);
        final k = (0.6 + 0.4 * r.amount / resourceKindAmount[r.kind]!);
        p.oval(b.translate(0, 2), 18, 8, const Color(0x33000000));
        p.rock(b.translate(-7, -2), 9 * k, 14 * k, shadeColor(col, 0.9));
        p.rock(b.translate(6, 0), 10 * k, 18 * k, col);
        p.rock(b.translate(-1, 5), 7 * k, 10 * k, shadeColor(col, 1.05));
        if (gold && (game.timeSeconds * 2 + v * 10) % 3 < 0.25) {
          final s = b.translate(5, -16 * k);
          p.line(s.translate(-3, 0), s.translate(3, 0), const Color(0xFFFFFFFF),
              1.2);
          p.line(s.translate(0, -3), s.translate(0, 3), const Color(0xFFFFFFFF),
              1.2);
        }
      case ResourceKind.berries:
        p.oval(b.translate(0, 2), 15, 7, const Color(0x33000000));
        const g = Color(0xFF3C8A3A);
        final c = b.translate(0, -8);
        final pts = [
          c.translate(-13, 4),
          c.translate(-10, -6),
          c.translate(0, -11),
          c.translate(10, -7),
          c.translate(13, 4),
          c.translate(0, 9),
        ];
        final mid = c.translate(-2, -2);
        final sh = [1.0, 1.2, 1.1, 0.85, 0.7, 0.9];
        for (int i = 0; i < 6; i++) {
          p.fill([mid, pts[i], pts[(i + 1) % 6]], shadeColor(g, sh[i]));
        }
        final count =
            (r.amount / resourceKindAmount[ResourceKind.berries]! * 7).ceil();
        final rnd = Random(r.id);
        for (int i = 0; i < count; i++) {
          final o =
              c.translate(rnd.nextDouble() * 18 - 9, rnd.nextDouble() * 12 - 7);
          p.fill([
            o.translate(0, -2.5),
            o.translate(2.5, 0),
            o.translate(0, 2.5),
            o.translate(-2.5, 0)
          ], const Color(0xFFD7344F));
        }
    }
  }

  // --- Units -------------------------------------------------------------------

  void _drawUnit(Unit u) {
    final b = iso(u.x, u.y);
    final team = _teamColor(u.owner);
    final body = u.hitFlash > 0 ? const Color(0xFFFFFFFF) : team;
    final f = u.facing;
    final cav = u.def.cls == UnitClass.cavalry;
    p.oval(b, cav ? 13 : 8, cav ? 6 : 4, const Color(0x40000000));
    final walk = u.moving ? sin(u.animTime * 12) : 0.0;
    final x = u.x, y = u.y;
    double riderZ = 0;

    if (cav) {
      final horse = u.type == UnitType.knight
          ? const Color(0xFF5A4030)
          : const Color(0xFF9A6A40);
      // Legs
      for (final o in [-6.0, -2.0, 3.0, 7.0]) {
        final lx = b.dx + o * f;
        final sw = (o > 0 ? walk : -walk) * 2;
        p.line(Offset(lx, b.dy - 7), Offset(lx + sw, b.dy),
            shadeColor(horse, 0.7), 2);
      }
      // Body (elongated along screen x).
      final bx0 = b.dx - 9, bx1 = b.dx + 9;
      p.fill([
        Offset(bx0, b.dy - 7),
        Offset(bx1, b.dy - 7),
        Offset(bx1, b.dy - 14),
        Offset(bx0, b.dy - 14),
      ], shadeColor(horse, 0.85));
      p.fill([
        Offset(bx0, b.dy - 14),
        Offset(bx1, b.dy - 14),
        Offset(bx1 - 2, b.dy - 17),
        Offset(bx0 + 2, b.dy - 17),
      ], shadeColor(horse, 1.15));
      // Head & neck
      final hx = b.dx + 10 * f;
      p.fill([
        Offset(hx - 3 * f, b.dy - 13),
        Offset(hx + 2 * f, b.dy - 22),
        Offset(hx + 7 * f, b.dy - 19),
        Offset(hx + 2 * f, b.dy - 11),
      ], horse);
      // Tail
      p.line(Offset(b.dx - 9 * f, b.dy - 14), Offset(b.dx - 13 * f, b.dy - 8),
          shadeColor(horse, 0.6), 2);
      // Caparison in team colour for knights
      if (u.type == UnitType.knight) {
        p.fill([
          Offset(bx0 + 2, b.dy - 14),
          Offset(bx1 - 2, b.dy - 14),
          Offset(bx1 - 3, b.dy - 8),
          Offset(bx0 + 3, b.dy - 8),
        ], shadeColor(body, 0.9));
      }
      riderZ = 12;
    } else {
      // Legs
      p.line(Offset(b.dx - 2, b.dy - 6), Offset(b.dx - 2 + walk * 2, b.dy),
          const Color(0xFF4A3A2A), 2.2);
      p.line(Offset(b.dx + 2, b.dy - 6), Offset(b.dx + 2 - walk * 2, b.dy),
          const Color(0xFF4A3A2A), 2.2);
    }

    // Torso (low-poly prism).
    final tz0 = 5 + riderZ, tz1 = 15 + riderZ;
    const a = 0.085;
    final torso =
        u.isVillager ? Color.lerp(body, const Color(0xFFC8A070), 0.45)! : body;
    p.box(x - a, y - a, x + a, y + a, tz0, tz1, torso);
    // Belt in team colour for villagers.
    if (u.isVillager) {
      p.box(x - a - 0.005, y - a - 0.005, x + a + 0.005, y + a + 0.005, tz0 + 2,
          tz0 + 4, body);
    }
    // Head
    const hA = 0.06;
    p.box(x - hA, y - hA, x + hA, y + hA, tz1 + 1, tz1 + 7, _skin);
    // Helmet / hat
    final hat = switch (u.type) {
      UnitType.villager => const Color(0xFFC9A55C),
      UnitType.knight => const Color(0xFFCFD3D8),
      UnitType.militia || UnitType.spearman => const Color(0xFF9EA4AA),
      _ => shadeColor(body, 0.75),
    };
    final hc = iso(x, y, tz1 + 7);
    if (u.isVillager) {
      p.fill(
          [hc.translate(-7, 2), hc.translate(7, 2), hc.translate(0, -4)], hat);
    } else {
      p.fill(
          [hc.translate(-5, 1), hc.translate(5, 1), hc.translate(0, -5)], hat);
    }

    // Weapons / tools.
    final hand = iso(x, y, tz0 + 6).translate(6 * f, 0);
    final attacking =
        u.task == Task.attack && u.attackCooldown > u.def.reload - 0.35;
    final working =
        (u.task == Task.gather || u.task == Task.build) && !u.moving;
    final swing = attacking
        ? sin((u.def.reload - u.attackCooldown) / 0.35 * pi) * 1.2
        : (working ? sin(u.animTime * 8) * 0.9 : 0.0);
    switch (u.type) {
      case UnitType.villager:
        final ang = -1.0 - swing;
        final tip = hand + Offset(cos(ang) * 9 * f, sin(ang) * 9);
        p.line(hand, tip, const Color(0xFF7A5230), 1.6);
        if (u.task == Task.build) {
          p.fill([
            tip.translate(-2, -2),
            tip.translate(2, -2),
            tip.translate(2, 2),
            tip.translate(-2, 2)
          ], const Color(0xFF888888));
        } else {
          p.fill([tip, tip.translate(3 * f, 2), tip.translate(-1 * f, 3)],
              const Color(0xFFB0B4B8));
        }
        if (u.carry > 0.5 && u.carryType != null) {
          final cc = switch (u.carryType!) {
            Res.food => const Color(0xFFD84A4A),
            Res.wood => const Color(0xFF9A6A3A),
            Res.gold => const Color(0xFFF2C440),
            Res.stone => const Color(0xFFA0A4A8),
          };
          final bx = x - 0.1 * f, by = y + 0.1 * f;
          p.box(
              bx - 0.06, by - 0.06, bx + 0.06, by + 0.06, tz0 + 3, tz0 + 9, cc);
        }
      case UnitType.militia:
        final ang = -0.6 - swing;
        p.line(hand, hand + Offset(cos(ang) * 11 * f, sin(ang) * 11),
            const Color(0xFFDDE2E6), 2);
        // Shield
        final sh = iso(x, y, tz0 + 6).translate(-5 * f, 0);
        p.fill([
          sh.translate(0, -5),
          sh.translate(3 * f, -2),
          sh.translate(0, 5),
          sh.translate(-3 * f, -2)
        ], shadeColor(body, 0.8));
      case UnitType.spearman:
        final ang = -1.3 + swing * 0.8;
        final tip = hand + Offset(cos(ang) * 18 * f, sin(ang) * 18);
        p.line(hand - Offset(cos(ang) * 6 * f, sin(ang) * 6), tip, _wood, 1.6);
        p.fill([tip, tip.translate(2, 3), tip.translate(-2, 3)],
            const Color(0xFFDDE2E6));
      case UnitType.archer:
      case UnitType.skirmisher:
        final bc = u.type == UnitType.archer
            ? const Color(0xFF6A4020)
            : const Color(0xFF8A6A40);
        final top = hand.translate(0, -8), bot = hand.translate(0, 6);
        final mid = hand.translate(5 * f, -1);
        p.line(top, mid, bc, 1.8);
        p.line(mid, bot, bc, 1.8);
        p.line(top, bot, const Color(0xCCFFFFFF), 0.7);
        if (u.type == UnitType.skirmisher) {
          final sh = iso(x, y, tz0 + 5).translate(-5 * f, 0);
          p.fill([
            sh.translate(-3, -4),
            sh.translate(3, -4),
            sh.translate(3, 4),
            sh.translate(-3, 4)
          ], shadeColor(body, 0.7));
        }
      case UnitType.scout:
        final ang = -0.4 - swing;
        p.line(hand, hand + Offset(cos(ang) * 10 * f, sin(ang) * 10),
            const Color(0xFFDDE2E6), 1.8);
      case UnitType.knight:
        final ang = -0.3 - swing * 0.5;
        p.line(hand, hand + Offset(cos(ang) * 20 * f, sin(ang) * 20),
            const Color(0xFFC8B88A), 2.2);
        p.fill([
          iso(x, y, tz1 + 12),
          iso(x, y, tz1 + 6).translate(2, 0),
          iso(x, y, tz1 + 6).translate(-2, 0)
        ], body);
    }
  }

  // --- Buildings -----------------------------------------------------------------

  double _buildingHeight(BuildingType t) => switch (t) {
        BuildingType.townCenter => 62,
        BuildingType.house => 30,
        BuildingType.mill => 38,
        BuildingType.lumberCamp || BuildingType.miningCamp => 24,
        BuildingType.farm => 4,
        BuildingType.barracks => 34,
        BuildingType.archeryRange => 30,
        BuildingType.stable => 32,
        BuildingType.blacksmith => 38,
        BuildingType.market => 30,
        BuildingType.tower => 72,
        BuildingType.castle => 70,
      };

  void _drawBuilding(Building b) {
    if (b.complete || b.type == BuildingType.farm) {
      _drawBuildingShape(b, 1);
    } else {
      _drawConstruction(b);
    }
  }

  void _drawConstruction(Building b) {
    final x0 = b.minX, y0 = b.minY, x1 = b.maxX, y1 = b.maxY;
    p.fill(_tileDiamond(x0, y0, b.size.toDouble(), b.size.toDouble()),
        const Color(0xFFA2835A));
    final h = _buildingHeight(b.type) * 0.55;
    final z = max(2.0, h * b.progress);
    const m = 0.25;
    p.box(x0 + m, y0 + m, x1 - m, y1 - m, 0, z, _wallWood, alpha: 0.85);
    // Scaffold poles.
    for (final c in [
      Offset(x0 + 0.1, y0 + 0.1),
      Offset(x1 - 0.1, y0 + 0.1),
      Offset(x1 - 0.1, y1 - 0.1),
      Offset(x0 + 0.1, y1 - 0.1)
    ]) {
      p.line(
          iso(c.dx, c.dy), iso(c.dx, c.dy, h + 6), const Color(0xFF6B4A2A), 2);
    }
    p.line(iso(x0 + 0.1, y1 - 0.1, h * 0.6), iso(x1 - 0.1, y1 - 0.1, h * 0.6),
        const Color(0xFF6B4A2A), 1.5);
    p.line(iso(x1 - 0.1, y0 + 0.1, h * 0.6), iso(x1 - 0.1, y1 - 0.1, h * 0.6),
        const Color(0xFF6B4A2A), 1.5);
    // Team flag
    _flag(iso(x1 - 0.1, y1 - 0.1, h + 6), b.owner);
  }

  void _flag(Offset top, int owner) {
    p.line(top, top.translate(0, 12), const Color(0xFF5A4030), 1.5);
    final wave = sin(game.timeSeconds * 4 + top.dx) * 1.5;
    p.fill([top, top.translate(9, 2 + wave), top.translate(0, 5)],
        _teamColor(owner));
  }

  void _drawBuildingShape(Building b, double alpha) {
    final x0 = b.minX, y0 = b.minY, x1 = b.maxX, y1 = b.maxY;
    final cx = b.cx, cy = b.cy;
    final team = _teamColor(b.owner);
    final roof = shadeColor(team, 0.85);
    if (alpha < 1) {
      p.canvas.saveLayer(
          null, Paint()..color = Color.fromRGBO(255, 255, 255, alpha));
    }
    switch (b.type) {
      case BuildingType.townCenter:
        p.box(x0 + 0.1, y0 + 0.1, x1 - 0.1, y1 - 0.1, 0, 6, _darkStone);
        p.box(x0 + 0.35, y0 + 0.35, x1 - 0.35, y1 - 0.35, 6, 26, _wallBeige);
        // Door
        p.fill([
          iso(cx - 0.3, y1 - 0.35, 6),
          iso(cx + 0.3, y1 - 0.35, 6),
          iso(cx + 0.3, y1 - 0.35, 18),
          iso(cx - 0.3, y1 - 0.35, 18)
        ], const Color(0xFF5A3A22));
        p.box(x0 + 0.9, y0 + 0.9, x1 - 0.9, y1 - 0.9, 26, 40, _stoneWall);
        p.pyramid(x0 + 0.7, y0 + 0.7, x1 - 0.7, y1 - 0.7, 40, 62, roof);
        _flag(iso(cx, cy, 62), b.owner);
      case BuildingType.house:
        p.box(x0 + 0.25, y0 + 0.25, x1 - 0.25, y1 - 0.25, 0, 15, _wallBeige);
        p.fill([
          iso(x1 - 0.25, cy - 0.15, 0),
          iso(x1 - 0.25, cy + 0.25, 0),
          iso(x1 - 0.25, cy + 0.25, 9),
          iso(x1 - 0.25, cy - 0.15, 9)
        ], const Color(0xFF5A3A22));
        p.gable(x0 + 0.12, y0 + 0.12, x1 - 0.12, y1 - 0.12, 15, 30, roof,
            wall: _wallBeige);
      case BuildingType.mill:
        p.box(x0 + 0.35, y0 + 0.35, x1 - 0.35, y1 - 0.35, 0, 20, _wallBeige);
        p.pyramid(x0 + 0.25, y0 + 0.25, x1 - 0.25, y1 - 0.25, 20, 36, roof);
        final hub = iso(x1 - 0.3, cy, 24);
        final ang = b.complete ? b.animTime * 1.5 : 0.4;
        for (int i = 0; i < 4; i++) {
          final a = ang + i * pi / 2;
          final d = Offset(cos(a) * 18, sin(a) * 18);
          final n = Offset(-sin(a) * 4, cos(a) * 4);
          p.fill([hub, hub + d, hub + d + n, hub + n * 0.3],
              i.isEven ? const Color(0xFFF2EAD8) : const Color(0xFFD9CCB0));
        }
        p.oval(hub, 2.5, 2.5, _wood);
      case BuildingType.lumberCamp:
      case BuildingType.miningCamp:
        final lumber = b.type == BuildingType.lumberCamp;
        p.fill(_tileDiamond(x0 + 0.1, y0 + 0.1, 1.8, 1.8),
            const Color(0xFF9E8358));
        for (final c in [
          Offset(x0 + 0.3, y0 + 0.3),
          Offset(x1 - 0.3, y0 + 0.3),
          Offset(x1 - 0.3, y1 - 0.3),
          Offset(x0 + 0.3, y1 - 0.3)
        ]) {
          p.box(
              c.dx - 0.05, c.dy - 0.05, c.dx + 0.05, c.dy + 0.05, 0, 18, _wood);
        }
        // Back wall
        p.box(x0 + 0.3, y0 + 0.25, x1 - 0.3, y0 + 0.35, 0, 18, _wallWood);
        // Slanted roof
        p.fill([
          iso(x0 + 0.15, y0 + 0.15, 22),
          iso(x1 - 0.15, y0 + 0.15, 22),
          iso(x1 - 0.15, y1 - 0.15, 15),
          iso(x0 + 0.15, y1 - 0.15, 15)
        ], roof);
        p.fill([
          iso(x1 - 0.15, y0 + 0.15, 22),
          iso(x1 - 0.15, y1 - 0.15, 15),
          iso(x1 - 0.15, y1 - 0.15, 12),
          iso(x1 - 0.15, y0 + 0.15, 19)
        ], shadeColor(roof, 0.65));
        if (lumber) {
          for (int i = 0; i < 3; i++) {
            final lx = x0 + 0.5 + i * 0.25;
            p.box(lx, y1 - 0.4, lx + 0.18, y1 + 0.05, 0, 5,
                const Color(0xFFA06A3A));
          }
          p.box(x0 + 0.62, y1 - 0.35, x0 + 0.8, y1, 5, 10,
              const Color(0xFFB07A48));
        } else {
          p.box(x1 - 0.75, y1 - 0.45, x1 - 0.25, y1 - 0.05, 2, 9,
              const Color(0xFF7A5A3A));
          p.rock(iso(x1 - 0.5, y1 - 0.25, 10), 4, 5, const Color(0xFFE8B83A));
          p.rock(iso(x0 + 0.5, y1 - 0.3), 5, 6, const Color(0xFFA3A8AE));
        }
      case BuildingType.farm:
        final full = b.owner >= 0 ? w.players[b.owner].farmFood : farmBaseFood;
        final k = b.complete ? (b.food / full).clamp(0.0, 1.0) : 0.0;
        p.fill(_tileDiamond(x0 + 0.05, y0 + 0.05, 1.9, 1.9),
            const Color(0xFF8A6238));
        final crop =
            Color.lerp(const Color(0xFF9A7A40), const Color(0xFFE2C452), k)!;
        final rows = b.complete ? 6 : (6 * b.progress).floor();
        for (int i = 0; i < rows; i++) {
          final yy = y0 + 0.2 + i * 0.3;
          p.fill([
            iso(x0 + 0.15, yy, 0),
            iso(x1 - 0.15, yy, 0),
            iso(x1 - 0.15, yy + 0.15, 2 + 3 * k),
            iso(x0 + 0.15, yy + 0.15, 2 + 3 * k)
          ], crop);
        }
        // Fence corners in team colour
        p.box(x0, y0, x0 + 0.08, y0 + 0.08, 0, 6, team);
        p.box(x1 - 0.08, y1 - 0.08, x1, y1, 0, 6, team);
      case BuildingType.barracks:
        p.box(x0 + 0.25, y0 + 0.25, x1 - 0.25, y1 - 0.25, 0, 24, _stoneWall);
        // Crenellations
        for (int i = 0; i < 5; i++) {
          final t = x0 + 0.3 + i * (b.size - 0.6) / 4.5;
          p.box(t, y1 - 0.4, t + 0.2, y1 - 0.25, 24, 29, _stoneWall);
          final t2 = y0 + 0.3 + i * (b.size - 0.6) / 4.5;
          p.box(x1 - 0.4, t2, x1 - 0.25, t2 + 0.2, 24, 29, _stoneWall);
        }
        p.fill([
          iso(cx - 0.35, y1 - 0.25, 0),
          iso(cx + 0.35, y1 - 0.25, 0),
          iso(cx + 0.35, y1 - 0.25, 14),
          iso(cx - 0.35, y1 - 0.25, 14)
        ], const Color(0xFF3A2A1E));
        p.gable(x0 + 0.6, y0 + 0.6, x1 - 0.8, y1 - 0.8, 24, 34, roof,
            wall: _stoneWall);
        _flag(iso(x1 - 0.35, y1 - 0.35, 30), b.owner);
      case BuildingType.archeryRange:
        p.box(x0 + 0.2, y0 + 0.2, x1 - 1.2, y1 - 0.2, 0, 15, _wallWood);
        p.gable(x0 + 0.1, y0 + 0.1, x1 - 1.1, y1 - 0.1, 15, 28, roof,
            wall: _wallWood);
        for (int i = 0; i < 2; i++) {
          final t = iso(x1 - 0.5, y0 + 0.8 + i * 1.3, 8);
          p.line(t.translate(0, 8), t, _wood, 1.5);
          p.oval(t, 6, 6, const Color(0xFFF4F0E8));
          p.oval(t, 4, 4, const Color(0xFFD03838));
          p.oval(t, 1.8, 1.8, const Color(0xFFF4F0E8));
        }
      case BuildingType.stable:
        p.box(x0 + 0.2, y0 + 0.5, x1 - 0.2, y1 - 0.5, 0, 17, _wallWood);
        p.gable(x0 + 0.1, y0 + 0.35, x1 - 0.1, y1 - 0.35, 17, 32, roof,
            wall: _wallWood);
        for (int i = 0; i < 3; i++) {
          final t = x0 + 0.5 + i * 0.75;
          p.fill([
            iso(t, y1 - 0.5, 0),
            iso(t + 0.4, y1 - 0.5, 0),
            iso(t + 0.4, y1 - 0.5, 10),
            iso(t, y1 - 0.5, 10)
          ], const Color(0xFF4A3020));
        }
        p.box(x1 - 0.6, y1 - 0.4, x1 - 0.15, y1 - 0.05, 0, 6,
            const Color(0xFFE0C060));
      case BuildingType.blacksmith:
        p.box(x0 + 0.25, y0 + 0.25, x1 - 0.25, y1 - 0.25, 0, 17, _darkStone);
        p.pyramid(x0 + 0.15, y0 + 0.15, x1 - 0.15, y1 - 0.15, 17, 32, roof);
        p.box(x0 + 0.4, y0 + 0.4, x0 + 0.7, y0 + 0.7, 17, 38,
            const Color(0xFF5A5450));
        final s = iso(x0 + 0.55, y0 + 0.55, 40 + (game.timeSeconds * 10 % 10));
        p.oval(s, 4, 3, const Color(0x55DDDDDD));
        p.box(x1 - 0.45, y1 - 0.1, x1 - 0.2, y1 + 0.05, 0, 5,
            const Color(0xFF3A3A3E));
      case BuildingType.market:
        p.box(x0 + 0.3, y0 + 0.3, x1 - 0.3, y1 - 0.3, 0, 16, _wallBeige);
        p.pyramid(x0 + 0.2, y0 + 0.2, x1 - 0.2, y1 - 0.2, 16, 30, roof);
        for (int i = 0; i < 4; i++) {
          final t = x0 + 0.3 + i * 0.6;
          p.fill([
            iso(t, y1 - 0.3, 14),
            iso(t + 0.6, y1 - 0.3, 14),
            iso(t + 0.6, y1 + 0.1, 9),
            iso(t, y1 + 0.1, 9)
          ], i.isEven ? const Color(0xFFF4F0E8) : team);
        }
        p.box(x1 - 0.2, y1 - 1.0, x1 + 0.05, y1 - 0.7, 0, 6,
            const Color(0xFFA07040));
      case BuildingType.tower:
        p.box(x0 + 0.18, y0 + 0.18, x1 - 0.18, y1 - 0.18, 0, 50, _stoneWall);
        p.box(x0 + 0.05, y0 + 0.05, x1 - 0.05, y1 - 0.05, 50, 56, _darkStone);
        p.pyramid(x0 + 0.02, y0 + 0.02, x1 - 0.02, y1 - 0.02, 56, 74, roof);
        _flag(iso(cx, cy, 74), b.owner);
      case BuildingType.castle:
        p.box(x0 + 0.3, y0 + 0.3, x1 - 0.3, y1 - 0.3, 0, 28, _stoneWall);
        p.box(x0 + 1.1, y0 + 1.1, x1 - 1.1, y1 - 1.1, 28, 46, _stoneWall);
        p.pyramid(x0 + 1.0, y0 + 1.0, x1 - 1.0, y1 - 1.0, 46, 70, roof);
        for (final c in [
          Offset(x0, y0),
          Offset(x1 - 1, y0),
          Offset(x0, y1 - 1),
          Offset(x1 - 1, y1 - 1)
        ]) {
          p.box(c.dx + 0.1, c.dy + 0.1, c.dx + 0.9, c.dy + 0.9, 0, 40,
              _darkStone);
          p.pyramid(
              c.dx + 0.05, c.dy + 0.05, c.dx + 0.95, c.dy + 0.95, 40, 54, roof);
        }
        p.fill([
          iso(cx - 0.4, y1 - 0.3, 0),
          iso(cx + 0.4, y1 - 0.3, 0),
          iso(cx + 0.4, y1 - 0.3, 16),
          iso(cx - 0.4, y1 - 0.3, 16)
        ], const Color(0xFF3A2A1E));
        _flag(iso(cx, cy, 70), b.owner);
    }
    if (alpha < 1) p.canvas.restore();
  }

  // ---------------------------------------------------------------------------
  // Projectiles, effects, overlays
  // ---------------------------------------------------------------------------

  void _drawProjectiles() {
    for (final pr in w.projectiles) {
      final vi =
          w.map.idx(pr.x.floor().clamp(0, 63), pr.y.floor().clamp(0, 63));
      if (w.visible[vi] == 0) continue;
      final a = iso(pr.x, pr.y, pr.z);
      final dx = (pr.target.cx - pr.sx), dy = (pr.target.cy - pr.sy);
      final dir = iso(dx, dy);
      final l = dir.distance;
      if (l < 0.01) continue;
      final n = dir / l;
      p.line(a - n * 7, a + n * 2, const Color(0xFF3A2A1A), 1.4);
      p.line(a + n * 1, a + n * 3, const Color(0xFFDDDDDD), 1.8);
    }
  }

  void _drawEffects() {
    for (final e in w.effects) {
      final k = e.t / e.duration;
      final b = iso(e.x, e.y);
      switch (e.kind) {
        case EffectKind.flag:
          final s = 1 - k;
          p.ovalStroke(
              b,
              12 * s * e.size + 4,
              6 * s * e.size + 2,
              e.size > 1 ? const Color(0xFFFF5050) : const Color(0xFF6CFF7A),
              2);
        case EffectKind.dust:
          final rnd = Random(e.hashCode);
          for (int i = 0; i < 8 + e.size * 3; i++) {
            final ang = rnd.nextDouble() * pi * 2;
            final dist = (10 + rnd.nextDouble() * 18 * e.size) * k;
            final c =
                b + Offset(cos(ang) * dist, sin(ang) * dist * 0.5 - k * 20);
            final r = (4 + rnd.nextDouble() * 6) * (1 - k * 0.5);
            p.fill([
              c.translate(0, -r),
              c.translate(r, 0),
              c.translate(0, r),
              c.translate(-r, 0)
            ], Color.fromRGBO(140, 120, 95, (1 - k) * 0.8));
          }
        case EffectKind.blood:
          p.fill([
            b.translate(-6, 0),
            b.translate(0, -3),
            b.translate(7, 0),
            b.translate(0, 3)
          ], Color.fromRGBO(120, 20, 20, (1 - k) * 0.7));
          // Fallen body
          p.fill([
            b.translate(-5, -2),
            b.translate(5, -2),
            b.translate(6, 1),
            b.translate(-4, 1)
          ], Color.fromRGBO(90, 70, 50, (1 - k) * 0.8));
        case EffectKind.sparkle:
          final c = b.translate(0, -10 - k * 10);
          p.line(c.translate(-4, 0), c.translate(4, 0),
              Color.fromRGBO(255, 255, 255, 1 - k), 1.5);
          p.line(c.translate(0, -4), c.translate(0, 4),
              Color.fromRGBO(255, 255, 255, 1 - k), 1.5);
      }
    }
  }

  void _drawOverlays(Rect view) {
    // Rally point of the selected building.
    if (game.selection.length == 1) {
      final s = game.selection.first;
      if (s is Building && s.owner == GameWorld.human && s.rallyX != null) {
        final r = iso(s.rallyX!, s.rallyY!);
        p.line(iso(s.cx, s.cy), r, const Color(0x66FFFFFF), 1);
        _flag(r.translate(0, -12), GameWorld.human);
      }
    }
    // Alert pings.
    for (final m in w.messages) {
      if (!m.alert || m.x == null) continue;
      final age = w.time - m.time;
      if (age > 3) continue;
      final c = iso(m.x!, m.y!);
      final r = (age % 1) * 40;
      p.ovalStroke(c, r + 6, (r + 6) / 2,
          Color.fromRGBO(255, 60, 60, 1 - (age % 1)), 2.5);
    }
  }
}
