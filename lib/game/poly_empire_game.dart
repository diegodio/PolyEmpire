import 'dart:math';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';

import 'config.dart';
import 'entities.dart';
import 'iso.dart';
import 'renderer.dart';
import 'world.dart';

/// Flame game: owns the simulation, camera and player interaction state.
class PolyEmpireGame extends FlameGame {
  GameWorld? sim;

  late final WorldRenderer renderer = WorldRenderer(this);

  // Camera (world pixels at screen centre).
  double camX = 0, camY = 0, zoom = 1.0;
  static const minZoom = 0.45, maxZoom = 2.2;

  // Interaction
  final List<Entity> selection = [];
  BuildingType? placing;
  Point<int>? hoverTile;
  Rect? dragRect;
  bool boxSelectMode = false;

  // Time / speed
  double speed = 1.0;
  bool simPaused = false;
  double timeSeconds = 0;
  final ValueNotifier<int> hudTick = ValueNotifier(0);
  double _hudTimer = 0;
  final Set<String> heldKeys = {};

  bool get started => sim != null;

  @override
  Color backgroundColor() => const Color(0xFF1C222C);

  @override
  Future<void> onLoad() async {
    add(_WorldView(this));
  }

  /// [reveal] and [skipSeconds] are debug options (URL: ?reveal=1&skip=600).
  void startGame(Difficulty difficulty, int seed,
      {bool reveal = false, double skipSeconds = 0}) {
    sim = GameWorld(seed: seed, difficulty: difficulty);
    sim!.revealAll = reveal;
    for (double t = 0; t < skipSeconds; t += 1 / 30) {
      sim!.update(1 / 30);
    }
    selection.clear();
    placing = null;
    simPaused = false;
    speed = 1;
    zoom = 1.1;
    centerOn(sim!.humanBase.x + 0.5, sim!.humanBase.y + 0.5);
    hudTick.value++;
  }

  void quitToMenu() {
    sim = null;
    selection.clear();
    placing = null;
    hudTick.value++;
  }

  @override
  void update(double dt) {
    super.update(dt);
    timeSeconds += dt;
    final w = sim;
    if (w == null) return;
    // Keyboard panning.
    if (heldKeys.isNotEmpty) {
      final s = 700 * dt / zoom;
      if (heldKeys.contains('left')) camX -= s;
      if (heldKeys.contains('right')) camX += s;
      if (heldKeys.contains('up')) camY -= s;
      if (heldKeys.contains('down')) camY += s;
      _clampCamera();
    }
    if (!simPaused && w.winner == null) {
      double remaining = min(dt, 0.1) * speed;
      while (remaining > 0) {
        final step = min(remaining, 1 / 30);
        w.update(step);
        remaining -= step;
      }
      selection.removeWhere((e) => !e.alive);
    }
    _hudTimer -= dt;
    if (_hudTimer <= 0) {
      _hudTimer = 0.15;
      hudTick.value++;
    }
  }

  // ---------------------------------------------------------------------------
  // Camera
  // ---------------------------------------------------------------------------

  void centerOn(double tx, double ty) {
    final p = iso(tx, ty);
    camX = p.dx;
    camY = p.dy;
    _clampCamera();
  }

  void _clampCamera() {
    const n = GameWorld.mapSize;
    camX = camX.clamp(-n * hw, n * hw);
    camY = camY.clamp(0, n * hh * 2);
  }

  void pan(Offset screenDelta) {
    camX -= screenDelta.dx / zoom;
    camY -= screenDelta.dy / zoom;
    _clampCamera();
  }

  void zoomAt(double factor, Offset screen) {
    final before = screenToWorldPx(screen);
    zoom = (zoom * factor).clamp(minZoom, maxZoom);
    final after = screenToWorldPx(screen);
    camX += before.dx - after.dx;
    camY += before.dy - after.dy;
    _clampCamera();
  }

  Offset screenToWorldPx(Offset s) => Offset(
      (s.dx - size.x / 2) / zoom + camX, (s.dy - size.y / 2) / zoom + camY);

  Offset worldPxToScreen(Offset w) => Offset(
      (w.dx - camX) * zoom + size.x / 2, (w.dy - camY) * zoom + size.y / 2);

  Offset screenToTile(Offset s) {
    final wp = screenToWorldPx(s);
    return unIso(wp.dx, wp.dy);
  }

  /// Ground tile corners of the current view (for the minimap).
  List<Offset> viewCornersTiles() => [
        screenToTile(Offset.zero),
        screenToTile(Offset(size.x, 0)),
        screenToTile(Offset(size.x, size.y)),
        screenToTile(Offset(0, size.y)),
      ];

  // ---------------------------------------------------------------------------
  // Picking
  // ---------------------------------------------------------------------------

