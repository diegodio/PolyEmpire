import 'dart:ui';

import 'config.dart';

class UnitStats {
  final String name;
  final double hp, attack, meleeArmor, pierceArmor, range, reload, speed, los;
  final Map<UnitClass, double> bonus;
  final int carry;
  const UnitStats({
    required this.name,
    required this.hp,
    required this.attack,
    required this.meleeArmor,
    required this.pierceArmor,
    required this.range,
    required this.reload,
    required this.speed,
    required this.los,
    required this.bonus,
    required this.carry,
  });
}

class PlayerState {
  final int index;
  final String name;
  final Color color;
  final Map<Res, double> res = {
    Res.food: 200,
    Res.wood: 200,
    Res.gold: 100,
    Res.stone: 200,
  };
  Age age = Age.dark;
  final Set<Tech> techs = {};
  final Set<Tech> researching = {};
  int pop = 0;
  int popCap = 0;
  double gatherMultiplier = 1;

  // Stats
  int unitsTrained = 0;
  int unitsLost = 0;
  int kills = 0;
  int buildingsBuilt = 0;
  double totalGathered = 0;

  final Map<UnitType, UnitStats> _cache = {};

  PlayerState(this.index, this.name, this.color);

  bool has(Tech t) => techs.contains(t);

  bool canAfford(Cost c) =>
      res[Res.food]! >= c.food &&
      res[Res.wood]! >= c.wood &&
      res[Res.gold]! >= c.gold &&
      res[Res.stone]! >= c.stone;

  void pay(Cost c) {
    res[Res.food] = res[Res.food]! - c.food;
    res[Res.wood] = res[Res.wood]! - c.wood;
    res[Res.gold] = res[Res.gold]! - c.gold;
    res[Res.stone] = res[Res.stone]! - c.stone;
  }

  void refund(Cost c) {
    res[Res.food] = res[Res.food]! + c.food;
    res[Res.wood] = res[Res.wood]! + c.wood;
    res[Res.gold] = res[Res.gold]! + c.gold;
    res[Res.stone] = res[Res.stone]! + c.stone;
  }

  String missing(Cost c) {
    for (final r in Res.values) {
      if (res[r]! < c.of(r)) return resNames[r]!;
    }
    return '';
  }

  void completeTech(Tech t) {
    techs.add(t);
    researching.remove(t);
    final a = ageTechs[t];
    if (a != null) age = a;
    _cache.clear();
  }

  int unitLevel(UnitType t) {
    switch (t) {
      case UnitType.militia:
        return has(Tech.longSwordsman) ? 2 : (has(Tech.manAtArms) ? 1 : 0);
      case UnitType.spearman:
        return has(Tech.pikeman) ? 1 : 0;
      case UnitType.archer:
        return has(Tech.crossbowman) ? 1 : 0;
      case UnitType.skirmisher:
        return has(Tech.eliteSkirmisher) ? 1 : 0;
      case UnitType.scout:
        return has(Tech.lightCavalry) ? 1 : 0;
      case UnitType.knight:
        return has(Tech.cavalier) ? 1 : 0;
      case UnitType.villager:
        return 0;
    }
  }

  String unitName(UnitType t) {
    final names = unitLineNames[t];
    if (names == null) return unitDefs[t]!.name;
    return names[unitLevel(t).clamp(0, names.length - 1)];
  }

  UnitStats stats(UnitType t) => _cache.putIfAbsent(t, () => _compute(t));

