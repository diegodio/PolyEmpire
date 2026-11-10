// Static game data: resources, ages, units, buildings and technologies.
// Values are inspired by Age of Empires II and tuned for a smaller map.

enum Res { food, wood, gold, stone }

const resNames = {
  Res.food: 'Comida',
  Res.wood: 'Madeira',
  Res.gold: 'Ouro',
  Res.stone: 'Pedra',
};

class Cost {
  final int food, wood, gold, stone;
  const Cost({this.food = 0, this.wood = 0, this.gold = 0, this.stone = 0});

  int of(Res r) => switch (r) {
        Res.food => food,
        Res.wood => wood,
        Res.gold => gold,
        Res.stone => stone,
      };

  bool get isFree => food == 0 && wood == 0 && gold == 0 && stone == 0;

  @override
  String toString() {
    final parts = <String>[];
    if (food > 0) parts.add('$food C');
    if (wood > 0) parts.add('$wood M');
    if (gold > 0) parts.add('$gold O');
    if (stone > 0) parts.add('$stone P');
    return parts.isEmpty ? 'Grátis' : parts.join(' · ');
  }
}

enum Age { dark, feudal, castle, imperial }

const ageNames = {
  Age.dark: 'Idade das Trevas',
  Age.feudal: 'Idade Feudal',
  Age.castle: 'Idade dos Castelos',
  Age.imperial: 'Idade Imperial',
};

enum UnitClass { villager, infantry, archer, cavalry }

enum UnitType { villager, militia, spearman, archer, skirmisher, scout, knight }

class UnitDef {
  final String name;
  final Cost cost;
  final double trainTime;
  final double hp;
  final double attack;
  final double meleeArmor;
  final double pierceArmor;
  final double range; // tiles; 0 => melee
  final double reload; // seconds between attacks
  final double speed; // tiles / second
  final double los; // tiles
  final Age minAge;
  final UnitClass cls;
  final Map<UnitClass, double> bonus;
  final bool ranged;

  const UnitDef({
    required this.name,
    required this.cost,
    required this.trainTime,
    required this.hp,
    required this.attack,
    this.meleeArmor = 0,
    this.pierceArmor = 0,
    this.range = 0,
    this.reload = 2,
    required this.speed,
    this.los = 4,
    this.minAge = Age.dark,
    required this.cls,
    this.bonus = const {},
    this.ranged = false,
  });
}

const unitDefs = <UnitType, UnitDef>{
  UnitType.villager: UnitDef(
    name: 'Aldeão',
    cost: Cost(food: 50),
    trainTime: 18,
    hp: 25,
    attack: 3,
    speed: 0.9,
    los: 4,
    cls: UnitClass.villager,
  ),
  UnitType.militia: UnitDef(
    name: 'Milícia',
    cost: Cost(food: 60, gold: 20),
    trainTime: 15,
    hp: 40,
    attack: 4,
    pierceArmor: 1,
    speed: 0.95,
    los: 4,
    cls: UnitClass.infantry,
    bonus: {UnitClass.villager: 1},
  ),
  UnitType.spearman: UnitDef(
    name: 'Lanceiro',
    cost: Cost(food: 35, wood: 25),
    trainTime: 15,
    hp: 45,
    attack: 3,
    reload: 3,
    speed: 1.0,
    los: 4,
    cls: UnitClass.infantry,
    bonus: {UnitClass.cavalry: 15},
  ),
  UnitType.archer: UnitDef(
    name: 'Arqueiro',
    cost: Cost(wood: 25, gold: 45),
    trainTime: 20,
    hp: 30,
    attack: 4,
    range: 4,
    speed: 0.96,
    los: 6,
    minAge: Age.feudal,
    cls: UnitClass.archer,
    ranged: true,
    bonus: {UnitClass.infantry: 1},
  ),
  UnitType.skirmisher: UnitDef(
    name: 'Escaramuçador',
    cost: Cost(food: 25, wood: 35),
    trainTime: 18,
    hp: 30,
    attack: 2,
    pierceArmor: 3,
    range: 4,
    reload: 3,
    speed: 0.96,
    los: 6,
    minAge: Age.feudal,
    cls: UnitClass.archer,
    ranged: true,
    bonus: {UnitClass.archer: 3},
  ),
  UnitType.scout: UnitDef(
    name: 'Batedor',
    cost: Cost(food: 80),
    trainTime: 18,
    hp: 45,
    attack: 3,
    pierceArmor: 2,
    speed: 1.55,
    los: 6,
    minAge: Age.feudal,
    cls: UnitClass.cavalry,
  ),
  UnitType.knight: UnitDef(
    name: 'Cavaleiro',
    cost: Cost(food: 60, gold: 75),
    trainTime: 20,
    hp: 100,
    attack: 10,
    meleeArmor: 2,
    pierceArmor: 2,
    reload: 1.8,
    speed: 1.35,
    los: 5,
    minAge: Age.castle,
    cls: UnitClass.cavalry,
  ),
};

