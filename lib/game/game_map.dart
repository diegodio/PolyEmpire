import 'dart:collection';
import 'dart:math';
import 'dart:typed_data';

import 'config.dart';
import 'entities.dart';

enum Terrain { grass, water, sand, dirt }

/// Tile grid ("chess board") with occupancy and A* pathfinding.
class GameMap {
  final int size;
  late final List<Terrain> terrain;
  late final List<Entity?> occupant; // resource or building (non-walkable)
  late final List<Building?> farmAt; // farms (walkable)
  late final Float32List shade; // visual variation per tile

  GameMap(this.size) {
    terrain = List.filled(size * size, Terrain.grass);
    occupant = List.filled(size * size, null);
    farmAt = List.filled(size * size, null);
    shade = Float32List(size * size);
  }

  int idx(int x, int y) => y * size + x;
  bool inBounds(int x, int y) => x >= 0 && y >= 0 && x < size && y < size;

  Terrain terrainAt(int x, int y) => terrain[idx(x, y)];

  bool walkable(int x, int y) {
    if (!inBounds(x, y)) return false;
    final i = idx(x, y);
    return terrain[i] != Terrain.water && occupant[i] == null;
  }

  bool buildable(int x, int y) {
    if (!inBounds(x, y)) return false;
    final i = idx(x, y);
    return terrain[i] != Terrain.water &&
        occupant[i] == null &&
        farmAt[i] == null;
  }

  Entity? entityAt(int x, int y) {
    if (!inBounds(x, y)) return null;
    final i = idx(x, y);
    return occupant[i] ?? farmAt[i];
  }

  void placeBuilding(Building b) {
    for (int y = b.ty; y < b.ty + b.size; y++) {
      for (int x = b.tx; x < b.tx + b.size; x++) {
        if (b.def.walkable) {
          farmAt[idx(x, y)] = b;
        } else {
          occupant[idx(x, y)] = b;
        }
      }
    }
  }

  void removeBuilding(Building b) {
    for (int y = b.ty; y < b.ty + b.size; y++) {
      for (int x = b.tx; x < b.tx + b.size; x++) {
        final i = idx(x, y);
        if (occupant[i] == b) occupant[i] = null;
        if (farmAt[i] == b) farmAt[i] = null;
      }
    }
  }

  void removeResource(ResourceNode r) {
    final i = idx(r.tx, r.ty);
    if (occupant[i] == r) occupant[i] = null;
  }

  bool canPlace(BuildingType type, int tx, int ty) {
    final s = buildingDefs[type]!.size;
    for (int y = ty; y < ty + s; y++) {
      for (int x = tx; x < tx + s; x++) {
        if (!buildable(x, y)) return false;
      }
    }
    return true;
  }

  // ---------------------------------------------------------------------------
  // Map generation
  // ---------------------------------------------------------------------------

