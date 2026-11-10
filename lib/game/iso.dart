import 'dart:ui';

/// Isometric projection helpers. Tiles are 64x32 pixel diamonds.
const double hw = 32; // half tile width
const double hh = 16; // half tile height

Offset iso(double x, double y, [double z = 0]) =>
    Offset((x - y) * hw, (x + y) * hh - z);

/// Inverse projection of a world-pixel point on the ground plane.
Offset unIso(double px, double py) =>
    Offset((px / hw + py / hh) / 2, (py / hh - px / hw) / 2);

Color shadeColor(Color c, double f) {
  if (f >= 1) {
    final t = (f - 1).clamp(0.0, 1.0);
    return Color.lerp(c, const Color(0xFFFFFFFF), t)!;
  }
  return Color.lerp(const Color(0xFF000000), c, f.clamp(0.0, 1.0))!;
}

/// Small helper that draws flat-shaded polygons with a reusable paint/path.
class Poly {
  final Paint paint = Paint()..isAntiAlias = true;
  final Paint stroke = Paint()
    ..style = PaintingStyle.stroke
    ..isAntiAlias = true;
  final Path _path = Path();
  late Canvas canvas;

  void fill(List<Offset> pts, Color c) {
    _path.reset();
    _path.moveTo(pts[0].dx, pts[0].dy);
    for (int i = 1; i < pts.length; i++) {
      _path.lineTo(pts[i].dx, pts[i].dy);
    }
    _path.close();
    paint.color = c;
    canvas.drawPath(_path, paint);
  }

  void line(Offset a, Offset b, Color c, double w) {
    stroke.color = c;
    stroke.strokeWidth = w;
    stroke.strokeCap = StrokeCap.round;
    canvas.drawLine(a, b, stroke);
  }

  void outline(List<Offset> pts, Color c, double w) {
    _path.reset();
    _path.moveTo(pts[0].dx, pts[0].dy);
    for (int i = 1; i < pts.length; i++) {
      _path.lineTo(pts[i].dx, pts[i].dy);
    }
    _path.close();
    stroke.color = c;
    stroke.strokeWidth = w;
    canvas.drawPath(_path, stroke);
  }

  void oval(Offset c, double rx, double ry, Color color) {
    paint.color = color;
    canvas.drawOval(
        Rect.fromCenter(center: c, width: rx * 2, height: ry * 2), paint);
  }

  void ovalStroke(Offset c, double rx, double ry, Color color, double w) {
    stroke.color = color;
    stroke.strokeWidth = w;
    canvas.drawOval(
        Rect.fromCenter(center: c, width: rx * 2, height: ry * 2), stroke);
  }

  /// Axis-aligned box in world tile coordinates with heights in pixels.
  void box(
      double x0, double y0, double x1, double y1, double z0, double z1, Color c,
      {double alpha = 1}) {
    Color a(Color k) => alpha >= 1 ? k : k.withValues(alpha: alpha);
    // Left-front face (y = y1)
    fill([iso(x0, y1, z0), iso(x1, y1, z0), iso(x1, y1, z1), iso(x0, y1, z1)],
        a(shadeColor(c, 0.92)));
    // Right-front face (x = x1)
    fill([iso(x1, y0, z0), iso(x1, y1, z0), iso(x1, y1, z1), iso(x1, y0, z1)],
        a(shadeColor(c, 0.72)));
    // Top
    fill([iso(x0, y0, z1), iso(x1, y0, z1), iso(x1, y1, z1), iso(x0, y1, z1)],
        a(shadeColor(c, 1.12)));
  }

  /// Four-sided pyramid roof.
  void pyramid(double x0, double y0, double x1, double y1, double zb, double zt,
      Color c) {
    final apex = iso((x0 + x1) / 2, (y0 + y1) / 2, zt);
    fill([iso(x0, y0, zb), iso(x1, y0, zb), apex], shadeColor(c, 1.18));
    fill([iso(x0, y0, zb), iso(x0, y1, zb), apex], shadeColor(c, 1.05));
    fill([iso(x0, y1, zb), iso(x1, y1, zb), apex], shadeColor(c, 0.9));
    fill([iso(x1, y0, zb), iso(x1, y1, zb), apex], shadeColor(c, 0.7));
  }

  /// Gable roof with the ridge running along the x axis.
  void gable(
      double x0, double y0, double x1, double y1, double zb, double zr, Color c,
      {Color? wall}) {
    final cy = (y0 + y1) / 2;
    fill([iso(x0, y0, zb), iso(x1, y0, zb), iso(x1, cy, zr), iso(x0, cy, zr)],
        shadeColor(c, 1.15));
    fill([iso(x0, y1, zb), iso(x1, y1, zb), iso(x1, cy, zr), iso(x0, cy, zr)],
        shadeColor(c, 0.9));
    fill([iso(x1, y0, zb), iso(x1, y1, zb), iso(x1, cy, zr)],
        shadeColor(wall ?? c, 0.7));
  }

  /// Low-poly cone (tree tier, tent...) at screen base point.
  void cone(Offset base, double r, double zb, double zt, Color c) {
    final apex = base.translate(0, -zt);
    final l = base.translate(-r, -zb);
    final rt = base.translate(r, -zb);
    final f = base.translate(r * 0.12, -zb + r * 0.5);
    final back = base.translate(-r * 0.1, -zb - r * 0.45);
    fill([apex, back, l], shadeColor(c, 1.05));
    fill([apex, rt, back], shadeColor(c, 0.85));
    fill([apex, l, f], shadeColor(c, 1.18));
    fill([apex, f, rt], shadeColor(c, 0.72));
  }

  /// Faceted rock / crystal chunk.
  void rock(Offset c, double w, double h, Color color) {
    final top = c.translate(w * 0.1, -h);
    final ul = c.translate(-w, -h * 0.45);
    final ll = c.translate(-w * 0.8, 0);
    final bot = c.translate(w * 0.05, w * 0.35);
    final lr = c.translate(w * 0.85, 0);
    final ur = c.translate(w, -h * 0.5);
    final inner = c.translate(w * 0.15, -h * 0.42);
    fill([top, ul, inner], shadeColor(color, 1.25));
    fill([top, inner, ur], shadeColor(color, 1.05));
    fill([ul, ll, bot, inner], shadeColor(color, 0.88));
    fill([inner, bot, lr, ur], shadeColor(color, 0.66));
  }
}
