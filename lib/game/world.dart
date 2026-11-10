import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

import 'ai.dart';
import 'config.dart';
import 'entities.dart';
import 'game_map.dart';
import 'player.dart';

class GameMessage {
  final String text;
  final double time;
  final bool alert;
  final double? x, y;
  GameMessage(this.text, this.time, {this.alert = false, this.x, this.y});
}

/// Full RTS simulation: map, players, entities, combat, economy and fog.
class GameWorld {
  static const mapSize = 64;
  static const human = 0;
  static const enemy = 1;

  final int seed;
  final Difficulty difficulty;
  late final Random rnd;
  late final GameMap map;
  late final List<PlayerState> players;
  final List<Unit> units = [];
  final List<Building> buildings = [];
  final List<ResourceNode> resources = [];
  final List<Projectile> projectiles = [];
  final List<Effect> effects = [];
  final List<GameMessage> messages = [];
  late final EnemyAI ai;

  late final Uint8List explored;
  late final Uint8List visible;
  double _fogTimer = 0;
  double _checkTimer = 0;
  double _alertCooldown = 0;
  double _houseWarnCooldown = 0;
  double time = 0;
  int? winner;
  bool revealAll = false;

  late final Point<int> humanBase;
  late final Point<int> enemyBase;

  GameWorld({required this.seed, required this.difficulty}) {
    rnd = Random(seed);
    map = GameMap(mapSize);
    explored = Uint8List(mapSize * mapSize);
    visible = Uint8List(mapSize * mapSize);
    players = [
      PlayerState(0, 'Você', const Color(0xFF2F7FE0)),
      PlayerState(1, 'Inimigo', const Color(0xFFD8393B)),
    ];
    final flip = rnd.nextBool();
    var hb = flip ? const Point(10, 10) : const Point(53, 53);
    var eb = flip ? const Point(53, 53) : const Point(10, 10);
    // Avoid the same diagonal every time.
    if (rnd.nextBool()) {
      hb = Point(hb.x, mapSize - 1 - hb.y);
      eb = Point(eb.x, mapSize - 1 - eb.y);
    }
    humanBase = hb;
    enemyBase = eb;

    resources.addAll(map.generate(rnd, [humanBase, enemyBase]));
    _setupPlayer(0, humanBase);
    _setupPlayer(1, enemyBase);

    final ep = players[1];
    ep.gatherMultiplier = switch (difficulty) {
      Difficulty.easy => 0.75,
      Difficulty.normal => 1.0,
      Difficulty.hard => 1.35,
    };
    ai = EnemyAI(this, 1);
    _recountPop();
    _updateFog();
  }

  void _setupPlayer(int p, Point<int> base) {
    // Clear area around the town center.
    for (int y = base.y - 2; y <= base.y + 2; y++) {
      for (int x = base.x - 2; x <= base.x + 2; x++) {
        final e = map.entityAt(x, y);
        if (e is ResourceNode) {
          map.removeResource(e);
          resources.remove(e);
        }
      }
    }
    addBuilding(BuildingType.townCenter, p, base.x - 1, base.y - 1,
        complete: true);
    final dirs = [
      const Point(2.6, 0.0),
      const Point(0.0, 2.6),
      const Point(-2.2, 2.4),
      const Point(2.4, -2.2),
    ];
    for (int i = 0; i < 3; i++) {
      spawnUnit(UnitType.villager, p, base.x + 0.5 + dirs[i].x,
          base.y + 0.5 + dirs[i].y);
    }
    spawnUnit(
        UnitType.scout, p, base.x + 0.5 + dirs[3].x, base.y + 0.5 + dirs[3].y);
  }

  // ---------------------------------------------------------------------------
  // Entity management
  // ---------------------------------------------------------------------------

  Unit spawnUnit(UnitType type, int owner, double x, double y) {
    final st = players[owner].stats(type);
    final u = Unit(type: type, owner: owner, x: x, y: y, hp: st.hp);
    units.add(u);
    return u;
  }

  Building addBuilding(BuildingType type, int owner, int tx, int ty,
      {bool complete = false}) {
    final b = Building(
        type: type, owner: owner, tx: tx, ty: ty, progress: complete ? 1 : 0);
    if (complete) b.hp = b.maxHp;
    if (type == BuildingType.farm) b.food = players[owner].farmFood;
    buildings.add(b);
    map.placeBuilding(b);
    // Push units out of the footprint.
    if (!b.def.walkable) {
      for (final u in units) {
        if (u.x >= b.minX && u.x < b.maxX && u.y >= b.minY && u.y < b.maxY) {
          final p = map.nearestWalkable(u.tileX, u.tileY);
          if (p != null) {
            u.x = p.x + 0.5;
            u.y = p.y + 0.5;
            u.path = [];
          }
        }
      }
    }
    return b;
  }

  void message(String text, {bool alert = false, double? x, double? y}) {
    messages.add(GameMessage(text, time, alert: alert, x: x, y: y));
    if (messages.length > 30) messages.removeAt(0);
  }

  Iterable<Building> buildingsOf(int owner) =>
      buildings.where((b) => b.owner == owner && b.alive);
  Iterable<Unit> unitsOf(int owner) =>
      units.where((u) => u.owner == owner && u.alive);

  bool hasCompleted(int owner, BuildingType t) => buildings
      .any((b) => b.owner == owner && b.type == t && b.complete && b.alive);

  // ---------------------------------------------------------------------------
  // Requirements
  // ---------------------------------------------------------------------------