  Entity? pick(Offset screen) {
    final w = sim!;
    final wp = screenToWorldPx(screen);
    Entity? best;
    double bd = 16 / sqrt(zoom) + 4;
    for (final u in w.units) {
      if (!u.alive) continue;
      if (u.owner != GameWorld.human && !w.isVisibleTo(GameWorld.human, u)) {
        continue;
      }
      final c = iso(u.x, u.y, 12);
      final d = (c - wp).distance;
      if (d < bd) {
        bd = d;
        best = u;
      }
    }
    if (best != null) return best;

    // Buildings: test the footprint extruded upward.
    Building? bb;
    double bdepth = -1;
    for (final b in w.buildings) {
      if (!b.alive) continue;
      final h = b.type == BuildingType.farm ? 0.0 : (b.size * 14.0 + 12);
      for (double k = 0; k <= h; k += 6) {
        final t = unIso(wp.dx, wp.dy + k);
        if (t.dx >= b.minX &&
            t.dx < b.maxX &&
            t.dy >= b.minY &&
            t.dy < b.maxY) {
          if (b.depth() > bdepth) {
            bdepth = b.depth();
            bb = b;
          }
          break;
        }
      }
    }
    // Resources (trees are tall).
    ResourceNode? rr;
    for (double k = 0; k <= 30; k += 10) {
      final t = unIso(wp.dx, wp.dy + k);
      final e = w.map.entityAt(t.dx.floor(), t.dy.floor());
      if (e is ResourceNode && w.explored[w.map.idx(e.tx, e.ty)] == 1) {
        if (rr == null || e.depth() > rr.depth()) rr = e;
      }
    }
    if (bb != null && rr != null) {
      return rr.depth() > bb.depth() ? rr : bb;
    }
    if (bb != null) {
      if (bb.owner != GameWorld.human && !_explored(bb)) return null;
      return bb;
    }
    return rr;
  }

  bool _explored(Building b) {
    final w = sim!;
    for (int y = b.ty; y < b.ty + b.size; y++) {
      for (int x = b.tx; x < b.tx + b.size; x++) {
        if (w.explored[w.map.idx(x, y)] == 1) return true;
      }
    }
    return false;
  }

  List<Unit> get selectedUnits => selection
      .whereType<Unit>()
      .where((u) => u.owner == GameWorld.human && u.alive)
      .toList();

  bool get hasOwnUnits => selectedUnits.isNotEmpty;

  // ---------------------------------------------------------------------------
  // Input handlers (called from the Flutter layer)
  // ---------------------------------------------------------------------------

  void hover(Offset screen) {
    if (!started) return;
    final t = screenToTile(screen);
    hoverTile = Point(t.dx.floor(), t.dy.floor());
  }

  bool canPlaceAt(BuildingType type, int tx, int ty) {
    final w = sim!;
    if (!w.map.canPlace(type, tx, ty)) return false;
    final s = buildingDefs[type]!.size;
    for (int y = ty; y < ty + s; y++) {
      for (int x = tx; x < tx + s; x++) {
        if (w.explored[w.map.idx(x, y)] == 0) return false;
      }
    }
    return true;
  }

  void startPlacing(BuildingType t) {
    final w = sim!;
    final reason = w.buildReason(GameWorld.human, t);
    if (reason != null) {
      w.message(reason);
      return;
    }
    placing = t;
  }

  void _tryPlace(Offset screen, {bool keep = false}) {
    final w = sim!;
    final type = placing!;
    final t = screenToTile(screen);
    hoverTile = Point(t.dx.floor(), t.dy.floor());
    final s = buildingDefs[type]!.size;
    final tx = hoverTile!.x - (s - 1) ~/ 2, ty = hoverTile!.y - (s - 1) ~/ 2;
    if (!canPlaceAt(type, tx, ty)) {
      w.message('Não é possível construir aqui.');
      return;
    }
    final builders = selectedUnits.where((u) => u.isVillager).toList();
    final b = w.placeFoundation(GameWorld.human, type, tx, ty, builders);
    if (b == null) {
      w.message(w.buildReason(GameWorld.human, type) ??
          'Não é possível construir aqui.');
      placing = null;
      return;
    }
    if (!keep || w.buildReason(GameWorld.human, type) != null) placing = null;
  }

  /// Primary tap/click. [mouse] indicates a mouse (desktop) style input where
  /// commands are given with the right button.
  void tap(Offset screen, {required bool mouse, bool shift = false}) {
    final w = sim;
    if (w == null || w.winner != null) return;
    if (placing != null) {
      _tryPlace(screen, keep: shift);
      return;
    }
    final e = pick(screen);
    if (mouse) {
      _select(e, additive: shift);
      return;
    }
    // Touch: contextual.
    final units = selectedUnits;
    if (units.isNotEmpty) {
      if (e == null) {
        final t = screenToTile(screen);
        w.smartCommand(units, t.dx, t.dy, null);
        return;
      }
      final isMineUnit = e is Unit && e.owner == GameWorld.human;
      if (!isMineUnit) {
        final villagers = units.any((u) => u.isVillager);
        final b = e is Building ? e : null;
        final ownWork = b != null &&
            b.owner == GameWorld.human &&
            villagers &&
            (!b.complete || b.type == BuildingType.farm || b.hp < b.maxHp);
        final enemyTarget = e.owner != GameWorld.human && e.owner >= 0;
        final resTarget = e is ResourceNode && villagers;
        if (enemyTarget || resTarget || ownWork) {
          w.smartCommand(units, e.cx, e.cy, e);
          return;
        }
      }
    } else if (e == null && selection.length == 1) {
      final s = selection.first;
      if (s is Building &&
          s.owner == GameWorld.human &&
          s.def.trains.isNotEmpty) {
        final t = screenToTile(screen);
        s.rallyX = t.dx;
        s.rallyY = t.dy;
        w.effects.add(Effect(EffectKind.flag, t.dx, t.dy, duration: 0.6));
        return;
      }
    }
    _select(e);
  }

