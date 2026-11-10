import 'dart:math';

import 'config.dart';
import 'entities.dart';
import 'player.dart';
import 'world.dart';

/// Simple scripted opponent: grows an economy, ages up, builds an army and
/// sends attack waves at the human player.
class EnemyAI {
  final GameWorld w;
  final int me;
  double _timer = 2;
  double _nextAttack;
  int _waveSize;
  int _waves = 0;
  final Set<Unit> _attackers = {};
  Entity? _threat;
  double _rebalanceTimer = 0;
  double _threatTime = -100;

  EnemyAI(this.w, this.me)
      : _nextAttack = switch (w.difficulty) {
          Difficulty.easy => 720,
          Difficulty.normal => 480,
          Difficulty.hard => 330,
        },
        _waveSize = switch (w.difficulty) {
          Difficulty.easy => 5,
          Difficulty.normal => 7,
          Difficulty.hard => 9,
        };

  int get _villagerTarget => switch (w.difficulty) {
        Difficulty.easy => 18,
        Difficulty.normal => 26,
        Difficulty.hard => 34,
      };

  int _ageThreshold(Age a) => switch (a) {
        Age.dark => w.difficulty == Difficulty.hard ? 19 : 17,
        Age.feudal => w.difficulty == Difficulty.easy ? 22 : 25,
        Age.castle => 30,
        Age.imperial => 999,
      };

  Tech? _nextAgeTech(Age a) => switch (a) {
        Age.dark => Tech.feudalAge,
        Age.feudal => Tech.castleAge,
        Age.castle => Tech.imperialAge,
        Age.imperial => null,
      };

  bool _affordWithReserve(PlayerState p, Cost c, Cost reserve) {
    for (final r in Res.values) {
      if (p.res[r]! - reserve.of(r) < c.of(r)) return false;
    }
    return true;
  }

  void update(double dt) {
    _timer -= dt;
    if (_timer > 0) return;
    _timer = 1.0;
    _think();
  }

  void onAttacked(Entity victim, Entity attacker) {
    if (victim.owner == me && attacker.owner != me && attacker.owner >= 0) {
      _threat = attacker;
      _threatTime = w.time;
    }
  }

  void onUnitSpawned(Unit u) {
    if (u.isMilitary) {
      final r = _rallyPoint();
      if (r != null) w.orderMove(u, r.x, r.y);
    }
  }

  Building? get _tc {
    for (final b in w.buildings) {
      if (b.owner == me && b.alive && b.type == BuildingType.townCenter) {
        return b;
      }
    }
    return null;
  }

  Point<double>? _rallyPoint() {
    final tc = _tc;
    if (tc == null) return null;
    final c = GameWorld.mapSize / 2;
    final dx = c - tc.cx, dy = c - tc.cy;
    final l = sqrt(dx * dx + dy * dy);
    return Point(tc.cx + dx / l * 5, tc.cy + dy / l * 5);
  }

  int _count(BuildingType t, {bool includeFoundations = true}) => w.buildings
      .where((b) =>
          b.owner == me &&
          b.alive &&
          b.type == t &&
          (includeFoundations || b.complete))
      .length;

  bool _hasFoundation() => w.buildings.any((b) =>
      b.owner == me && b.alive && !b.complete && b.type != BuildingType.farm);