/// Names of unit upgrade lines: level 0, 1, 2.
const unitLineNames = <UnitType, List<String>>{
  UnitType.militia: ['Milícia', 'Homem de Armas', 'Espadachim Longo'],
  UnitType.spearman: ['Lanceiro', 'Piqueiro'],
  UnitType.archer: ['Arqueiro', 'Besteiro'],
  UnitType.skirmisher: ['Escaramuçador', 'Escaramuçador de Elite'],
  UnitType.scout: ['Batedor', 'Cavalaria Leve'],
  UnitType.knight: ['Cavaleiro', 'Cavaleiro Nobre'],
};

enum BuildingType {
  townCenter,
  house,
  mill,
  lumberCamp,
  miningCamp,
  farm,
  barracks,
  archeryRange,
  stable,
  blacksmith,
  market,
  tower,
  castle,
}

class BuildingDef {
  final String name;
  final Cost cost;
  final double buildTime;
  final double hp;
  final int size;
  final int pop;
  final Age minAge;
  final Set<Res> dropOff;
  final List<UnitType> trains;
  final double attack; // pierce arrows
  final double range;
  final double los;
  final List<BuildingType> requires; // any one of these must exist
  final bool walkable;

  const BuildingDef({
    required this.name,
    required this.cost,
    required this.buildTime,
    required this.hp,
    required this.size,
    this.pop = 0,
    this.minAge = Age.dark,
    this.dropOff = const {},
    this.trains = const [],
    this.attack = 0,
    this.range = 0,
    this.los = 4,
    this.requires = const [],
    this.walkable = false,
  });
}

const buildingDefs = <BuildingType, BuildingDef>{
  BuildingType.townCenter: BuildingDef(
    name: 'Centro da Cidade',
    cost: Cost(wood: 275, stone: 100),
    buildTime: 120,
    hp: 2400,
    size: 3,
    pop: 5,
    minAge: Age.castle,
    dropOff: {Res.food, Res.wood, Res.gold, Res.stone},
    trains: [UnitType.villager],
    attack: 5,
    range: 6,
    los: 8,
  ),
  BuildingType.house: BuildingDef(
    name: 'Casa',
    cost: Cost(wood: 25),
    buildTime: 18,
    hp: 550,
    size: 2,
    pop: 5,
    los: 2,
  ),
  BuildingType.mill: BuildingDef(
    name: 'Moinho',
    cost: Cost(wood: 100),
    buildTime: 25,
    hp: 600,
    size: 2,
    dropOff: {Res.food},
  ),
  BuildingType.lumberCamp: BuildingDef(
    name: 'Campo de Lenhador',
    cost: Cost(wood: 100),
    buildTime: 25,
    hp: 600,
    size: 2,
    dropOff: {Res.wood},
  ),
  BuildingType.miningCamp: BuildingDef(
    name: 'Campo de Mineração',
    cost: Cost(wood: 100),
    buildTime: 25,
    hp: 600,
    size: 2,
    dropOff: {Res.gold, Res.stone},
  ),
  BuildingType.farm: BuildingDef(
    name: 'Fazenda',
    cost: Cost(wood: 60),
    buildTime: 12,
    hp: 480,
    size: 2,
    los: 1,
    requires: [BuildingType.mill, BuildingType.townCenter],
    walkable: true,
  ),
  BuildingType.barracks: BuildingDef(
    name: 'Quartel',
    cost: Cost(wood: 175),
    buildTime: 35,
    hp: 1200,
    size: 3,
    trains: [UnitType.militia, UnitType.spearman],
  ),
  BuildingType.archeryRange: BuildingDef(
    name: 'Campo de Arqueiros',
    cost: Cost(wood: 175),
    buildTime: 35,
    hp: 1200,
    size: 3,
    minAge: Age.feudal,
    trains: [UnitType.archer, UnitType.skirmisher],
    requires: [BuildingType.barracks],
  ),
  BuildingType.stable: BuildingDef(
    name: 'Estábulo',
    cost: Cost(wood: 175),
    buildTime: 35,
    hp: 1200,
    size: 3,
    minAge: Age.feudal,
    trains: [UnitType.scout, UnitType.knight],
    requires: [BuildingType.barracks],
  ),
  BuildingType.blacksmith: BuildingDef(
    name: 'Ferraria',
    cost: Cost(wood: 150),
    buildTime: 30,
    hp: 1000,
    size: 2,
    minAge: Age.feudal,
  ),
  BuildingType.market: BuildingDef(
    name: 'Mercado',
    cost: Cost(wood: 175),
    buildTime: 35,
    hp: 1200,
    size: 3,
    minAge: Age.feudal,
    requires: [BuildingType.mill],
  ),
  BuildingType.tower: BuildingDef(
    name: 'Torre de Vigia',
    cost: Cost(wood: 25, stone: 125),
    buildTime: 45,
    hp: 1020,
    size: 1,
    minAge: Age.feudal,
    attack: 5,
    range: 7,
    los: 9,
  ),
  BuildingType.castle: BuildingDef(
    name: 'Castelo',
    cost: Cost(stone: 650),
    buildTime: 120,
    hp: 4800,
    size: 4,
    pop: 20,
    minAge: Age.castle,
    attack: 11,
    range: 8,
    los: 10,
  ),
};