  /// Returns null if possible, otherwise the reason why not.
  String? buildReason(int owner, BuildingType t) {
    final p = players[owner];
    final d = buildingDefs[t]!;
    if (p.age.index < d.minAge.index) return 'Requer ${ageNames[d.minAge]}';
    if (d.requires.isNotEmpty &&
        !d.requires.any((r) => hasCompleted(owner, r))) {
      return 'Requer ${buildingDefs[d.requires.first]!.name}';
    }
    if (!p.canAfford(d.cost)) return 'Falta ${p.missing(d.cost)}';
    return null;
  }

  String? trainReason(Building b, UnitType t) {
    final p = players[b.owner];
    final d = unitDefs[t]!;
    if (!b.complete) return 'Em construção';
    if (p.age.index < d.minAge.index) return 'Requer ${ageNames[d.minAge]}';
    if (b.queue.length >= 5) return 'Fila cheia';
    if (!p.canAfford(d.cost)) return 'Falta ${p.missing(d.cost)}';
    return null;
  }

  List<Tech> techsAt(Building b) {
    final p = players[b.owner];
    final out = <Tech>[];
    for (final e in techDefs.entries) {
      if (e.value.at != b.type) continue;
      if (p.has(e.key)) continue;
      if (ageTechs.containsKey(e.key)) {
        // Show only the next age.
        final next = Age.values[min(p.age.index + 1, Age.values.length - 1)];
        if (ageTechs[e.key] != next || p.age == Age.imperial) continue;
      }
      if (e.value.requires != null && !p.has(e.value.requires!)) continue;
      out.add(e.key);
    }
    return out;
  }

  String? researchReason(Building b, Tech t) {
    final p = players[b.owner];
    final d = techDefs[t]!;
    if (!b.complete) return 'Em construção';
    if (p.researching.contains(t)) return 'Pesquisando...';
    if (p.has(t)) return 'Já pesquisado';
    if (p.age.index < d.minAge.index) return 'Requer ${ageNames[d.minAge]}';
    if (ageTechs.containsKey(t) && p.researching.any(ageTechs.containsKey)) {
      return 'Pesquisando...';
    }
    final req = ageRequirementBuildings[t];
    if (req != null && req.isNotEmpty) {
      final n = req.where((r) => hasCompleted(b.owner, r)).length;
      if (n < 2)
        return 'Requer 2 prédios (${req.map((r) => buildingDefs[r]!.name).join(', ')})';
    }
    if (b.queue.length >= 5) return 'Fila cheia';
    if (!p.canAfford(d.cost)) return 'Falta ${p.missing(d.cost)}';
    return null;
  }

  // ---------------------------------------------------------------------------
  // Commands
  // ---------------------------------------------------------------------------

  bool train(Building b, UnitType t) {
    if (trainReason(b, t) != null) return false;
    players[b.owner].pay(unitDefs[t]!.cost);
    b.queue.add(QueueItem.unit(t));
    return true;
  }

  bool research(Building b, Tech t) {
    if (researchReason(b, t) != null) return false;
    final p = players[b.owner];
    p.pay(techDefs[t]!.cost);
    p.researching.add(t);
    b.queue.add(QueueItem.tech(t));
    return true;
  }

  void cancelQueue(Building b, int index) {
    if (index < 0 || index >= b.queue.length) return;
    final q = b.queue.removeAt(index);
    players[b.owner].refund(q.cost);
    if (q.tech != null) players[b.owner].researching.remove(q.tech);
  }

  Building? placeFoundation(
      int owner, BuildingType t, int tx, int ty, List<Unit> builders) {
    if (buildReason(owner, t) != null) return null;
    if (!map.canPlace(t, tx, ty)) return null;
    if (owner == human && !_exploredRect(tx, ty, buildingDefs[t]!.size)) {
      return null;
    }
    players[owner].pay(buildingDefs[t]!.cost);
    final b = addBuilding(t, owner, tx, ty);
    for (final u in builders) {
      if (u.isVillager) orderBuild(u, b);
    }
    return b;
  }

  bool _exploredRect(int tx, int ty, int s) {
    for (int y = ty; y < ty + s; y++) {
      for (int x = tx; x < tx + s; x++) {
        if (!map.inBounds(x, y) || explored[map.idx(x, y)] == 0) return false;
      }
    }
    return true;
  }

  void _resetOrder(Unit u) {
    u.path = [];
    u.pathIndex = 0;
    u.target = null;
    u.repathTimer = 0;
    u.stuckTimer = 0;
  }

  void orderMove(Unit u, double x, double y, {bool attackMove = false}) {
    _resetOrder(u);
    u.task = attackMove ? Task.attackMove : Task.move;
    u.targetX = x;
    u.targetY = y;
    final tx = x.floor().clamp(0, mapSize - 1),
        ty = y.floor().clamp(0, mapSize - 1);
    var dest = Point(tx, ty);
    if (!map.walkable(tx, ty)) {
      dest = map.nearestWalkable(tx, ty) ?? dest;
      u.targetX = dest.x + 0.5;
      u.targetY = dest.y + 0.5;
    }
    u.path = map.findPath(u.tileX, u.tileY, dest.x, dest.y, dest.x, dest.y);
  }