  /// Secondary (right) click: contextual command / rally point.
  void secondaryTap(Offset screen) {
    final w = sim;
    if (w == null || w.winner != null) return;
    if (placing != null) {
      placing = null;
      return;
    }
    final t = screenToTile(screen);
    final e = pick(screen);
    final units = selectedUnits;
    if (units.isNotEmpty) {
      w.smartCommand(units, e?.cx ?? t.dx, e?.cy ?? t.dy, e);
      return;
    }
    if (selection.length == 1) {
      final s = selection.first;
      if (s is Building && s.owner == GameWorld.human) {
        s.rallyX = e?.cx ?? t.dx;
        s.rallyY = e?.cy ?? t.dy;
        w.effects
            .add(Effect(EffectKind.flag, s.rallyX!, s.rallyY!, duration: 0.6));
      }
    }
  }

  void _select(Entity? e, {bool additive = false}) {
    if (!additive) selection.clear();
    if (e != null) {
      if (additive && selection.contains(e)) {
        selection.remove(e);
      } else if (!(additive && e.owner != GameWorld.human)) {
        selection.add(e);
      }
    }
    hudTick.value++;
  }

  void selectInRect(Rect r) {
    final w = sim!;
    final picked = <Unit>[];
    for (final u in w.units) {
      if (u.owner != GameWorld.human || !u.alive) continue;
      final s = worldPxToScreen(iso(u.x, u.y, 10));
      if (r.contains(s)) picked.add(u);
    }
    if (picked.isEmpty) return;
    // Prefer military if both present (AoE style keeps all).
    selection
      ..clear()
      ..addAll(picked);
    hudTick.value++;
  }

  void selectAllOfTypeOnScreen(UnitType t) {
    final w = sim!;
    selection.clear();
    for (final u in w.units) {
      if (u.owner != GameWorld.human || !u.alive || u.type != t) continue;
      final s = worldPxToScreen(iso(u.x, u.y));
      if (s.dx >= 0 && s.dy >= 0 && s.dx <= size.x && s.dy <= size.y) {
        selection.add(u);
      }
    }
    hudTick.value++;
  }

  int _idleIndex = 0;
  void selectNextIdleVillager() {
    final w = sim!;
    final idle = w.units
        .where((u) =>
            u.owner == GameWorld.human &&
            u.alive &&
            u.isVillager &&
            u.task == Task.idle)
        .toList();
    if (idle.isEmpty) {
      w.message('Nenhum aldeão ocioso.');
      return;
    }
    _idleIndex = (_idleIndex + 1) % idle.length;
    final u = idle[_idleIndex];
    selection
      ..clear()
      ..add(u);
    centerOn(u.x, u.y);
    hudTick.value++;
  }

  void selectArmy() {
    final w = sim!;
    selection
      ..clear()
      ..addAll(w.units
          .where((u) => u.owner == GameWorld.human && u.alive && u.isMilitary));
    if (selection.isEmpty) w.message('Você não tem unidades militares.');
    hudTick.value++;
  }

  void selectTownCenter() {
    final w = sim!;
    final tc = w.buildings.where((b) =>
        b.owner == GameWorld.human &&
        b.alive &&
        b.type == BuildingType.townCenter);
    if (tc.isEmpty) return;
    selection
      ..clear()
      ..add(tc.first);
    centerOn(tc.first.cx, tc.first.cy);
    hudTick.value++;
  }

  void deleteSelection() {
    final w = sim!;
    for (final e in selection) {
      if (e.owner != GameWorld.human) continue;
      w.applyDamage(e, e.hp + 1, null);
    }
    selection.clear();
    hudTick.value++;
  }

  int get idleVillagers =>
      sim?.units
          .where((u) =>
              u.owner == GameWorld.human &&
              u.alive &&
              u.isVillager &&
              u.task == Task.idle)
          .length ??
      0;
}

class _WorldView extends Component {
  final PolyEmpireGame game;
  _WorldView(this.game);

  @override
  void render(Canvas canvas) {
    game.renderer.render(canvas, Size(game.size.x, game.size.y));
  }
}