  void _think() {
    final p = w.players[me];
    final tc = _tc;
    final mine = w.units.where((u) => u.owner == me && u.alive).toList();
    final vills = mine.where((u) => u.isVillager).toList();
    final army = mine.where((u) => u.isMilitary).toList();
    _attackers.removeWhere((u) => !u.alive);

    // --- Villagers ---------------------------------------------------------
    if (tc != null && tc.complete) {
      final queuedV = tc.queue.where((q) => q.unit == UnitType.villager).length;
      final agingUp = tc.queue.any((q) => q.tech != null);
      final ageTech = _nextAgeTech(p.age);
      final waitAge = ageTech != null &&
          vills.length + queuedV >= _ageThreshold(p.age) &&
          !p.researching.contains(ageTech);
      if (!agingUp &&
          !waitAge &&
          queuedV < 2 &&
          vills.length + queuedV < _villagerTarget) {
        w.train(tc, UnitType.villager);
      }
    }

    // --- Houses --------------------------------------------------------------
    final houseFoundations = w.buildings.where((b) =>
        b.owner == me &&
        b.alive &&
        !b.complete &&
        b.type == BuildingType.house);
    if (p.popCap < 200 && p.pop + 4 >= p.popCap && houseFoundations.isEmpty) {
      _build(BuildingType.house, vills);
    }

    // --- Economy buildings -----------------------------------------------------
    if (vills.length >= 5 && !_hasFoundation()) {
      if (_count(BuildingType.lumberCamp) == 0) {
        _buildNearResource(BuildingType.lumberCamp, ResourceKind.tree, vills);
      } else if (_count(BuildingType.mill) == 0 &&
          w.nearestResource(ResourceKind.berries, tc?.cx ?? 0, tc?.cy ?? 0,
                  maxDist: 14) !=
              null) {
        _buildNearResource(BuildingType.mill, ResourceKind.berries, vills);
      } else if (_count(BuildingType.miningCamp) == 0 && vills.length >= 9) {
        _buildNearResource(BuildingType.miningCamp, ResourceKind.gold, vills);
      } else if (_count(BuildingType.barracks) == 0 && vills.length >= 10) {
        _build(BuildingType.barracks, vills);
      } else if (p.age.index >= Age.feudal.index) {
        if (_count(BuildingType.archeryRange) == 0) {
          _build(BuildingType.archeryRange, vills);
        } else if (_count(BuildingType.blacksmith) == 0) {
          _build(BuildingType.blacksmith, vills);
        } else if (_count(BuildingType.stable) == 0) {
          _build(BuildingType.stable, vills);
        } else if (_count(BuildingType.tower) < 2 && p.res[Res.stone]! > 200) {
          _build(BuildingType.tower, vills);
        } else if (_count(BuildingType.lumberCamp) < 2 && vills.length > 18) {
          _buildNearResource(BuildingType.lumberCamp, ResourceKind.tree, vills,
              avoidExisting: true);
        } else if (p.age.index >= Age.castle.index &&
            _count(BuildingType.barracks) < 2 &&
            p.res[Res.wood]! > 300) {
          _build(BuildingType.barracks, vills);
        } else if (p.age.index >= Age.castle.index &&
            _count(BuildingType.castle) == 0 &&
            p.res[Res.stone]! >= 650) {
          _build(BuildingType.castle, vills);
        }
      }
    }

    // --- Age up --------------------------------------------------------------
    final nextAge = _nextAgeTech(p.age);
    if (tc != null &&
        nextAge != null &&
        vills.length >= _ageThreshold(p.age) &&
        !p.researching.contains(nextAge)) {
      if (tc.queue.isEmpty) {
        w.research(tc, nextAge);
      }
    }

    // --- Research --------------------------------------------------------------
    final saving = nextAge != null &&
        vills.length >= _ageThreshold(p.age) - 3 &&
        !p.researching.contains(nextAge);
    final reserve = saving ? techDefs[nextAge]!.cost : const Cost();
    {
      const order = [
        Tech.loom,
        Tech.doubleBitAxe,
        Tech.horseCollar,
        Tech.wheelbarrow,
        Tech.forging,
        Tech.fletching,
        Tech.manAtArms,
        Tech.scaleMail,
        Tech.paddedArcher,
        Tech.goldMining,
        Tech.bloodlines,
        Tech.bowSaw,
        Tech.crossbowman,
        Tech.pikeman,
        Tech.ironCasting,
        Tech.bodkinArrow,
        Tech.longSwordsman,
        Tech.scaleBarding,
        Tech.heavyPlow,
        Tech.handCart,
        Tech.husbandry,
        Tech.thumbRing,
        Tech.cavalier,
      ];
      for (final t in order) {
        if (p.has(t) || p.researching.contains(t)) continue;
        final d = techDefs[t]!;
        if (p.age.index < d.minAge.index) continue;
        if (d.requires != null && !p.has(d.requires!)) continue;
        if (!_affordWithReserve(p, d.cost, reserve)) continue;
        final b = _idleBuilding(d.at);
        if (b == null) continue;
        if (d.at == BuildingType.townCenter && saving) continue;
        if (w.research(b, t)) break;
      }
    }

    // --- Military production -------------------------------------------------
    {
      for (final b in w.buildings) {
        if (b.owner != me || !b.alive || !b.complete) continue;
        if (b.def.trains.isEmpty || b.type == BuildingType.townCenter) continue;
        if (b.queue.length >= 2) continue;
        final options =
            b.def.trains.where((t) => w.trainReason(b, t) == null).toList();
        if (options.isEmpty) continue;
        // Prefer the strongest available unit.
        final pick = options.last == UnitType.knight ||
                options.last == UnitType.skirmisher && w.rnd.nextBool()
            ? options.first
            : options[w.rnd.nextInt(options.length)];
        if (!_affordWithReserve(p, unitDefs[pick]!.cost, reserve)) continue;
        if (p.pop + 1 < p.popCap || b.queue.isEmpty) w.train(b, pick);
      }
    }

    // --- Economy assignments ----------------------------------------------------
    _assignVillagers(vills);

    // --- Defense ----------------------------------------------------------------
    final threat = _threat;
    if (threat != null &&
        threat.alive &&
        w.time - _threatTime < 20 &&
        tc != null &&
        threat.distanceFrom(tc.cx, tc.cy) < 20) {
      for (final u in army) {
        if (_attackers.contains(u)) continue;
        if (u.task == Task.idle || u.task == Task.move)
          w.orderAttack(u, threat);
      }
    } else if (threat != null && (!threat.alive || w.time - _threatTime > 20)) {
      _threat = null;
    }

    // --- Attack waves -------------------------------------------------------------
    final home = army.where((u) => !_attackers.contains(u)).toList();
    if (w.time >= _nextAttack && home.length >= _waveSize) {
      final target = _pickTarget();
      if (target != null) {
        _waves++;
        for (final u in home) {
          _attackers.add(u);
        }
        w.orderGroupMove(home, target.cx, target.cy, attackMove: true);
        _waveSize = min(30, _waveSize + 3);
        _nextAttack = w.time + 100 + w.rnd.nextInt(60);
        w.message('Um exército inimigo está marchando! (onda $_waves)',
            alert: true);
      }
    }
    // Keep attackers pushing once they finish their orders.
    for (final u in _attackers) {
      if (u.task == Task.idle) {
        final t = _pickTarget(from: u);
        if (t != null) w.orderMove(u, t.cx, t.cy, attackMove: true);
      }
    }
  }

