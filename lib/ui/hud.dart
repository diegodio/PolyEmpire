import 'package:flutter/material.dart';

import '../game/config.dart';
import '../game/entities.dart';
import '../game/poly_empire_game.dart';
import '../game/world.dart';
import 'minimap.dart';

const panelColor = Color(0xE6151A23);
const borderColor = Color(0xFF3A4556);
const accent = Color(0xFFE8C26A);

const resColors = {
  Res.food: Color(0xFFE05A4E),
  Res.wood: Color(0xFFB07A44),
  Res.gold: Color(0xFFF2C440),
  Res.stone: Color(0xFFA8AEB5),
};

const resIcons = {
  Res.food: Icons.restaurant,
  Res.wood: Icons.park,
  Res.gold: Icons.toll,
  Res.stone: Icons.landscape,
};

const buildingIcons = {
  BuildingType.townCenter: Icons.account_balance,
  BuildingType.house: Icons.house,
  BuildingType.mill: Icons.wind_power,
  BuildingType.lumberCamp: Icons.forest,
  BuildingType.miningCamp: Icons.diamond,
  BuildingType.farm: Icons.grass,
  BuildingType.barracks: Icons.shield,
  BuildingType.archeryRange: Icons.gps_fixed,
  BuildingType.stable: Icons.pets,
  BuildingType.blacksmith: Icons.hardware,
  BuildingType.market: Icons.storefront,
  BuildingType.tower: Icons.cell_tower,
  BuildingType.castle: Icons.castle,
};

const unitIcons = {
  UnitType.villager: Icons.person,
  UnitType.militia: Icons.shield_outlined,
  UnitType.spearman: Icons.north_east,
  UnitType.archer: Icons.my_location,
  UnitType.skirmisher: Icons.near_me,
  UnitType.scout: Icons.directions_run,
  UnitType.knight: Icons.military_tech,
};

IconData techIcon(Tech t) {
  if (ageTechs.containsKey(t)) return Icons.trending_up;
  final at = techDefs[t]!.at;
  return switch (at) {
    BuildingType.blacksmith => Icons.construction,
    BuildingType.barracks ||
    BuildingType.archeryRange ||
    BuildingType.stable =>
      Icons.upgrade,
    _ => Icons.science,
  };
}

class Hud extends StatefulWidget {
  final PolyEmpireGame game;
  const Hud({super.key, required this.game});

  @override
  State<Hud> createState() => _HudState();
}

class _HudState extends State<Hud> {
  bool militaryTab = false;

  PolyEmpireGame get game => widget.game;
  GameWorld get w => game.sim!;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final narrow = size.width < 760;
    return Stack(
      children: [
        Positioned(
            top: 0, left: 0, right: 0, child: SafeArea(child: _topBar(narrow))),
        Positioned(
          top: narrow ? 96 : 60,
          left: 0,
          right: 0,
          child: IgnorePointer(child: _messages()),
        ),
        Positioned(
          right: 8,
          top: narrow ? 96 : 64,
          child: SafeArea(child: _sideTools()),
        ),
        Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(child: _bottom(narrow))),
        if (game.simPaused && w.winner == null) _pauseOverlay(),
        if (w.winner != null) _gameOver(),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Top bar
  // ---------------------------------------------------------------------------

  Widget _topBar(bool narrow) {
    final p = w.players[GameWorld.human];
    final chips = <Widget>[
      for (final r in Res.values)
        _chip(resIcons[r]!, resColors[r]!, p.res[r]!.floor().toString(),
            tooltip: resNames[r]!),
      _chip(Icons.groups, Colors.white, '${p.pop}/${p.popCap}',
          tooltip: 'População', warn: p.pop >= p.popCap),
    ];
    final right = <Widget>[
      _pill(ageNames[p.age]!, accent),
      _pill(_fmtTime(w.time), Colors.white70),
      _iconBtn(Icons.speed, '${game.speed.toStringAsFixed(0)}x', () {
        game.speed = game.speed >= 3 ? 1 : game.speed + 1;
        setState(() {});
      }),
      _iconBtn(game.simPaused ? Icons.play_arrow : Icons.pause, null, () {
        game.simPaused = !game.simPaused;
        setState(() {});
      }),
      _iconBtn(Icons.menu, null, _showMenu),
    ];
    return Container(
      margin: const EdgeInsets.all(6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: panelColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: narrow
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(spacing: 6, runSpacing: 4, children: chips),
                const SizedBox(height: 4),
                Wrap(spacing: 6, runSpacing: 4, children: right),
              ],
            )
          : Row(
              children: [
                ...chips.map((c) => Padding(
                    padding: const EdgeInsets.only(right: 8), child: c)),
                const Spacer(),
                ...right.map((c) =>
                    Padding(padding: const EdgeInsets.only(left: 6), child: c)),
              ],
            ),
    );
  }