  void orderGroupMove(List<Unit> group, double x, double y,
      {bool attackMove = false}) {
    if (group.isEmpty) return;
    final slots = _formationSlots(x.floor(), y.floor(), group.length);
    final sorted = [...group]..sort((a, b) =>
        (pow(a.x - x, 2) + pow(a.y - y, 2))
            .compareTo(pow(b.x - x, 2) + pow(b.y - y, 2)));
    for (int i = 0; i < sorted.length; i++) {
      final s = slots[i % slots.length];
      orderMove(sorted[i], s.x + 0.5, s.y + 0.5, attackMove: attackMove);
    }
  }

  List<Point<int>> _formationSlots(int cx, int cy, int n) {
    final out = <Point<int>>[];
    for (int r = 0; r < 10 && out.length < n; r++) {
      for (int dy = -r; dy <= r && out.length < n; dy++) {
        for (int dx = -r; dx <= r && out.length < n; dx++) {
          if (max(dx.abs(), dy.abs()) != r) continue;
          if (map.walkable(cx + dx, cy + dy)) out.add(Point(cx + dx, cy + dy));
        }
      }
    }
    if (out.isEmpty) out.add(Point(cx, cy));
    return out;
  }

  void orderAttack(Unit u, Entity target) {
    if (target.owner == u.owner) return;
    _resetOrder(u);
    u.task = Task.attack;
    u.target = target;
  }

  void orderGather(Unit u, Entity res) {
    if (!u.isVillager) return;
    _resetOrder(u);
    u.task = Task.gather;
    u.target = res;
    u.lastResource = res;
    if (res is ResourceNode) {
      u.lastKind = res.kind;
      u.lastResX = res.cx;
      u.lastResY = res.cy;
    } else {
      u.lastKind = null;
    }
  }

  void orderBuild(Unit u, Building b) {
    if (!u.isVillager) return;
    _resetOrder(u);
    u.task = Task.build;
    u.target = b;
  }

  void orderReturn(Unit u) {
    final drop = nearestDrop(u.owner, u.carryType!, u.x, u.y);
    if (drop == null) {
      u.task = Task.idle;
      return;
    }
    u.path = [];
    u.pathIndex = 0;
    u.task = Task.returnRes;
    u.target = drop;
  }

  /// Context-sensitive command (right click / tap with a selection).
  void smartCommand(List<Unit> group, double x, double y, Entity? target) {
    final mine = group.where((u) => u.alive && u.owner == human).toList();
    if (mine.isEmpty) return;
    if (target != null && target.alive) {
      if (target.owner != human && target.owner != -1) {
        for (final u in mine) {
          orderAttack(u, target);
        }
        effects.add(Effect(EffectKind.flag, target.cx, target.cy,
            duration: 0.6, size: 2));
        return;
      }
      final vills = mine.where((u) => u.isVillager).toList();
      final others = mine.where((u) => !u.isVillager).toList();
      if (target is ResourceNode) {
        for (final v in vills) {
          orderGather(v, target);
        }
      } else if (target is Building && target.owner == human) {
        for (final v in vills) {
          if (!target.complete) {
            orderBuild(v, target);
          } else if (target.type == BuildingType.farm) {
            orderGather(v, target);
          } else if (v.carry > 0 && target.def.dropOff.contains(v.carryType)) {
            v.task = Task.returnRes;
            v.target = target;
            v.path = [];
          } else if (target.hp < target.maxHp) {
            orderBuild(v, target); // repair
          } else {
            orderMove(v, x, y);
          }
        }
      }
      if (others.isNotEmpty) orderGroupMove(others, x, y);
      if (vills.isNotEmpty) {
        effects.add(Effect(EffectKind.flag, x, y, duration: 0.6));
      }
      return;
    }
    orderGroupMove(mine, x, y);
    effects.add(Effect(EffectKind.flag, x, y, duration: 0.6));
  }

  // ---------------------------------------------------------------------------
  // Queries
  // ---------------------------------------------------------------------------

  Building? nearestDrop(int owner, Res r, double x, double y) {
    Building? best;
    double bd = double.infinity;
    for (final b in buildings) {
      if (b.owner != owner || !b.alive || !b.complete) continue;
      if (!b.def.dropOff.contains(r)) continue;
      final d = b.distanceFrom(x, y);
      if (d < bd) {
        bd = d;
        best = b;
      }
    }
    return best;
  }

  ResourceNode? nearestResource(ResourceKind k, double x, double y,
      {double maxDist = 1e9}) {
    ResourceNode? best;
    double bd = maxDist * maxDist;
    for (final r in resources) {
      if (r.kind != k || !r.alive) continue;
      final dx = r.cx - x, dy = r.cy - y;
      final d = dx * dx + dy * dy;
      if (d < bd) {
        bd = d;
        best = r;
      }
    }
    return best;
  }

  bool isVisibleTo(int owner, Entity e) {
    if (owner != human) return true;
    final x = e.cx.floor().clamp(0, mapSize - 1);
    final y = e.cy.floor().clamp(0, mapSize - 1);
    return visible[map.idx(x, y)] == 1;
  }

  Entity? findEnemyNear(Unit u, double radius, {bool includeBuildings = true}) {
    Entity? best;
    double bd = radius;
    bool bestIsVillager = true;
    for (final o in units) {
      if (!o.alive || o.owner == u.owner) continue;
      final d = o.distanceFrom(u.x, u.y);
      if (d > radius) continue;
      // Prefer military targets over villagers when close.
      final isV = o.isVillager;
      if (d < bd || (bestIsVillager && !isV && d < bd + 2)) {
        bd = d;
        best = o;
        bestIsVillager = isV;
      }
    }
    if (best != null || !includeBuildings) return best;
    for (final b in buildings) {
      if (!b.alive || b.owner == u.owner || b.owner < 0) continue;
      final d = b.distanceFrom(u.x, u.y);
      if (d < bd) {
        bd = d;
        best = b;
      }
    }
    return best;
  }