  /// Generates terrain and returns the resource nodes created.
  List<ResourceNode> generate(Random rnd, List<Point<int>> bases) {
    final nodes = <ResourceNode>[];
    for (int i = 0; i < shade.length; i++) {
      shade[i] = rnd.nextDouble();
    }

    bool nearBase(int x, int y, double r) {
      for (final b in bases) {
        final dx = x - b.x, dy = y - b.y;
        if (dx * dx + dy * dy < r * r) return true;
      }
      return false;
    }

    void blob(int cx, int cy, double r, void Function(int x, int y) f) {
      final ri = r.ceil() + 1;
      for (int y = cy - ri; y <= cy + ri; y++) {
        for (int x = cx - ri; x <= cx + ri; x++) {
          if (!inBounds(x, y)) continue;
          final dx = x - cx, dy = y - cy;
          final d = sqrt(dx * dx + dy * dy) + rnd.nextDouble() * 1.2 - 0.6;
          if (d <= r) f(x, y);
        }
      }
    }

    // Lakes.
    final lakes = 2 + rnd.nextInt(2);
    for (int l = 0; l < lakes; l++) {
      for (int tries = 0; tries < 40; tries++) {
        final cx = 8 + rnd.nextInt(size - 16);
        final cy = 8 + rnd.nextInt(size - 16);
        if (nearBase(cx, cy, 16)) continue;
        final r = 2.5 + rnd.nextDouble() * 2.5;
        blob(cx, cy, r + 1.3, (x, y) {
          if (terrain[idx(x, y)] != Terrain.water) {
            terrain[idx(x, y)] = Terrain.sand;
          }
        });
        blob(cx, cy, r, (x, y) => terrain[idx(x, y)] = Terrain.water);
        break;
      }
    }

    // Dirt patches for variety.
    for (int i = 0; i < 18; i++) {
      final cx = rnd.nextInt(size), cy = rnd.nextInt(size);
      blob(cx, cy, 1 + rnd.nextDouble() * 2, (x, y) {
        if (terrain[idx(x, y)] == Terrain.grass) {
          terrain[idx(x, y)] = Terrain.dirt;
        }
      });
    }

    void addNode(ResourceKind k, int x, int y) {
      if (!inBounds(x, y)) return;
      final i = idx(x, y);
      if (terrain[i] == Terrain.water || occupant[i] != null) return;
      final n = ResourceNode(
        kind: k,
        tx: x,
        ty: y,
        amount: resourceKindAmount[k]!,
        variant: rnd.nextDouble(),
      );
      occupant[i] = n;
      nodes.add(n);
    }

    // Border forest.
    for (int y = 0; y < size; y++) {
      for (int x = 0; x < size; x++) {
        final edge = min(min(x, y), min(size - 1 - x, size - 1 - y));
        if (edge < 1 || (edge < 3 && rnd.nextDouble() < 0.35)) {
          if (!nearBase(x, y, 9)) addNode(ResourceKind.tree, x, y);
        }
      }
    }

    // Forest clusters.
    final forests = 16 + rnd.nextInt(6);
    for (int f = 0; f < forests; f++) {
      for (int tries = 0; tries < 30; tries++) {
        final cx = 4 + rnd.nextInt(size - 8);
        final cy = 4 + rnd.nextInt(size - 8);
        if (nearBase(cx, cy, 11)) continue;
        blob(cx, cy, 1.5 + rnd.nextDouble() * 2.8, (x, y) {
          if (rnd.nextDouble() < 0.9) addNode(ResourceKind.tree, x, y);
        });
        break;
      }
    }

    void cluster(ResourceKind k, int cx, int cy, int count) {
      final open = Queue<Point<int>>()..add(Point(cx, cy));
      final seen = <Point<int>>{};
      int placed = 0;
      while (open.isNotEmpty && placed < count) {
        final p = open.removeFirst();
        if (!seen.add(p)) continue;
        if (!inBounds(p.x, p.y)) continue;
        final i = idx(p.x, p.y);
        if (terrain[i] == Terrain.water) continue;
        if (occupant[i] == null) {
          addNode(k, p.x, p.y);
          placed++;
        }
        final dirs = [
          const Point(1, 0),
          const Point(-1, 0),
          const Point(0, 1),
          const Point(0, -1)
        ]..shuffle(rnd);
        for (final d in dirs) {
          open.add(Point(p.x + d.x, p.y + d.y));
        }
      }
    }

    // Base resources (symmetric-ish per base).
    for (final b in bases) {
      final ang = rnd.nextDouble() * pi * 2;
      Point<int> at(double a, double dist) => Point(
            (b.x + cos(a) * dist).round().clamp(3, size - 4),
            (b.y + sin(a) * dist).round().clamp(3, size - 4),
          );
      final g = at(ang, 7);
      cluster(ResourceKind.gold, g.x, g.y, 6);
      final s = at(ang + 2.0, 7.5);
      cluster(ResourceKind.stone, s.x, s.y, 5);
      final be = at(ang + 3.6, 5.5);
      cluster(ResourceKind.berries, be.x, be.y, 6);
      final w = at(ang + 4.8, 9);
      blob(w.x, w.y, 2.4, (x, y) => addNode(ResourceKind.tree, x, y));
      final w2 = at(ang + 1.0, 10);
      blob(w2.x, w2.y, 1.8, (x, y) => addNode(ResourceKind.tree, x, y));
    }

    // Extra contested resources in the middle.
    final mid = size ~/ 2;
    cluster(ResourceKind.gold, mid - 4 + rnd.nextInt(3), mid + 3, 7);
    cluster(ResourceKind.gold, mid + 3, mid - 4 + rnd.nextInt(3), 7);
    cluster(ResourceKind.stone, mid + rnd.nextInt(3), mid, 5);
    for (int i = 0; i < 4; i++) {
      final x = 6 + rnd.nextInt(size - 12), y = 6 + rnd.nextInt(size - 12);
      if (!nearBase(x, y, 12)) cluster(ResourceKind.berries, x, y, 4);
    }

    // Make sure the bases are connected.
    _ensureConnected(bases[0], bases[1], nodes);
    return nodes;
  }