/// Buildings villagers can construct, in menu order.
const economyBuildings = [
  BuildingType.house,
  BuildingType.mill,
  BuildingType.lumberCamp,
  BuildingType.miningCamp,
  BuildingType.farm,
  BuildingType.market,
  BuildingType.townCenter,
];

const militaryBuildings = [
  BuildingType.barracks,
  BuildingType.archeryRange,
  BuildingType.stable,
  BuildingType.blacksmith,
  BuildingType.tower,
  BuildingType.castle,
];

enum Tech {
  feudalAge,
  castleAge,
  imperialAge,
  loom,
  wheelbarrow,
  handCart,
  doubleBitAxe,
  bowSaw,
  twoManSaw,
  goldMining,
  goldShaftMining,
  stoneMining,
  horseCollar,
  heavyPlow,
  forging,
  ironCasting,
  fletching,
  bodkinArrow,
  scaleMail,
  scaleBarding,
  paddedArcher,
  manAtArms,
  longSwordsman,
  pikeman,
  crossbowman,
  eliteSkirmisher,
  lightCavalry,
  cavalier,
  bloodlines,
  husbandry,
  thumbRing,
}

class TechDef {
  final String name;
  final String desc;
  final Cost cost;
  final double time;
  final BuildingType at;
  final Age minAge;
  final Tech? requires;

  const TechDef({
    required this.name,
    required this.desc,
    required this.cost,
    required this.time,
    required this.at,
    this.minAge = Age.dark,
    this.requires,
  });
}