  // ---------------------------------------------------------------------------
  // Simulation
  // ---------------------------------------------------------------------------

  void update(double dt) {
    if (winner != null) return;
    time += dt;
    _alertCooldown -= dt;
    _houseWarnCooldown -= dt;

    _recountPop();
    for (final u in units) {
      if (u.alive) _updateUnit(u, dt);
    }
    _separate(dt);
    for (final b in buildings) {
      if (b.alive) _updateBuilding(b, dt);
    }
    _updateProjectiles(dt);
    for (final e in effects) {
      e.t += dt;
    }
    effects.removeWhere((e) => e.t >= e.duration);

    units.removeWhere((u) => !u.alive);
    buildings.removeWhere((b) => !b.alive);
    resources.removeWhere((r) => !r.alive);

    ai.update(dt);

    _fogTimer -= dt;
    if (_fogTimer <= 0) {
      _fogTimer = 0.2;
      _updateFog();
    }
    _checkTimer -= dt;
    if (_checkTimer <= 0) {
      _checkTimer = 1;
      _checkVictory();
    }
  }

  void _recountPop() {
    for (final p in players) {
      p.pop = 0;
      p.popCap = 0;
    }
    for (final u in units) {
      if (u.alive) players[u.owner].pop++;
    }
    for (final b in buildings) {
      if (b.alive && b.complete && b.owner >= 0) {
        players[b.owner].popCap += b.def.pop;
      }
    }
    for (final p in players) {
      p.popCap = min(200, p.popCap);
    }
  }

  void _checkVictory() {
    for (int p = 0; p < 2; p++) {
      final hasUnits = units.any((u) => u.owner == p && u.alive);
      final hasBuildings = buildings
          .any((b) => b.owner == p && b.alive && b.type != BuildingType.farm);
      if (!hasUnits && !hasBuildings) {
        winner = 1 - p;
        return;
      }
    }
  }

  void _updateFog() {
    if (revealAll) {
      visible.fillRange(0, visible.length, 1);
      explored.fillRange(0, explored.length, 1);
      return;
    }
    visible.fillRange(0, visible.length, 0);
    void reveal(double cx, double cy, double r) {
      final r2 = r * r;
      final x0 = max(0, (cx - r).floor()),
          x1 = min(mapSize - 1, (cx + r).ceil());
      final y0 = max(0, (cy - r).floor()),
          y1 = min(mapSize - 1, (cy + r).ceil());
      for (int y = y0; y <= y1; y++) {
        for (int x = x0; x <= x1; x++) {
          final dx = x + 0.5 - cx, dy = y + 0.5 - cy;
          if (dx * dx + dy * dy <= r2) {
            final i = y * mapSize + x;
            visible[i] = 1;
            explored[i] = 1;
          }
        }
      }
    }

    final p = players[human];
    for (final u in units) {
      if (u.owner == human && u.alive) reveal(u.x, u.y, p.stats(u.type).los);
    }
    for (final b in buildings) {
      if (b.owner == human && b.alive) {
        reveal(b.cx, b.cy, b.def.los + b.size / 2);
      }
    }
  }

  // --- Units -----------------------------------------------------------------

  void _updateUnit(Unit u, double dt) {
    final p = players[u.owner];
    final st = p.stats(u.type);
    u.attackCooldown -= dt;
    u.hitFlash = max(0, u.hitFlash - dt);
    u.repathTimer -= dt;
    u.scanTimer -= dt;
    u.moving = false;

    switch (u.task) {
      case Task.idle:
        if (u.isMilitary && u.scanTimer <= 0) {
          u.scanTimer = 0.5;
          final t =
              findEnemyNear(u, st.los, includeBuildings: u.owner != human);
          if (t != null) orderAttack(u, t);
        }
      case Task.move:
        if (_follow(u, st.speed, dt)) u.task = Task.idle;
      case Task.attackMove:
        if (u.scanTimer <= 0) {
          u.scanTimer = 0.4;
          final t = findEnemyNear(u, st.los);
          if (t != null) {
            final tx = u.targetX, ty = u.targetY;
            orderAttack(u, t);
            u.lastResX = tx; // reuse as resume point
            u.lastResY = ty;
            u.lastResource = null;
            u.stuckTimer = -1; // flag: resume attack-move afterwards
            return;
          }
        }
        if (_follow(u, st.speed, dt)) u.task = Task.idle;
      case Task.attack:
        _doAttack(u, st, dt);
      case Task.gather:
        _doGather(u, st, dt);
      case Task.returnRes:
        _doReturn(u, st, dt);
      case Task.build:
        _doBuild(u, st, dt);
    }
  }