  Building? _idleBuilding(BuildingType t) {
    for (final b in w.buildings) {
      if (b.owner == me &&
          b.alive &&
          b.complete &&
          b.type == t &&
          b.queue.isEmpty) {
        return b;
      }
    }
    return null;
  }

  Entity? _pickTarget({Unit? from}) {
    final ox = from?.x ?? _tc?.cx ?? GameWorld.mapSize / 2;
    final oy = from?.y ?? _tc?.cy ?? GameWorld.mapSize / 2;
    Entity? best;
    double bd = double.infinity;
    for (final b in w.buildings) {
      if (b.owner != GameWorld.human || !b.alive) continue;
      final d = b.distanceFrom(ox, oy) + (b.type == BuildingType.farm ? 6 : 0);
      if (d < bd) {
        bd = d;
        best = b;
      }
    }
    if (best != null) return best;
    for (final u in w.units) {
      if (u.owner != GameWorld.human || !u.alive) continue;
      final d = u.distanceFrom(ox, oy);
      if (d < bd) {
        bd = d;
        best = u;
      }
    }
    return best;
  }

  Unit? _pickBuilder(List<Unit> vills) {
    Unit? best;
    for (final v in vills) {
      if (v.task == Task.build) continue;
      if (v.task == Task.idle) return v;
      if (v.carryType == Res.wood || v.lastKind == ResourceKind.tree)
        best ??= v;
    }
    return best ?? (vills.isNotEmpty ? vills.first : null);
  }