  UnitStats _compute(UnitType t) {
    final d = unitDefs[t]!;
    double hp = d.hp, atk = d.attack, ma = d.meleeArmor, pa = d.pierceArmor;
    double range = d.range, reload = d.reload, speed = d.speed, los = d.los;
    final bonus = Map<UnitClass, double>.from(d.bonus);
    int carry = 10;

    switch (d.cls) {
      case UnitClass.villager:
        if (has(Tech.loom)) {
          hp += 15;
          ma += 1;
          pa += 2;
        }
        if (has(Tech.wheelbarrow)) {
          carry += 5;
          speed *= 1.1;
        }
        if (has(Tech.handCart)) {
          carry += 10;
          speed *= 1.1;
        }
        if (has(Tech.heavyPlow)) carry += 1;
      case UnitClass.infantry:
        if (has(Tech.forging)) atk += 1;
        if (has(Tech.ironCasting)) atk += 1;
        if (has(Tech.scaleMail)) {
          ma += 1;
          pa += 1;
        }
      case UnitClass.cavalry:
        if (has(Tech.forging)) atk += 1;
        if (has(Tech.ironCasting)) atk += 1;
        if (has(Tech.scaleBarding)) {
          ma += 1;
          pa += 1;
        }
        if (has(Tech.bloodlines)) hp += 20;
        if (has(Tech.husbandry)) speed *= 1.1;
      case UnitClass.archer:
        if (has(Tech.fletching)) {
          atk += 1;
          range += 1;
          los += 1;
        }
        if (has(Tech.bodkinArrow)) {
          atk += 1;
          range += 1;
          los += 1;
        }
        if (has(Tech.paddedArcher)) {
          ma += 1;
          pa += 1;
        }
        if (has(Tech.thumbRing)) reload *= 0.8;
    }

    final lvl = unitLevel(t);
    switch (t) {
      case UnitType.militia:
        if (lvl >= 1) {
          hp += 10;
          atk += 2;
        }
        if (lvl >= 2) {
          hp += 15;
          atk += 3;
        }
      case UnitType.spearman:
        if (lvl >= 1) {
          hp += 10;
          atk += 1;
          bonus[UnitClass.cavalry] = (bonus[UnitClass.cavalry] ?? 0) + 10;
        }
      case UnitType.archer:
      case UnitType.skirmisher:
        if (lvl >= 1) {
          hp += 5;
          atk += 1;
          range += 1;
        }
      case UnitType.scout:
        if (lvl >= 1) {
          hp += 15;
          atk += 3;
        }
      case UnitType.knight:
        if (lvl >= 1) {
          hp += 20;
          atk += 2;
        }
      case UnitType.villager:
        break;
    }

    return UnitStats(
      name: unitName(t),
      hp: hp,
      attack: atk,
      meleeArmor: ma,
      pierceArmor: pa,
      range: range,
      reload: reload,
      speed: speed,
      los: los,
      bonus: bonus,
      carry: carry,
    );
  }

  double gatherRate(ResourceKind? kind, {bool farm = false}) {
    double r;
    if (farm) {
      r = farmGatherRate;
      if (has(Tech.heavyPlow)) r *= 1.2;
    } else {
      r = gatherRates[kind]!;
      switch (kind!) {
        case ResourceKind.tree:
          if (has(Tech.doubleBitAxe)) r *= 1.2;
          if (has(Tech.bowSaw)) r *= 1.2;
          if (has(Tech.twoManSaw)) r *= 1.1;
        case ResourceKind.gold:
          if (has(Tech.goldMining)) r *= 1.15;
          if (has(Tech.goldShaftMining)) r *= 1.15;
        case ResourceKind.stone:
          if (has(Tech.stoneMining)) r *= 1.15;
        case ResourceKind.berries:
          break;
      }
    }
    return r * gatherMultiplier;
  }

  double get farmFood {
    double f = farmBaseFood;
    if (has(Tech.horseCollar)) f += 75;
    if (has(Tech.heavyPlow)) f += 125;
    return f;
  }

  double buildingAttack(double base) {
    double a = base;
    if (has(Tech.fletching)) a += 1;
    if (has(Tech.bodkinArrow)) a += 1;
    return a;
  }

  double buildingRange(double base) {
    double r = base;
    if (has(Tech.fletching)) r += 1;
    if (has(Tech.bodkinArrow)) r += 1;
    return r;
  }
}