  /// Moves along the current path. Returns true when the end is reached.
  bool _follow(Unit u, double speed, double dt) {
    if (u.pathIndex >= u.path.length) return true;
    var wp = u.path[u.pathIndex];
    final last = u.pathIndex == u.path.length - 1;
    double gx = wp.x + 0.5, gy = wp.y + 0.5;
    if (last && (u.task == Task.move || u.task == Task.attackMove)) {
      gx = u.targetX;
      gy = u.targetY;
    }
    if (!map.walkable(wp.x, wp.y) && !(wp.x == u.tileX && wp.y == u.tileY)) {
      // Blocked by a new building: re-path.
      final end = u.path.last;
      u.path = map.findPath(u.tileX, u.tileY, end.x, end.y, end.x, end.y);
      u.pathIndex = 0;
      if (u.path.length <= 1) return true;
      return false;
    }
    final dx = gx - u.x, dy = gy - u.y;
    final d = sqrt(dx * dx + dy * dy);
    final step = speed * dt;
    u.moving = true;
    u.animTime += dt;
    if (dx.abs() > 0.01 || dy.abs() > 0.01) {
      final sx = dx - dy; // screen-space x direction
      if (sx.abs() > 0.05) u.facing = sx > 0 ? 1 : -1;
    }
    if (d <= step) {
      u.x = gx;
      u.y = gy;
      u.pathIndex++;
      return u.pathIndex >= u.path.length;
    }
    u.x += dx / d * step;
    u.y += dy / d * step;
    return false;
  }

  void _pathTo(Unit u, Entity e) {
    if (e is Unit) {
      u.path = map.findPath(
          u.tileX, u.tileY, e.tileX, e.tileY, e.tileX, e.tileY,
          maxNodes: 3000);
    } else if (e is Building && e.def.walkable) {
      u.path = map.findPath(
          u.tileX, u.tileY, e.tx, e.ty, e.tx + e.size - 1, e.ty + e.size - 1);
    } else {
      final x0 = e.minX.floor(), y0 = e.minY.floor();
      final x1 = e.maxX.ceil() - 1, y1 = e.maxY.ceil() - 1;
      u.path = map.findPath(u.tileX, u.tileY, x0, y0, x1, y1, adjacent: true);
    }
    u.pathIndex = 0;
    // Skip the first node (current tile).
    if (u.path.length > 1) u.pathIndex = 1;
  }

  /// Moves toward an entity, re-pathing periodically. Returns true if within
  /// [reach] distance.
  bool _approach(Unit u, Entity e, double reach, double speed, double dt) {
    final d = e.distanceFrom(u.x, u.y);
    if (d <= reach) return true;
    if (u.path.isEmpty || u.pathIndex >= u.path.length || u.repathTimer <= 0) {
      if (u.repathTimer <= 0 ||
          u.path.isEmpty ||
          u.pathIndex >= u.path.length) {
        _pathTo(u, e);
        u.repathTimer = e is Unit ? 0.6 : 3.0;
        if (u.path.length <= 1 && d > reach + 0.6) {
          // Can't get closer.
          u.stuckTimer += 0.6;
        }
      }
    }
    if (u.pathIndex < u.path.length) {
      _follow(u, speed, dt);
    } else {
      // At the end of the path: step directly toward the target.
      final tx = u.x.clamp(e.minX, e.maxX), ty = u.y.clamp(e.minY, e.maxY);
      final dx = tx - u.x, dy = ty - u.y;
      final l = sqrt(dx * dx + dy * dy);
      if (l > 0.01) {
        final nx = u.x + dx / l * speed * dt, ny = u.y + dy / l * speed * dt;
        if (map.walkable(nx.floor(), ny.floor()) ||
            (e is Building && e.def.walkable)) {
          u.x = nx;
          u.y = ny;
          u.moving = true;
          u.animTime += dt;
        }
      }
    }
    return e.distanceFrom(u.x, u.y) <= reach;
  }

  void _face(Unit u, Entity e) {
    final sx = (e.cx - u.x) - (e.cy - u.y);
    if (sx.abs() > 0.05) u.facing = sx > 0 ? 1 : -1;
  }

  void _doAttack(Unit u, UnitStats st, double dt) {
    final t = u.target;
    final lost = t == null ||
        !t.alive ||
        (u.owner == human &&
            t is Unit &&
            !isVisibleTo(human, t) &&
            t.distanceFrom(u.x, u.y) > st.los + 1);
    if (lost || u.stuckTimer > 6) {
      final resume = u.stuckTimer < 0;
      final rx = u.lastResX, ry = u.lastResY;
      _resetOrder(u);
      u.task = Task.idle;
      if (resume) {
        orderMove(u, rx, ry, attackMove: true);
      } else if (u.isMilitary) {
        final n = findEnemyNear(u, st.los, includeBuildings: u.owner != human);
        if (n != null) orderAttack(u, n);
      }
      return;
    }
    final reach = st.range > 0 ? st.range : 0.45;
    if (_approach(u, t, reach, st.speed, dt)) {
      u.path = [];
      u.pathIndex = 0;
      _face(u, t);
      if (u.attackCooldown <= 0) {
        u.attackCooldown = st.reload;
        u.animTime = 0;
        final dmg = _damage(u.owner, st.attack, st.bonus, st.range > 0, t);
        if (st.range > 0) {
          projectiles.add(Projectile(
              sx: u.x,
              sy: u.y,
              sz: 14,
              target: t,
              damage: dmg,
              owner: u.owner,
              source: u));
        } else {
          applyDamage(t, dmg, u);
        }
      }
    }
  }

  double _damage(int owner, double attack, Map<UnitClass, double> bonus,
      bool pierce, Entity target) {
    double armor;
    double extra = 0;
    if (target is Unit) {
      final ts = players[target.owner].stats(target.type);
      armor = pierce ? ts.pierceArmor : ts.meleeArmor;
      extra = bonus[target.def.cls] ?? 0;
    } else {
      armor = pierce ? 7 : 1;
    }
    return max(1.0, attack - armor) + extra;
  }