  void _ensureConnected(Point<int> a, Point<int> b, List<ResourceNode> nodes) {
    final reach = _flood(a);
    if (reach[idx(b.x, b.y)]) return;
    // Carve a straight corridor.
    final steps = max((b.x - a.x).abs(), (b.y - a.y).abs());
    for (int s = 0; s <= steps; s++) {
      final x = (a.x + (b.x - a.x) * s / steps).round();
      final y = (a.y + (b.y - a.y) * s / steps).round();
      for (int oy = 0; oy <= 1; oy++) {
        for (int ox = 0; ox <= 1; ox++) {
          if (!inBounds(x + ox, y + oy)) continue;
          final i = idx(x + ox, y + oy);
          final o = occupant[i];
          if (o is ResourceNode) {
            occupant[i] = null;
            nodes.remove(o);
          }
          if (terrain[i] == Terrain.water) terrain[i] = Terrain.sand;
        }
      }
    }
  }

  List<bool> _flood(Point<int> start) {
    final seen = List.filled(size * size, false);
    final q = Queue<Point<int>>()..add(start);
    seen[idx(start.x, start.y)] = true;
    while (q.isNotEmpty) {
      final p = q.removeFirst();
      for (final d in const [
        Point(1, 0),
        Point(-1, 0),
        Point(0, 1),
        Point(0, -1)
      ]) {
        final nx = p.x + d.x, ny = p.y + d.y;
        if (!inBounds(nx, ny)) continue;
        final i = idx(nx, ny);
        if (seen[i]) continue;
        // Treat buildings as passable for this connectivity check.
        if (terrain[i] == Terrain.water || occupant[i] is ResourceNode)
          continue;
        seen[i] = true;
        q.add(Point(nx, ny));
      }
    }
    return seen;
  }

  // ---------------------------------------------------------------------------
  // Pathfinding (8-directional A*, no corner cutting)
  // ---------------------------------------------------------------------------

  late final Float64List _g = Float64List(size * size);
  late final Int32List _parent = Int32List(size * size);
  late final Int32List _stamp = Int32List(size * size);
  late final Uint8List _closed = Uint8List(size * size);
  int _curStamp = 0;

