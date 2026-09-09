/// RGBA color; each channel is 8-bit unsigned. Ported from visioncortex.
class Color {
  final int r;
  final int g;
  final int b;
  final int a;

  const Color(this.r, this.g, this.b, [this.a = 255]);

  const Color.zero()
      : r = 0,
        g = 0,
        b = 0,
        a = 0;

  static const black = Color(0, 0, 0);
  static const white = Color(255, 255, 255);
  static const red = Color(255, 0, 0);

  String toHexString() =>
      '#${r.toRadixString(16).padLeft(2, '0').toUpperCase()}'
      '${g.toRadixString(16).padLeft(2, '0').toUpperCase()}'
      '${b.toRadixString(16).padLeft(2, '0').toUpperCase()}';

  List<int> get rgbU8 => [r, g, b];

  @override
  bool operator ==(Object other) =>
      other is Color && r == other.r && g == other.g && b == other.b && a == other.a;

  @override
  int get hashCode => Object.hash(r, g, b, a);

  @override
  String toString() => 'Color($r,$g,$b,$a)';
}

/// Running color sums used by the color-cluster hierarchy.
class ColorSum {
  int r = 0;
  int g = 0;
  int b = 0;
  int a = 0;
  int counter = 0;

  void add(Color c) {
    r += c.r;
    g += c.g;
    b += c.b;
    a += c.a;
    counter++;
  }

  void addChannels(int cr, int cg, int cb, [int ca = 255]) {
    r += cr;
    g += cg;
    b += cb;
    a += ca;
    counter++;
  }

  void merge(ColorSum other) {
    r += other.r;
    g += other.g;
    b += other.b;
    a += other.a;
    counter += other.counter;
  }

  Color average() => Color(
        counter == 0 ? 0 : r ~/ counter,
        counter == 0 ? 0 : g ~/ counter,
        counter == 0 ? 0 : b ~/ counter,
        counter == 0 ? 0 : a ~/ counter,
      );

  void clear() {
    r = 0;
    g = 0;
    b = 0;
    a = 0;
    counter = 0;
  }

  ColorSum clone() => ColorSum()
    ..r = r
    ..g = g
    ..b = b
    ..a = a
    ..counter = counter;
}