  void applyDamage(Entity t, double dmg, Entity? attacker) {
    if (!t.alive) return;
    t.hp -= dmg;
    if (t is Unit) {
      t.hitFlash = 0.15;
      // Retaliate when idle.
      if (attacker != null &&
          attacker.alive &&
          t.task == Task.idle &&
          t.isMilitary) {
        orderAttack(t, attacker);
      }
      if (t.owner == human && attacker != null) _underAttack(t);
    } else if (t is Building && t.owner == human && attacker != null) {
      _underAttack(t);
    }
    if (t.owner >= 0 && attacker != null) ai.onAttacked(t, attacker);
    if (t.hp <= 0) {
      t.dead = true;
      if (t is Unit) {
        effects.add(Effect(EffectKind.blood, t.x, t.y, duration: 1.2));
        players[t.owner].unitsLost++;
        if (attacker != null && attacker.owner >= 0) {
          players[attacker.owner].kills++;
        }
      } else if (t is Building) {
        map.removeBuilding(t);
        for (final q in t.queue) {
          if (q.tech != null) players[t.owner].researching.remove(q.tech);
        }
        t.queue.clear();
        effects.add(Effect(EffectKind.dust, t.cx, t.cy,
            duration: 1.6, size: t.size.toDouble()));
        if (t.owner == human) {
          message('${t.def.name} destruído!', alert: true, x: t.cx, y: t.cy);
        } else if (t.owner == enemy) {
          message('${t.def.name} inimigo destruído!');
        }
      }
    }
  }

  void _underAttack(Entity e) {
    if (_alertCooldown > 0) return;
    _alertCooldown = 12;
    message('Você está sendo atacado!', alert: true, x: e.cx, y: e.cy);
  }

  void _doGather(Unit u, UnitStats st, double dt) {
    final p = players[u.owner];
    var t = u.target;
    if (t == null || !t.alive) {
      // Look for a nearby resource of the same kind.
      ResourceNode? next;
      if (u.lastKind != null) {
        next =
            nearestResource(u.lastKind!, u.lastResX, u.lastResY, maxDist: 10);
      }
      if (next != null) {
        orderGather(u, next);
        return;
      }
      if (t is Building && t.type == BuildingType.farm && _reseed(u, t)) return;
      if (u.carry > 0) {
        orderReturn(u);
      } else {
        _resetOrder(u);
        u.task = Task.idle;
      }
      return;
    }
    final isFarm = t is Building && t.type == BuildingType.farm;
    if (isFarm && !t.complete) {
      orderBuild(u, t);
      return;
    }
    final res = isFarm ? Res.food : (t as ResourceNode).res;
    if (u.carryType != res) {
      u.carryType = res;
      u.carry = 0;
    }
    if (u.carry >= st.carry) {
      orderReturn(u);
      return;
    }
    final reach = isFarm ? 0.0 : 0.8;
    if (!_approach(u, t, reach, st.speed, dt)) {
      if (u.stuckTimer > 4) {
        // Try another resource of the same kind.
        u.stuckTimer = 0;
        if (t is ResourceNode) {
          final alt = resources
              .where((r) => r.kind == t.kind && r.alive && r != t)
              .toList()
            ..sort((a, b) =>
                a.distanceFrom(u.x, u.y).compareTo(b.distanceFrom(u.x, u.y)));
          if (alt.isNotEmpty)
            orderGather(u, alt[rnd.nextInt(min(3, alt.length))]);
        }
      }
      return;
    }
    u.path = [];
    u.pathIndex = 0;
    _face(u, t);
    u.animTime += dt;
    final rate = isFarm
        ? p.gatherRate(null, farm: true)
        : p.gatherRate((t as ResourceNode).kind);
    double amount = rate * dt;
    if (isFarm) {
      final f = t;
      amount = min(amount, f.food);
      f.food -= amount;
      if (f.food <= 0.01) {
        f.dead = true;
        map.removeBuilding(f);
      }
    } else {
      final n = t as ResourceNode;
      amount = min(amount, n.amount);
      n.amount -= amount;
      if (n.amount <= 0.01) {
        n.dead = true;
        map.removeResource(n);
        effects.add(Effect(EffectKind.sparkle, n.cx, n.cy, duration: 0.5));
      }
      u.lastResX = n.cx;
      u.lastResY = n.cy;
    }
    u.carry += amount;
    if (u.carry >= st.carry) orderReturn(u);
  }

  bool _reseed(Unit u, Building old) {
    final p = players[u.owner];
    final cost = buildingDefs[BuildingType.farm]!.cost;
    if (!p.canAfford(cost) ||
        !map.canPlace(BuildingType.farm, old.tx, old.ty)) {
      return false;
    }
    p.pay(cost);
    final f = addBuilding(BuildingType.farm, u.owner, old.tx, old.ty);
    orderBuild(u, f);
    return true;
  }

  void _doReturn(Unit u, UnitStats st, double dt) {
    final t = u.target;
    if (u.carryType == null || u.carry <= 0) {
      _resumeGather(u);
      return;
    }
    if (t == null || !t.alive) {
      orderReturn(u);
      if (u.task == Task.idle) return;
      return;
    }
    if (!_approach(u, t, 0.8, st.speed, dt)) {
      if (u.stuckTimer > 6) {
        u.stuckTimer = 0;
        u.task = Task.idle;
      }
      return;
    }
    final p = players[u.owner];
    p.res[u.carryType!] = p.res[u.carryType!]! + u.carry;
    p.totalGathered += u.carry;
    u.carry = 0;
    _resumeGather(u);
  }