  void _build(BuildingType t, List<Unit> vills) {
    if (w.buildReason(me, t) != null) return;
    final tc = _tc;
    if (tc == null) return;
    final spot = _findSpot(t, tc.cx, tc.cy, 3, 14);
    if (spot == null) return;
    final builder = _pickBuilder(vills);
    if (builder == null) return;
    final helpers = <Unit>[builder];
    if (t == BuildingType.castle || t == BuildingType.barracks) {
      for (final v in vills) {
        if (helpers.length >= 3) break;
        if (v != builder && v.task != Task.build) helpers.add(v);
      }
    }
    w.placeFoundation(me, t, spot.x, spot.y, helpers);
  }

  void _buildNearResource(BuildingType t, ResourceKind k, List<Unit> vills,
      {bool avoidExisting = false}) {
    if (w.buildReason(me, t) != null) return;
    final tc = _tc;
    if (tc == null) return;
    // Find a resource node with many neighbours, close to the TC.
    ResourceNode? best;
    double bs = double.infinity;
    for (final r in w.resources) {
      if (r.kind != k || !r.alive) continue;
      final d = r.distanceFrom(tc.cx, tc.cy);
      if (d > 22) continue;
      if (avoidExisting &&
          w.buildings.any((b) =>
              b.owner == me && b.type == t && b.distanceFrom(r.cx, r.cy) < 7)) {
        continue;
      }
      int n = 0;
      for (final o in w.resources) {
        if (o.kind == k && (o.cx - r.cx).abs() < 3 && (o.cy - r.cy).abs() < 3)
          n++;
      }
      final score = d - n * 0.8;
      if (score < bs) {
        bs = score;
        best = r;
      }
    }
    if (best == null) return;
    final spot = _findSpot(t, best.cx, best.cy, 1, 5, margin: false);
    if (spot == null) return;
    final builder = _pickBuilder(vills);
    if (builder == null) return;
    w.placeFoundation(me, t, spot.x, spot.y, [builder]);
  }

  Point<int>? _findSpot(
      BuildingType t, double cx, double cy, int minR, int maxR,
      {bool margin = true}) {
    final s = buildingDefs[t]!.size;
    final map = w.map;
    final candidates = <Point<int>>[];
    for (int r = minR; r <= maxR; r++) {
      for (int dy = -r; dy <= r; dy++) {
        for (int dx = -r; dx <= r; dx++) {
          if (max(dx.abs(), dy.abs()) != r) continue;
          final tx = (cx + dx - s / 2).round(), ty = (cy + dy - s / 2).round();
          if (!map.canPlace(t, tx, ty)) continue;
          if (margin) {
            bool ok = true;
            for (int y = ty - 1; y <= ty + s && ok; y++) {
              for (int x = tx - 1; x <= tx + s; x++) {
                if (y >= ty && y < ty + s && x >= tx && x < tx + s) continue;
                if (!map.inBounds(x, y) || map.entityAt(x, y) is Building) {
                  ok = false;
                  break;
                }
              }
            }
            if (!ok) continue;
          }
          candidates.add(Point(tx, ty));
        }
      }
      if (candidates.isNotEmpty) {
        return candidates[w.rnd.nextInt(candidates.length)];
      }
    }
    return null;
  }