  /// Finds a path from (sx,sy) to a tile in the goal rectangle
  /// [gx0,gx1]x[gy0,gy1]. When [adjacent] is true the goal is any walkable tile
  /// touching that rectangle (used for resources/buildings).
  List<Point<int>> findPath(
    int sx,
    int sy,
    int gx0,
    int gy0,
    int gx1,
    int gy1, {
    bool adjacent = false,
    int maxNodes = 6000,
  }) {
    _curStamp++;
    if (_curStamp > 1 << 30) {
      _stamp.fillRange(0, _stamp.length, 0);
      _curStamp = 1;
    }
    final stamp = _curStamp;
    final tcx = (gx0 + gx1) / 2, tcy = (gy0 + gy1) / 2;

    bool isGoal(int x, int y) {
      if (adjacent) {
        return x >= gx0 - 1 &&
            x <= gx1 + 1 &&
            y >= gy0 - 1 &&
            y <= gy1 + 1 &&
            !(x >= gx0 && x <= gx1 && y >= gy0 && y <= gy1);
      }
      return x >= gx0 && x <= gx1 && y >= gy0 && y <= gy1;
    }

    double h(int x, int y) {
      final dx = (x - tcx).abs(), dy = (y - tcy).abs();
      return max(dx, dy) + 0.414 * min(dx, dy);
    }

    final heap = _Heap();
    final s = idx(sx, sy);
    _stamp[s] = stamp;
    _g[s] = 0;
    _parent[s] = -1;
    _closed[s] = 0;
    heap.push(s, h(sx, sy));
    int best = s;
    double bestH = h(sx, sy);
    int expanded = 0;

    while (heap.isNotEmpty) {
      final cur = heap.pop();
      if (_closed[cur] == 1 && _stamp[cur] == stamp) continue;
      _closed[cur] = 1;
      final cx = cur % size, cy = cur ~/ size;
      if (isGoal(cx, cy) && (cur != s || walkable(cx, cy))) {
        return _build(cur);
      }
      final hh = h(cx, cy);
      if (hh < bestH) {
        bestH = hh;
        best = cur;
      }
      if (++expanded > maxNodes) break;
      for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          final nx = cx + dx, ny = cy + dy;
          if (!walkable(nx, ny)) continue;
          if (dx != 0 && dy != 0) {
            if (!walkable(cx + dx, cy) || !walkable(cx, cy + dy)) continue;
          }
          final ni = idx(nx, ny);
          final ng = _g[cur] + ((dx != 0 && dy != 0) ? 1.414 : 1.0);
          if (_stamp[ni] != stamp) {
            _stamp[ni] = stamp;
            _closed[ni] = 0;
          } else if (_closed[ni] == 1 || ng >= _g[ni]) {
            continue;
          }
          _g[ni] = ng;
          _parent[ni] = cur;
          heap.push(ni, ng + h(nx, ny));
        }
      }
    }
    // Unreachable: go as close as possible.
    return _build(best);
  }

  List<Point<int>> _build(int end) {
    final out = <Point<int>>[];
    int c = end;
    while (c != -1) {
      out.add(Point(c % size, c ~/ size));
      c = _parent[c];
    }
    return out.reversed.toList();
  }

  /// Nearest walkable tile to (x,y) by spiral search.
  Point<int>? nearestWalkable(int x, int y, {int maxR = 12}) {
    if (walkable(x, y)) return Point(x, y);
    for (int r = 1; r <= maxR; r++) {
      for (int dy = -r; dy <= r; dy++) {
        for (int dx = -r; dx <= r; dx++) {
          if (max(dx.abs(), dy.abs()) != r) continue;
          if (walkable(x + dx, y + dy)) return Point(x + dx, y + dy);
        }
      }
    }
    return null;
  }
}

class _Heap {
  final List<int> _items = [];
  final List<double> _keys = [];
  bool get isNotEmpty => _items.isNotEmpty;

  void push(int item, double key) {
    _items.add(item);
    _keys.add(key);
    int i = _items.length - 1;
    while (i > 0) {
      final p = (i - 1) >> 1;
      if (_keys[p] <= _keys[i]) break;
      _swap(i, p);
      i = p;
    }
  }

  int pop() {
    final top = _items[0];
    final last = _items.length - 1;
    _swap(0, last);
    _items.removeLast();
    _keys.removeLast();
    int i = 0;
    final n = _items.length;
    while (true) {
      final l = i * 2 + 1, r = l + 1;
      int m = i;
      if (l < n && _keys[l] < _keys[m]) m = l;
      if (r < n && _keys[r] < _keys[m]) m = r;
      if (m == i) break;
      _swap(i, m);
      i = m;
    }
    return top;
  }

  void _swap(int a, int b) {
    final t = _items[a];
    _items[a] = _items[b];
    _items[b] = t;
    final k = _keys[a];
    _keys[a] = _keys[b];
    _keys[b] = k;
  }
}