  void _resumeGather(Unit u) {
    final last = u.lastResource;
    if (last != null && last.alive) {
      final kind = u.lastKind;
      orderGather(u, last);
      u.lastKind = kind;
      return;
    }
    if (u.lastKind != null) {
      final n =
          nearestResource(u.lastKind!, u.lastResX, u.lastResY, maxDist: 12);
      if (n != null) {
        orderGather(u, n);
        return;
      }
    }
    if (last is Building &&
        last.type == BuildingType.farm &&
        _reseed(u, last)) {
      return;
    }
    _resetOrder(u);
    u.task = Task.idle;
  }

  void _doBuild(Unit u, UnitStats st, double dt) {
    final b = u.target;
    if (b is! Building || !b.alive) {
      _resetOrder(u);
      u.task = Task.idle;
      return;
    }
    final repairing = b.complete;
    if (repairing && b.hp >= b.maxHp) {
      _afterBuild(u, b);
      return;
    }
    final reach = b.def.walkable ? 0.0 : 0.8;
    if (!_approach(u, b, reach, st.speed, dt)) {
      if (u.stuckTimer > 8) {
        _resetOrder(u);
        u.task = Task.idle;
      }
      return;
    }
    u.path = [];
    u.pathIndex = 0;
    _face(u, b);
    u.animTime += dt;
    if (!repairing) {
      final inc = dt / b.def.buildTime;
      b.progress = min(1.0, b.progress + inc);
      b.hp = min(b.maxHp, b.hp + inc * b.maxHp);
      if (b.complete) {
        b.hp = max(b.hp, b.maxHp * 0.999);
        b.hp = b.maxHp;
        players[b.owner].buildingsBuilt++;
        if (b.owner == human) message('${b.def.name} concluído.');
        _afterBuild(u, b);
      }
    } else {
      final p = players[u.owner];
      // Repairing costs a little wood.
      if (p.res[Res.wood]! > 0.2) {
        b.hp = min(b.maxHp, b.hp + b.maxHp / b.def.buildTime * dt * 0.5);
        p.res[Res.wood] = p.res[Res.wood]! - dt * 0.2;
      }
    }
  }

  void _afterBuild(Unit u, Building b) {
    _resetOrder(u);
    u.task = Task.idle;
    ResourceNode? n;
    switch (b.type) {
      case BuildingType.farm:
        // Only one farmer per farm.
        final busy = units.any(
            (o) => o != u && o.alive && o.task == Task.gather && o.target == b);
        if (!busy) {
          orderGather(u, b);
          return;
        }
      case BuildingType.lumberCamp:
        n = nearestResource(ResourceKind.tree, b.cx, b.cy, maxDist: 12);
      case BuildingType.mill:
        n = nearestResource(ResourceKind.berries, b.cx, b.cy, maxDist: 10);
      case BuildingType.miningCamp:
        final g = nearestResource(ResourceKind.gold, b.cx, b.cy, maxDist: 10);
        final s = nearestResource(ResourceKind.stone, b.cx, b.cy, maxDist: 10);
        n = g ?? s;
        if (g != null && s != null) {
          n = g.distanceFrom(b.cx, b.cy) <= s.distanceFrom(b.cx, b.cy) ? g : s;
        }
      default:
        break;
    }
    if (n != null) {
      orderGather(u, n);
      return;
    }
    // Help with other nearby foundations.
    for (final o in buildings) {
      if (o.owner == u.owner &&
          o.alive &&
          !o.complete &&
          o.distanceFrom(u.x, u.y) < 8) {
        orderBuild(u, o);
        return;
      }
    }
  }

  void _separate(double dt) {
    final buckets = <int, List<Unit>>{};
    for (final u in units) {
      if (!u.alive) continue;
      buckets.putIfAbsent(u.tileY * mapSize + u.tileX, () => []).add(u);
    }
    for (final u in units) {
      if (!u.alive || u.moving) continue;
      for (int oy = -1; oy <= 1; oy++) {
        for (int ox = -1; ox <= 1; ox++) {
          final list = buckets[(u.tileY + oy) * mapSize + (u.tileX + ox)];
          if (list == null) continue;
          for (final o in list) {
            if (o == u) continue;
            final dx = u.x - o.x, dy = u.y - o.y;
            final d2 = dx * dx + dy * dy;
            if (d2 < 0.12 && d2 > 1e-6) {
              final d = sqrt(d2);
              final push = (0.35 - d) * dt * 2;
              final nx = u.x + dx / d * push, ny = u.y + dy / d * push;
              if (map.walkable(nx.floor(), ny.floor())) {
                u.x = nx;
                u.y = ny;
              }
            } else if (d2 <= 1e-6) {
              u.x += (rnd.nextDouble() - 0.5) * 0.02;
              u.y += (rnd.nextDouble() - 0.5) * 0.02;
            }
          }
        }
      }
    }
  }

  // --- Buildings -------------------------------------------------------------

