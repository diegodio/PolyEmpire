import 'package:flutter_test/flutter_test.dart';
import 'package:polyempire/game/config.dart';
import 'package:polyempire/game/world.dart';

void main() {
  test('enemy AI builds an economy, ages up and attacks', () {
    for (final seed in [1, 2, 3]) {
      final w = GameWorld(seed: seed, difficulty: Difficulty.hard);
      for (int i = 0; i < 30 * 1500 && w.winner == null; i++) {
        w.update(1 / 30);
      }
      final ai = w.players[GameWorld.enemy];
      expect(ai.age.index, greaterThanOrEqualTo(Age.feudal.index));
      expect(ai.unitsTrained, greaterThan(20));
      // The idle human player should have lost units to enemy attacks.
      expect(w.players[GameWorld.human].unitsLost, greaterThan(0));
    }
  });

  test('pathfinding reaches a reachable tile', () {
    final w = GameWorld(seed: 7, difficulty: Difficulty.normal);
    final a = w.humanBase, b = w.enemyBase;
    final path = w.map.findPath(
        a.x + 2, a.y + 2, b.x + 2, b.y + 2, b.x + 2, b.y + 2,
        maxNodes: 100000);
    expect(path.isNotEmpty, true);
  });
}