  void _assignVillagers(List<Unit> vills) {
    final p = w.players[me];
    final tc = _tc;
    if (tc == null) return;
    final counts = {for (final r in Res.values) r: 0};
    final idle = <Unit>[];
    for (final v in vills) {
      if (v.task == Task.idle) {
        idle.add(v);
        continue;
      }
      if (v.task == Task.gather || v.task == Task.returnRes) {
        final r = v.carryType ??
            (v.lastKind != null ? resourceKindRes[v.lastKind]! : Res.food);
        counts[r] = counts[r]! + 1;
      }
    }
    final ratio = switch (p.age) {
      Age.dark => {
          Res.food: 0.55,
          Res.wood: 0.35,
          Res.gold: 0.10,
          Res.stone: 0.0
        },
      Age.feudal => {
          Res.food: 0.40,
          Res.wood: 0.35,
          Res.gold: 0.18,
          Res.stone: 0.07
        },
      _ => {Res.food: 0.42, Res.wood: 0.26, Res.gold: 0.24, Res.stone: 0.08},
    };
    // Rebalance one worker at a time toward the target ratio.
    _rebalanceTimer -= 1;
    if (idle.isEmpty && _rebalanceTimer <= 0) {
      _rebalanceTimer = 4;
      final total = counts.values.fold(0, (a, b) => a + b);
      Res? over, under;
      double mo = 1.5, mu = 1.5;
      for (final r in Res.values) {
        final diff = counts[r]! - ratio[r]! * total;
        // Hoarded resources count as over-staffed.
        final hoard = p.res[r]! > 800 ? 2.0 : 0.0;
        if (diff + hoard > mo) {
          mo = diff + hoard;
          over = r;
        }
        if (-diff > mu) {
          mu = -diff;
          under = r;
        }
      }
      if (over != null && under != null) {
        for (final v in vills) {
          if (v.task == Task.gather && v.carryType == over) {
            if (_sendTo(v, under, tc)) {
              counts[over] = counts[over]! - 1;
              counts[under] = counts[under]! + 1;
            }
            break;
          }
        }
      }
    }
    if (idle.isEmpty) return;
    for (final v in idle) {
      final total = counts.values.fold(0, (a, b) => a + b) + 1;
      Res pick = Res.food;
      double worst = -1e9;
      for (final r in Res.values) {
        final deficit = ratio[r]! - counts[r]! / total;
        if (deficit > worst) {
          worst = deficit;
          pick = r;
        }
      }
      if (_sendTo(v, pick, tc)) {
        counts[pick] = counts[pick]! + 1;
      } else if (_sendTo(v, Res.wood, tc)) {
        counts[Res.wood] = counts[Res.wood]! + 1;
      }
    }
  }

  bool _sendTo(Unit v, Res r, Building tc) {
    switch (r) {
      case Res.food:
        final mill0 = w.buildings.where(
            (b) => b.owner == me && b.alive && b.type == BuildingType.mill);
        final fx = mill0.isNotEmpty ? mill0.first.cx : tc.cx;
        final fy = mill0.isNotEmpty ? mill0.first.cy : tc.cy;
        final berries =
            w.nearestResource(ResourceKind.berries, fx, fy, maxDist: 9);
        if (berries != null) {
          w.orderGather(v, berries);
          return true;
        }
        // Free farm?
        for (final b in w.buildings) {
          if (b.owner == me && b.alive && b.type == BuildingType.farm) {
            final busy = w.units.any((o) =>
                o.alive &&
                o != v &&
                o.target == b &&
                (o.task == Task.gather || o.task == Task.build));
            if (!busy) {
              if (b.complete) {
                w.orderGather(v, b);
              } else {
                w.orderBuild(v, b);
              }
              return true;
            }
          }
        }
        if (w.buildReason(me, BuildingType.farm) == null) {
          final mill = w.buildings.firstWhere(
              (b) => b.owner == me && b.alive && b.type == BuildingType.mill,
              orElse: () => tc);
          final spot = _findSpot(BuildingType.farm, mill.cx, mill.cy, 2, 9,
              margin: false);
          if (spot != null) {
            return w.placeFoundation(
                    me, BuildingType.farm, spot.x, spot.y, [v]) !=
                null;
          }
        }
        return false;
      case Res.wood:
      case Res.gold:
      case Res.stone:
        final kind = r == Res.wood
            ? ResourceKind.tree
            : (r == Res.gold ? ResourceKind.gold : ResourceKind.stone);
        Building? camp;
        for (final b in w.buildings) {
          if (b.owner == me &&
              b.alive &&
              b.complete &&
              b.def.dropOff.contains(r) &&
              b.type != BuildingType.townCenter) {
            camp = b;
            break;
          }
        }
        final from = camp ?? tc;
        final n = w.nearestResource(kind, from.cx, from.cy, maxDist: 25);
        if (n == null) return false;
        w.orderGather(v, n);
        return true;
    }
  }
}