  void _updateBuilding(Building b, double dt) {
    b.animTime += dt;
    if (!b.complete) return;
    final p = players[b.owner];

    if (b.queue.isNotEmpty) {
      final q = b.queue.first;
      final total =
          q.unit != null ? unitDefs[q.unit]!.trainTime : techDefs[q.tech]!.time;
      if (q.unit != null && q.progress >= total) {
        if (p.pop < p.popCap) {
          _spawnFrom(b, q.unit!);
          b.queue.removeAt(0);
        } else if (b.owner == human && _houseWarnCooldown <= 0) {
          _houseWarnCooldown = 15;
          message('Precisa de mais casas! (população ${p.pop}/${p.popCap})',
              alert: true);
        }
      } else {
        q.progress += dt;
        if (q.tech != null && q.progress >= total) {
          b.queue.removeAt(0);
          p.completeTech(q.tech!);
          // Refresh HP of existing units affected by HP techs.
          for (final u in units) {
            if (u.owner == b.owner && u.alive) {
              final st = p.stats(u.type);
              if (st.hp > u.maxHp) {
                u.hp += st.hp - u.maxHp;
                u.maxHp = st.hp;
              }
            }
          }
          if (b.owner == human) {
            final age = ageTechs[q.tech];
            message(age != null
                ? 'Você avançou para a ${ageNames[age]}!'
                : 'Pesquisa concluída: ${techDefs[q.tech]!.name}');
          } else if (ageTechs.containsKey(q.tech)) {
            message('O inimigo avançou para a ${ageNames[ageTechs[q.tech]]}.',
                alert: true);
          }
        }
      }
    }

    // Defensive arrows.
    if (b.def.attack > 0) {
      b.attackCooldown -= dt;
      if (b.attackCooldown <= 0) {
        final range = p.buildingRange(b.def.range);
        Unit? target;
        double bd = range;
        for (final u in units) {
          if (!u.alive || u.owner == b.owner) continue;
          final d = b.distanceFrom(u.x, u.y);
          if (d < bd) {
            bd = d;
            target = u;
          }
        }
        if (target != null) {
          b.attackCooldown = 2.0;
          final arrows = b.type == BuildingType.castle ? 3 : 1;
          for (int i = 0; i < arrows; i++) {
            final dmg = _damage(b.owner, p.buildingAttack(b.def.attack),
                const {}, true, target);
            projectiles.add(Projectile(
                sx: b.cx + (rnd.nextDouble() - 0.5) * 0.6,
                sy: b.cy + (rnd.nextDouble() - 0.5) * 0.6,
                sz: b.type == BuildingType.tower ? 56 : 40,
                target: target,
                damage: dmg,
                owner: b.owner,
                source: b));
          }
        } else {
          b.attackCooldown = 0.4;
        }
      }
    }
  }

  void _spawnFrom(Building b, UnitType t) {
    final p = players[b.owner];
    // Find a free tile around the footprint closest to the rally point.
    final rx = b.rallyX ?? (b.cx + 2), ry = b.rallyY ?? (b.cy + 2);
    Point<int>? best;
    double bd = double.infinity;
    for (int y = b.ty - 1; y <= b.ty + b.size; y++) {
      for (int x = b.tx - 1; x <= b.tx + b.size; x++) {
        if (!map.walkable(x, y)) continue;
        final d = pow(x + 0.5 - rx, 2) + pow(y + 0.5 - ry, 2).toDouble();
        if (d < bd) {
          bd = d.toDouble();
          best = Point(x, y);
        }
      }
    }
    best ??= map.nearestWalkable(b.tx, b.ty, maxR: 6);
    if (best == null) return;
    final u = spawnUnit(t, b.owner, best.x + 0.5, best.y + 0.5);
    p.unitsTrained++;
    if (b.rallyX != null) {
      final e = map.entityAt(b.rallyX!.floor(), b.rallyY!.floor());
      if (u.isVillager && e is ResourceNode) {
        orderGather(u, e);
      } else if (u.isVillager &&
          e is Building &&
          e.owner == b.owner &&
          e.type == BuildingType.farm) {
        orderGather(u, e);
      } else {
        orderMove(u, b.rallyX!, b.rallyY!);
      }
    }
    if (b.owner == enemy) ai.onUnitSpawned(u);
  }

  void _updateProjectiles(double dt) {
    for (final pr in projectiles) {
      pr.t += dt;
      final k = (pr.t / pr.duration).clamp(0.0, 1.0);
      final ex = pr.target.alive ? pr.target.cx : pr.tx;
      final ey = pr.target.alive ? pr.target.cy : pr.ty;
      pr.x = pr.sx + (ex - pr.sx) * k;
      pr.y = pr.sy + (ey - pr.sy) * k;
      pr.z = pr.sz * (1 - k) + 8 * k + sin(k * pi) * 18;
      if (pr.t >= pr.duration && pr.target.alive) {
        final src = pr.source;
        applyDamage(
            pr.target, pr.damage, src != null && src.alive ? src : null);
      }
    }
    projectiles.removeWhere((p) => p.t >= p.duration);
  }

  // --- Market ----------------------------------------------------------------

  final Map<Res, double> marketPrice = {
    Res.food: 100,
    Res.wood: 100,
    Res.stone: 130,
  };

  bool marketBuy(int owner, Res r) {
    final p = players[owner];
    final price = marketPrice[r]!.round();
    if (p.res[Res.gold]! < price) return false;
    p.res[Res.gold] = p.res[Res.gold]! - price;
    p.res[r] = p.res[r]! + 100;
    marketPrice[r] = min(400, marketPrice[r]! + 6);
    return true;
  }

  bool marketSell(int owner, Res r) {
    final p = players[owner];
    if (p.res[r]! < 100) return false;
    p.res[r] = p.res[r]! - 100;
    final gain = (marketPrice[r]! * 0.7).round();
    p.res[Res.gold] = p.res[Res.gold]! + gain;
    marketPrice[r] = max(25, marketPrice[r]! - 6);
    return true;
  }
}