const techDefs = <Tech, TechDef>{
  Tech.feudalAge: TechDef(
    name: 'Idade Feudal',
    desc: 'Avança para a Idade Feudal. Requer 2 prédios da Idade das Trevas.',
    cost: Cost(food: 500),
    time: 80,
    at: BuildingType.townCenter,
  ),
  Tech.castleAge: TechDef(
    name: 'Idade dos Castelos',
    desc: 'Avança para a Idade dos Castelos. Requer 2 prédios Feudais.',
    cost: Cost(food: 800, gold: 200),
    time: 100,
    at: BuildingType.townCenter,
    minAge: Age.feudal,
  ),
  Tech.imperialAge: TechDef(
    name: 'Idade Imperial',
    desc: 'Avança para a Idade Imperial.',
    cost: Cost(food: 1000, gold: 800),
    time: 120,
    at: BuildingType.townCenter,
    minAge: Age.castle,
  ),
  Tech.loom: TechDef(
    name: 'Tear',
    desc: 'Aldeões +15 PV, +1/+2 armadura.',
    cost: Cost(gold: 50),
    time: 20,
    at: BuildingType.townCenter,
  ),
  Tech.wheelbarrow: TechDef(
    name: 'Carrinho de Mão',
    desc: 'Aldeões carregam +5 e andam 10% mais rápido.',
    cost: Cost(food: 175, wood: 50),
    time: 40,
    at: BuildingType.townCenter,
    minAge: Age.feudal,
  ),
  Tech.handCart: TechDef(
    name: 'Carroça de Mão',
    desc: 'Aldeões carregam +10 e andam 10% mais rápido.',
    cost: Cost(food: 300, wood: 200),
    time: 50,
    at: BuildingType.townCenter,
    minAge: Age.castle,
    requires: Tech.wheelbarrow,
  ),
  Tech.doubleBitAxe: TechDef(
    name: 'Machado de Duas Lâminas',
    desc: 'Lenhadores +20% de coleta.',
    cost: Cost(food: 100, wood: 50),
    time: 20,
    at: BuildingType.lumberCamp,
    minAge: Age.feudal,
  ),
  Tech.bowSaw: TechDef(
    name: 'Serra de Arco',
    desc: 'Lenhadores +20% de coleta.',
    cost: Cost(food: 150, wood: 100),
    time: 30,
    at: BuildingType.lumberCamp,
    minAge: Age.castle,
    requires: Tech.doubleBitAxe,
  ),
  Tech.twoManSaw: TechDef(
    name: 'Serra de Dois Homens',
    desc: 'Lenhadores +10% de coleta.',
    cost: Cost(food: 300, wood: 200),
    time: 40,
    at: BuildingType.lumberCamp,
    minAge: Age.imperial,
    requires: Tech.bowSaw,
  ),
  Tech.goldMining: TechDef(
    name: 'Mineração de Ouro',
    desc: 'Mineradores de ouro +15%.',
    cost: Cost(food: 100, wood: 75),
    time: 25,
    at: BuildingType.miningCamp,
    minAge: Age.feudal,
  ),
  Tech.goldShaftMining: TechDef(
    name: 'Mina de Ouro Profunda',
    desc: 'Mineradores de ouro +15%.',
    cost: Cost(food: 200, wood: 150),
    time: 35,
    at: BuildingType.miningCamp,
    minAge: Age.castle,
    requires: Tech.goldMining,
  ),
  Tech.stoneMining: TechDef(
    name: 'Mineração de Pedra',
    desc: 'Mineradores de pedra +15%.',
    cost: Cost(food: 100, wood: 75),
    time: 25,
    at: BuildingType.miningCamp,
    minAge: Age.feudal,
  ),
  Tech.horseCollar: TechDef(
    name: 'Coleira de Cavalo',
    desc: 'Fazendas +75 de comida.',
    cost: Cost(food: 75, wood: 75),
    time: 20,
    at: BuildingType.mill,
    minAge: Age.feudal,
  ),
  Tech.heavyPlow: TechDef(
    name: 'Arado Pesado',
    desc: 'Fazendas +125 de comida e fazendeiros +20% de coleta.',
    cost: Cost(food: 125, wood: 125),
    time: 30,
    at: BuildingType.mill,
    minAge: Age.castle,
    requires: Tech.horseCollar,
  ),
  Tech.forging: TechDef(
    name: 'Forja',
    desc: 'Infantaria e cavalaria +1 de ataque.',
    cost: Cost(food: 150),
    time: 30,
    at: BuildingType.blacksmith,
    minAge: Age.feudal,
  ),
  Tech.ironCasting: TechDef(
    name: 'Fundição de Ferro',
    desc: 'Infantaria e cavalaria +1 de ataque.',
    cost: Cost(food: 220, gold: 120),
    time: 40,
    at: BuildingType.blacksmith,
    minAge: Age.castle,
    requires: Tech.forging,
  ),
  Tech.fletching: TechDef(
    name: 'Emplumação',
    desc: 'Arqueiros, torres e CC +1 ataque e +1 alcance.',
    cost: Cost(food: 100, gold: 50),
    time: 30,
    at: BuildingType.blacksmith,
    minAge: Age.feudal,
  ),
  Tech.bodkinArrow: TechDef(
    name: 'Flecha Perfurante',
    desc: 'Arqueiros, torres e CC +1 ataque e +1 alcance.',
    cost: Cost(food: 200, gold: 100),
    time: 40,
    at: BuildingType.blacksmith,
    minAge: Age.castle,
    requires: Tech.fletching,
  ),
  Tech.scaleMail: TechDef(
    name: 'Cota de Escamas',
    desc: 'Infantaria +1/+1 de armadura.',
    cost: Cost(food: 100),
    time: 30,
    at: BuildingType.blacksmith,
    minAge: Age.feudal,
  ),
  Tech.scaleBarding: TechDef(
    name: 'Barda de Escamas',
    desc: 'Cavalaria +1/+1 de armadura.',
    cost: Cost(food: 150),
    time: 30,
    at: BuildingType.blacksmith,
    minAge: Age.feudal,
  ),
  Tech.paddedArcher: TechDef(
    name: 'Armadura Acolchoada',
    desc: 'Arqueiros +1/+1 de armadura.',
    cost: Cost(food: 100),
    time: 30,
    at: BuildingType.blacksmith,
    minAge: Age.feudal,
  ),
  Tech.manAtArms: TechDef(
    name: 'Homem de Armas',
    desc: 'Melhora a Milícia: +10 PV, +2 ataque.',
    cost: Cost(food: 100, gold: 40),
    time: 30,
    at: BuildingType.barracks,
    minAge: Age.feudal,
  ),
  Tech.longSwordsman: TechDef(
    name: 'Espadachim Longo',
    desc: 'Melhora: +15 PV, +3 ataque.',
    cost: Cost(food: 200, gold: 65),
    time: 40,
    at: BuildingType.barracks,
    minAge: Age.castle,
    requires: Tech.manAtArms,
  ),
  Tech.pikeman: TechDef(
    name: 'Piqueiro',
    desc: 'Melhora Lanceiros: +10 PV, +1 ataque, +10 vs cavalaria.',
    cost: Cost(food: 215, gold: 90),
    time: 40,
    at: BuildingType.barracks,
    minAge: Age.castle,
  ),
  Tech.crossbowman: TechDef(
    name: 'Besteiro',
    desc: 'Melhora Arqueiros: +5 PV, +1 ataque, +1 alcance.',
    cost: Cost(food: 125, gold: 75),
    time: 35,
    at: BuildingType.archeryRange,
    minAge: Age.castle,
  ),
  Tech.eliteSkirmisher: TechDef(
    name: 'Escaramuçador de Elite',
    desc: 'Melhora Escaramuçadores: +5 PV, +1 ataque, +1 alcance.',
    cost: Cost(wood: 200, gold: 100),
    time: 35,
    at: BuildingType.archeryRange,
    minAge: Age.castle,
  ),
  Tech.thumbRing: TechDef(
    name: 'Anel de Polegar',
    desc: 'Arqueiros atiram 20% mais rápido.',
    cost: Cost(food: 300, wood: 250),
    time: 40,
    at: BuildingType.archeryRange,
    minAge: Age.castle,
  ),
  Tech.lightCavalry: TechDef(
    name: 'Cavalaria Leve',
    desc: 'Melhora Batedores: +15 PV, +3 ataque.',
    cost: Cost(food: 150, gold: 50),
    time: 35,
    at: BuildingType.stable,
    minAge: Age.castle,
  ),
  Tech.cavalier: TechDef(
    name: 'Cavaleiro Nobre',
    desc: 'Melhora Cavaleiros: +20 PV, +2 ataque.',
    cost: Cost(food: 300, gold: 300),
    time: 50,
    at: BuildingType.stable,
    minAge: Age.imperial,
  ),
  Tech.bloodlines: TechDef(
    name: 'Linhagem',
    desc: 'Cavalaria +20 PV.',
    cost: Cost(food: 150, gold: 100),
    time: 35,
    at: BuildingType.stable,
    minAge: Age.feudal,
  ),
  Tech.husbandry: TechDef(
    name: 'Criação de Animais',
    desc: 'Cavalaria 10% mais rápida.',
    cost: Cost(food: 150),
    time: 30,
    at: BuildingType.stable,
    minAge: Age.castle,
  ),
};