  String _fmtTime(double t) {
    final m = (t ~/ 60).toString().padLeft(2, '0');
    final s = (t.floor() % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Widget _chip(IconData icon, Color color, String text,
      {String? tooltip, bool warn = false}) {
    final c = Row(mainAxisSize: MainAxisSize.min, children: [
      _gem(icon, color),
      const SizedBox(width: 5),
      Text(text,
          style: TextStyle(
              color: warn ? Colors.redAccent : Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 14,
              fontFeatures: const [FontFeature.tabularFigures()])),
    ]);
    return tooltip == null ? c : Tooltip(message: tooltip, child: c);
  }

  Widget _gem(IconData icon, Color color, {double size = 22}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(color, Colors.white, 0.25)!,
            Color.lerp(color, Colors.black, 0.35)!
          ],
        ),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Icon(icon, size: size * 0.68, color: Colors.white),
    );
  }

  Widget _pill(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.6)),
        ),
        child: Text(text,
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      );

  Widget _iconBtn(IconData icon, String? label, VoidCallback onTap,
      {Color? color, String? tooltip}) {
    final btn = Material(
      color: const Color(0xFF232B38),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 18, color: color ?? Colors.white),
            if (label != null) ...[
              const SizedBox(width: 4),
              Text(label,
                  style: const TextStyle(color: Colors.white, fontSize: 12)),
            ],
          ]),
        ),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip, child: btn);
  }

  void _showMenu() {
    final wasPaused = game.simPaused;
    game.simPaused = true;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1B212C),
        title: const Text('Menu'),
        content:
            const Text(_helpText, style: TextStyle(fontSize: 13, height: 1.4)),
        actions: [
          TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                game.quitToMenu();
              },
              child: const Text('Sair para o menu')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Continuar')),
        ],
      ),
    ).then((_) {
      game.simPaused = wasPaused;
      if (mounted) setState(() {});
    });
  }

  // ---------------------------------------------------------------------------
  // Messages & side tools
  // ---------------------------------------------------------------------------

  Widget _messages() {
    final recent = w.messages.where((m) => w.time - m.time < 6).toList();
    final shown =
        recent.length > 4 ? recent.sublist(recent.length - 4) : recent;
    return Column(
      children: [
        for (final m in shown)
          Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color:
                  m.alert ? const Color(0xDD5A1A1A) : const Color(0xCC10141B),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(m.text,
                style: TextStyle(
                    color: m.alert ? const Color(0xFFFFB0A0) : Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ),
      ],
    );
  }

  Widget _sideTools() {
    final idle = game.idleVillagers;
    Widget tool(IconData i, String tip, VoidCallback f,
        {bool active = false, String? badge}) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Tooltip(
          message: tip,
          child: Material(
            color: active ? const Color(0xFF3B6A3F) : panelColor,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: const BorderSide(color: borderColor)),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () {
                f();
                setState(() {});
              },
              child: SizedBox(
                width: 42,
                height: 42,
                child: Stack(children: [
                  Center(child: Icon(i, color: Colors.white, size: 21)),
                  if (badge != null)
                    Positioned(
                      right: 2,
                      top: 2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                            color: Colors.redAccent,
                            borderRadius: BorderRadius.circular(8)),
                        child: Text(badge,
                            style: const TextStyle(
                                fontSize: 10, color: Colors.white)),
                      ),
                    ),
                ]),
              ),
            ),
          ),
        ),
      );
    }

    return Column(children: [
      tool(
          Icons.person_search, 'Aldeão ocioso (.)', game.selectNextIdleVillager,
          badge: idle > 0 ? '$idle' : null),
      tool(
          Icons.account_balance, 'Centro da Cidade (H)', game.selectTownCenter),
      tool(Icons.groups_2, 'Selecionar exército', game.selectArmy),
      tool(Icons.highlight_alt, 'Modo seleção em área (arrastar)',
          () => game.boxSelectMode = !game.boxSelectMode,
          active: game.boxSelectMode),
      tool(Icons.zoom_in, 'Aproximar',
          () => game.zoomAt(1.2, Offset(game.size.x / 2, game.size.y / 2))),
      tool(Icons.zoom_out, 'Afastar',
          () => game.zoomAt(1 / 1.2, Offset(game.size.x / 2, game.size.y / 2))),
    ]);
  }

  // ---------------------------------------------------------------------------
  // Bottom panel
  // ---------------------------------------------------------------------------

  Widget _bottom(bool narrow) {
    final mini = Minimap(game: game, width: narrow ? 150 : 200);
    final panel = Container(
      constraints: BoxConstraints(minHeight: narrow ? 0 : 112),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: panelColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: game.selection.isEmpty && game.placing == null
          ? const Padding(
              padding: EdgeInsets.all(6),
              child: Text(
                'Toque/clique em uma unidade ou prédio para selecionar.\n'
                'Arraste para mover a câmera · role/pinça para zoom.',
                style: TextStyle(color: Colors.white60, fontSize: 12),
              ),
            )
          : narrow
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [_info(), const SizedBox(height: 6), _actions()],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 250, child: _info()),
                    const VerticalDivider(color: borderColor, width: 16),
                    Expanded(child: _actions()),
                  ],
                ),
    );
    return Padding(
      padding: const EdgeInsets.all(6),
      child: narrow
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [mini, const SizedBox(height: 6), panel],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                mini,
                const SizedBox(width: 6),
                Expanded(child: panel)
              ],
            ),
    );
  }

  Widget _info() {
    if (game.placing != null) {
      final d = buildingDefs[game.placing]!;
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Construir: ${d.name}', style: _titleStyle),
        const SizedBox(height: 4),
        Text('Custo: ${d.cost}', style: _bodyStyle),
        const Text(
            'Toque no mapa para posicionar (no celular toque 2x no mesmo local). '
            'Botão direito/ESC cancela.',
            style: TextStyle(color: Colors.white60, fontSize: 11)),
      ]);
    }
    final sel = game.selection;
    if (sel.length > 1) {
      final counts = <UnitType, int>{};
      for (final e in sel.whereType<Unit>()) {
        counts[e.type] = (counts[e.type] ?? 0) + 1;
      }
      final p = w.players[GameWorld.human];
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${sel.length} unidades', style: _titleStyle),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final e in counts.entries)
            Tooltip(
              message: 'Selecionar só ${p.unitName(e.key)}',
              child: InkWell(
                onTap: () {
                  game.selection
                      .removeWhere((s) => s is! Unit || s.type != e.key);
                  setState(() {});
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                      color: const Color(0xFF232B38),
                      borderRadius: BorderRadius.circular(6)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(unitIcons[e.key], size: 16, color: Colors.white),
                    const SizedBox(width: 3),
                    Text('${e.value}',
                        style:
                            const TextStyle(color: Colors.white, fontSize: 12)),
                  ]),
                ),
              ),
            ),
        ]),
      ]);
    }
    final e = sel.first;
    final owner = e.owner < 0 ? 'Natureza' : w.players[e.owner].name;
    if (e is Unit) {
      final st = w.players[e.owner].stats(e.type);
      final task = switch (e.task) {
        Task.idle => 'Ocioso',
        Task.move => 'Movendo',
        Task.attackMove => 'Avançando',
        Task.gather => 'Coletando',
        Task.returnRes => 'Levando recursos',
        Task.build => 'Construindo',
        Task.attack => 'Atacando',
      };
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _gem(unitIcons[e.type]!, w.players[e.owner].color, size: 28),
          const SizedBox(width: 8),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(st.name, style: _titleStyle),
              Text('$owner · $task',
                  style: const TextStyle(color: Colors.white60, fontSize: 11)),
            ]),
          ),
        ]),
        const SizedBox(height: 6),
        _hpBar(e.hp, e.maxHp),
        const SizedBox(height: 4),
        Text(
            'Ataque ${st.attack.toStringAsFixed(0)}  ·  Armadura ${st.meleeArmor.toStringAsFixed(0)}/${st.pierceArmor.toStringAsFixed(0)}'
            '${st.range > 0 ? '  ·  Alcance ${st.range.toStringAsFixed(0)}' : ''}',
            style: _bodyStyle),
        if (e.isVillager && e.carry > 0)
          Text('Carregando ${e.carry.floor()} ${resNames[e.carryType]}',
              style: _bodyStyle),
      ]);
    }
    if (e is Building) {
      final p = e.owner >= 0 ? w.players[e.owner] : null;
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _gem(buildingIcons[e.type]!, p?.color ?? Colors.grey, size: 28),
          const SizedBox(width: 8),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.def.name, style: _titleStyle),
              Text(owner,
                  style: const TextStyle(color: Colors.white60, fontSize: 11)),
            ]),
          ),
        ]),
        const SizedBox(height: 6),
        _hpBar(e.hp, e.maxHp),
        const SizedBox(height: 4),
        if (!e.complete)
          Text('Construção: ${(e.progress * 100).floor()}%', style: _bodyStyle)
        else if (e.type == BuildingType.farm)
          Text('Comida restante: ${e.food.floor()}', style: _bodyStyle)
        else if (e.def.pop > 0)
          Text('Fornece +${e.def.pop} de população', style: _bodyStyle),
        if (e.def.dropOff.isNotEmpty && e.complete)
          Text('Depósito: ${e.def.dropOff.map((r) => resNames[r]).join(', ')}',
              style: const TextStyle(color: Colors.white60, fontSize: 11)),
      ]);
    }
    if (e is ResourceNode) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _gem(resIcons[e.res]!, resColors[e.res]!, size: 28),
          const SizedBox(width: 8),
          Text(resourceKindNames[e.kind]!, style: _titleStyle),
        ]),
        const SizedBox(height: 6),
        Text('${resNames[e.res]}: ${e.amount.floor()}', style: _bodyStyle),
      ]);
    }
    return const SizedBox();
  }

  Widget _hpBar(double hp, double max) {
    final f = (hp / max).clamp(0.0, 1.0);
    return Row(children: [
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: f,
            minHeight: 7,
            backgroundColor: Colors.black45,
            color: f > 0.5
                ? Colors.greenAccent
                : (f > 0.25 ? Colors.amber : Colors.redAccent),
          ),
        ),
      ),
      const SizedBox(width: 6),
      Text('${hp.ceil()}/${max.floor()}',
          style: const TextStyle(color: Colors.white70, fontSize: 11)),
    ]);
  }

  static const _titleStyle =
      TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700);
  static const _bodyStyle = TextStyle(color: Colors.white70, fontSize: 12);

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Widget _actions() {
    if (game.placing != null) {
      return Wrap(spacing: 6, children: [
        _action(Icons.close, 'Cancelar', null, null, () {
          game.placing = null;
        }),
      ]);
    }
    final units = game.selectedUnits;
    if (units.isNotEmpty) {
      final villagers = units.any((u) => u.isVillager);
      final buttons = <Widget>[];
      if (villagers) {
        buttons.add(_action(
            Icons.eco, 'Economia', null, null, () => militaryTab = false,
            highlighted: !militaryTab));
        buttons.add(_action(
            Icons.security, 'Militar', null, null, () => militaryTab = true,
            highlighted: militaryTab));
        for (final t in militaryTab ? militaryBuildings : economyBuildings) {
          final d = buildingDefs[t]!;
          final reason = w.buildReason(GameWorld.human, t);
          buttons.add(_action(buildingIcons[t]!, d.name, d.cost, reason,
              () => game.startPlacing(t)));
        }
      }
      buttons.add(_action(Icons.stop_circle_outlined, 'Parar', null, null, () {
        for (final u in units) {
          u.task = Task.idle;
          u.path = [];
          u.target = null;
        }
      }));
      buttons.add(_action(
          Icons.delete_outline, 'Excluir', null, null, game.deleteSelection,
          danger: true));
      return Wrap(spacing: 6, runSpacing: 6, children: buttons);
    }
    final e = game.selection.first;
    if (e is Building && e.owner == GameWorld.human) {
      final buttons = <Widget>[];
      final p = w.players[GameWorld.human];
      for (final t in e.def.trains) {
        final d = unitDefs[t]!;
        buttons.add(_action(unitIcons[t]!, p.unitName(t), d.cost,
            w.trainReason(e, t), () => w.train(e, t)));
      }
      for (final t in w.techsAt(e)) {
        final d = techDefs[t]!;
        buttons.add(_action(techIcon(t), d.name, d.cost, w.researchReason(e, t),
            () => w.research(e, t),
            tooltip: d.desc, highlighted: ageTechs.containsKey(t)));
      }
      if (e.type == BuildingType.market && e.complete) {
        for (final r in [Res.food, Res.wood, Res.stone]) {
          final price = w.marketPrice[r]!.round();
          buttons.add(_action(
              Icons.add_shopping_cart,
              'Comprar 100 ${resNames[r]}',
              Cost(gold: price),
              p.res[Res.gold]! < price ? 'Falta Ouro' : null,
              () => w.marketBuy(GameWorld.human, r)));
          buttons.add(_action(
              Icons.sell,
              'Vender 100 ${resNames[r]}',
              null,
              p.res[r]! < 100 ? 'Falta ${resNames[r]}' : null,
              () => w.marketSell(GameWorld.human, r),
              tooltip: 'Recebe ${(price * 0.7).round()} de ouro'));
        }
      }
      buttons.add(_action(
          Icons.delete_outline, 'Excluir', null, null, game.deleteSelection,
          danger: true));
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (e.queue.isNotEmpty) _queue(e),
        Wrap(spacing: 6, runSpacing: 6, children: buttons),
      ]);
    }
    return const SizedBox();
  }

  Widget _queue(Building b) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        const Text('Fila: ',
            style: TextStyle(color: Colors.white60, fontSize: 12)),
        for (int i = 0; i < b.queue.length; i++)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Tooltip(
              message: 'Cancelar ${b.queue[i].name}',
              child: InkWell(
                onTap: () {
                  w.cancelQueue(b, i);
                  setState(() {});
                },
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: const Color(0xFF232B38),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: i == 0 ? accent : borderColor),
                  ),
                  child: Stack(children: [
                    Center(
                      child: Icon(
                        b.queue[i].unit != null
                            ? unitIcons[b.queue[i].unit]
                            : techIcon(b.queue[i].tech!),
                        size: 18,
                        color: Colors.white,
                      ),
                    ),
                    if (i == 0)
                      Positioned(
                        left: 2,
                        right: 2,
                        bottom: 2,
                        child: LinearProgressIndicator(
                          value: (b.queue[0].progress /
                                  (b.queue[0].unit != null
                                      ? unitDefs[b.queue[0].unit]!.trainTime
                                      : techDefs[b.queue[0].tech]!.time))
                              .clamp(0.0, 1.0),
                          minHeight: 3,
                          color: accent,
                          backgroundColor: Colors.black45,
                        ),
                      ),
                  ]),
                ),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _action(IconData icon, String label, Cost? cost, String? reason,
      VoidCallback onTap,
      {String? tooltip, bool highlighted = false, bool danger = false}) {
    final enabled = reason == null;
    final tip = [
      label,
      if (cost != null) 'Custo: $cost',
      if (tooltip != null) tooltip,
      if (reason != null) reason,
    ].join('\n');
    return Tooltip(
      message: tip,
      waitDuration: const Duration(milliseconds: 300),
      child: Material(
        color: highlighted
            ? const Color(0xFF4A3F22)
            : (danger ? const Color(0xFF3A2024) : const Color(0xFF232B38)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: highlighted ? accent : borderColor),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            if (!enabled) {
              w.message(reason);
            } else {
              onTap();
            }
            setState(() {});
          },
          child: Opacity(
            opacity: enabled ? 1 : 0.45,
            child: SizedBox(
              width: 76,
              height: 62,
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon,
                          size: 20,
                          color: danger ? Colors.redAccent : Colors.white),
                      const SizedBox(height: 2),
                      Text(label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 10)),
                      if (cost != null && !cost.isFree) _costRow(cost),
                    ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _costRow(Cost c) {
    return FittedBox(
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (final r in Res.values)
          if (c.of(r) > 0) ...[
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.only(right: 2, left: 3),
              decoration:
                  BoxDecoration(color: resColors[r], shape: BoxShape.circle),
            ),
            Text('${c.of(r)}',
                style: const TextStyle(color: Colors.white70, fontSize: 9)),
          ],
      ]),
    );
  }

  // ---------------------------------------------------------------------------
  // Overlays
  // ---------------------------------------------------------------------------

  Widget _pauseOverlay() {
    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          color: Colors.black26,
          alignment: Alignment.center,
          child: const Text('PAUSADO',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 6)),
        ),
      ),
    );
  }

  Widget _gameOver() {
    final win = w.winner == GameWorld.human;
    final p = w.players[GameWorld.human];
    final e = w.players[GameWorld.enemy];
    TableRow row(String a, String b, String c) => TableRow(children: [
          Padding(
              padding: const EdgeInsets.all(4),
              child: Text(a, style: _bodyStyle)),
          Padding(
              padding: const EdgeInsets.all(4),
              child: Text(b, style: const TextStyle(color: Color(0xFF7FB6FF)))),
          Padding(
              padding: const EdgeInsets.all(4),
              child: Text(c, style: const TextStyle(color: Color(0xFFFF8A8A)))),
        ]);
    return Positioned.fill(
      child: Container(
        color: Colors.black54,
        alignment: Alignment.center,
        child: Container(
          width: 380,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF1B212C),
            borderRadius: BorderRadius.circular(14),
            border:
                Border.all(color: win ? accent : Colors.redAccent, width: 2),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(win ? Icons.emoji_events : Icons.flag,
                size: 48, color: win ? accent : Colors.redAccent),
            const SizedBox(height: 8),
            Text(win ? 'VITÓRIA!' : 'DERROTA',
                style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    color: win ? accent : Colors.redAccent)),
            const SizedBox(height: 4),
            Text('Tempo de jogo: ${_fmtTime(w.time)}', style: _bodyStyle),
            const SizedBox(height: 12),
            Table(children: [
              row('', 'Você', 'Inimigo'),
              row('Idade', ageNames[p.age]!.replaceAll('Idade ', ''),
                  ageNames[e.age]!.replaceAll('Idade ', '')),
              row('Unidades treinadas', '${p.unitsTrained}',
                  '${e.unitsTrained}'),
              row('Abates', '${p.kills}', '${e.kills}'),
              row('Unidades perdidas', '${p.unitsLost}', '${e.unitsLost}'),
              row('Prédios construídos', '${p.buildingsBuilt}',
                  '${e.buildingsBuilt}'),
              row('Recursos coletados', '${p.totalGathered.floor()}',
                  '${e.totalGathered.floor()}'),
              row('Tecnologias', '${p.techs.length}', '${e.techs.length}'),
            ]),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              OutlinedButton(
                  onPressed: game.quitToMenu, child: const Text('Menu')),
              const SizedBox(width: 10),
              FilledButton(
                  onPressed: () => game.startGame(
                      w.difficulty, DateTime.now().millisecondsSinceEpoch),
                  child: const Text('Jogar novamente')),
            ]),
          ]),
        ),
      ),
    );
  }
}

const _helpText = '''Objetivo: destrua todos os prédios e unidades do inimigo.

Recursos: Comida (frutas, fazendas), Madeira (árvores), Ouro e Pedra (minas). Aldeões levam os recursos ao Centro da Cidade ou aos campos de depósito.

Mouse: clique esquerdo seleciona, arraste para selecionar em área, clique direito dá ordens (mover, coletar, construir, atacar). Botão direito/meio arrastando move a câmera; roda do mouse = zoom.

Toque: toque para selecionar; com unidades selecionadas, toque no chão/recurso/inimigo para dar ordens. Arraste para mover a câmera, pinça para zoom. Use o botão de seleção em área para arrastar e selecionar.

Teclado: WASD/setas movem a câmera, H = Centro da Cidade, . = aldeão ocioso, ESC = cancelar, Del = excluir, Espaço = pausar.

Avance de idade no Centro da Cidade para liberar novos prédios, unidades e tecnologias.''';

const helpText = _helpText;
