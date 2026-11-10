import 'dart:math';

import 'config.dart';

int _nextId = 1;

abstract class Entity {
  final int id = _nextId++;
  int owner; // -1 = gaia, 0 = player, 1 = enemy
  double hp;
  double maxHp;
  bool dead = false;

  Entity({required this.owner, required this.hp, required this.maxHp});

  bool get alive => !dead && hp > 0;

  /// Center in tile coordinates.
  double get cx;
  double get cy;

  /// Footprint rectangle in tile coordinates (min inclusive, max exclusive).
  double get minX;
  double get minY;
  double get maxX;
  double get maxY;

  double depth() => cx + cy;

  /// Distance from point to the footprint rectangle.
  double distanceFrom(double px, double py) {
    final dx = px < minX ? minX - px : (px > maxX ? px - maxX : 0.0);
    final dy = py < minY ? minY - py : (py > maxY ? py - maxY : 0.0);
    return sqrt(dx * dx + dy * dy);
  }
}

enum Task { idle, move, attackMove, gather, returnRes, build, attack }

class Unit extends Entity {
  final UnitType type;
  double x, y;
  double facing = 1; // 1 => right, -1 => left
  Task task = Task.idle;
  Entity? target;
  double targetX = 0, targetY = 0;
  List<Point<int>> path = [];
  int pathIndex = 0;
  double repathTimer = 0;
  double attackCooldown = 0;
  double animTime = 0;
  bool moving = false;
  double hitFlash = 0;

  // Villager economy state
  Res? carryType;
  double carry = 0;
  ResourceKind? lastKind;
  double lastResX = 0, lastResY = 0;
  Entity? lastResource;

  // Auto-acquire scan throttle
  double scanTimer = 0;
  double stuckTimer = 0;

  Unit({
    required this.type,
    required super.owner,
    required this.x,
    required this.y,
    required double hp,
  }) : super(hp: hp, maxHp: hp);

  UnitDef get def => unitDefs[type]!;
  bool get isVillager => type == UnitType.villager;
  bool get isMilitary => !isVillager;

  @override
  double get cx => x;
  @override
  double get cy => y;
  @override
  double get minX => x - 0.2;
  @override
  double get minY => y - 0.2;
  @override
  double get maxX => x + 0.2;
  @override
  double get maxY => y + 0.2;

  int get tileX => x.floor();
  int get tileY => y.floor();
}

class QueueItem {
  final UnitType? unit;
  final Tech? tech;
  double progress = 0; // seconds elapsed
  QueueItem.unit(UnitType this.unit) : tech = null;
  QueueItem.tech(Tech this.tech) : unit = null;

  Cost get cost => unit != null ? unitDefs[unit]!.cost : techDefs[tech]!.cost;
  String get name => unit != null ? unitDefs[unit]!.name : techDefs[tech]!.name;
}

class Building extends Entity {
  final BuildingType type;
  final int tx, ty;
  double progress; // 0..1 construction progress
  final List<QueueItem> queue = [];
  double? rallyX, rallyY;
  double attackCooldown = 0;
  double food = 0; // farms only
  double animTime = 0;
  bool explosionDone = false;

  Building({
    required this.type,
    required super.owner,
    required this.tx,
    required this.ty,
    this.progress = 0,
  }) : super(
          hp: max(1, buildingDefs[type]!.hp * progress),
          maxHp: buildingDefs[type]!.hp,
        );

  BuildingDef get def => buildingDefs[type]!;
  int get size => def.size;
  bool get complete => progress >= 1;

  @override
  double get cx => tx + size / 2;
  @override
  double get cy => ty + size / 2;
  @override
  double get minX => tx.toDouble();
  @override
  double get minY => ty.toDouble();
  @override
  double get maxX => (tx + size).toDouble();
  @override
  double get maxY => (ty + size).toDouble();

  @override
  double depth() => tx + ty + size * 1.0 - 0.6;
}

class ResourceNode extends Entity {
  final ResourceKind kind;
  final int tx, ty;
  double amount;
  final double variant; // visual variation 0..1

  ResourceNode({
    required this.kind,
    required this.tx,
    required this.ty,
    required this.amount,
    required this.variant,
  }) : super(owner: -1, hp: 1, maxHp: 1);

  Res get res => resourceKindRes[kind]!;

  @override
  bool get alive => !dead && amount > 0;

  @override
  double get cx => tx + 0.5;
  @override
  double get cy => ty + 0.5;
  @override
  double get minX => tx.toDouble();
  @override
  double get minY => ty.toDouble();
  @override
  double get maxX => tx + 1.0;
  @override
  double get maxY => ty + 1.0;
}

class Projectile {
  double x, y, z;
  final double sx, sy, sz;
  final Entity target;
  final double damage;
  final int owner;
  final Entity? source;
  double t = 0;
  final double duration;
  final double tx, ty;

  Projectile({
    required this.sx,
    required this.sy,
    required this.sz,
    required this.target,
    required this.damage,
    required this.owner,
    this.source,
  })  : x = sx,
        y = sy,
        z = sz,
        tx = target.cx,
        ty = target.cy,
        duration = max(
            0.25, sqrt(pow(target.cx - sx, 2) + pow(target.cy - sy, 2)) / 9.0);
}

enum EffectKind { dust, blood, sparkle, flag }

class Effect {
  final EffectKind kind;
  final double x, y;
  double t = 0;
  final double duration;
  final double size;
  Effect(this.kind, this.x, this.y, {this.duration = 0.8, this.size = 1});
}