const ageTechs = {
  Tech.feudalAge: Age.feudal,
  Tech.castleAge: Age.castle,
  Tech.imperialAge: Age.imperial,
};

/// Buildings that count toward the requirement to advance to the next age.
const ageRequirementBuildings = <Tech, List<BuildingType>>{
  Tech.feudalAge: [
    BuildingType.barracks,
    BuildingType.mill,
    BuildingType.lumberCamp,
    BuildingType.miningCamp,
  ],
  Tech.castleAge: [
    BuildingType.archeryRange,
    BuildingType.stable,
    BuildingType.blacksmith,
    BuildingType.market,
  ],
  Tech.imperialAge: [],
};

enum ResourceKind { tree, gold, stone, berries }

const resourceKindRes = {
  ResourceKind.tree: Res.wood,
  ResourceKind.gold: Res.gold,
  ResourceKind.stone: Res.stone,
  ResourceKind.berries: Res.food,
};

const resourceKindAmount = {
  ResourceKind.tree: 100.0,
  ResourceKind.gold: 800.0,
  ResourceKind.stone: 350.0,
  ResourceKind.berries: 125.0,
};

const resourceKindNames = {
  ResourceKind.tree: 'Árvore',
  ResourceKind.gold: 'Mina de Ouro',
  ResourceKind.stone: 'Mina de Pedra',
  ResourceKind.berries: 'Arbusto de Frutas',
};

/// Base gather rates (resource per second).
const gatherRates = {
  ResourceKind.tree: 0.42,
  ResourceKind.gold: 0.40,
  ResourceKind.stone: 0.38,
  ResourceKind.berries: 0.34,
};
const farmGatherRate = 0.36;
const farmBaseFood = 175.0;

enum Difficulty { easy, normal, hard }

const difficultyNames = {
  Difficulty.easy: 'Fácil',
  Difficulty.normal: 'Normal',
  Difficulty.hard: 'Difícil',
};
