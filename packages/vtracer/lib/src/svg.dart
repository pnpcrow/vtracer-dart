import 'package:visioncortex/visioncortex.dart';

import 'ir.dart';

/// SVG serializer configuration.
class SvgWriter {
  /// Allow relative commands where they serialize shorter.
  final bool relative;

  /// Allow `H`/`V`/`S` shorthands and `<g fill>` grouping.
  final bool shorthands;

  /// Decimal places for coordinates (null = full precision).
  final int? precision;

  const SvgWriter({this.relative = true, this.shorthands = true, this.precision = 2});

  String write(VectorDoc doc) {
    final out = StringBuffer();
    out.write('<?xml version="1.0" encoding="UTF-8"?>\n');
    out.write('<!-- Generator: vtracer-dart -->\n');
    out.write(
        '<svg version="1.1" xmlns="http://www.w3.org/2000/svg" width="${doc.width}" height="${doc.height}">\n');

    if (shorthands) {
      _writeGrouped(out, doc.shapes);
    } else {
      for (final shape in doc.shapes) {
        _writePath(out, shape, true);
      }
    }

    out.write('</svg>\n');
    return out.toString();
  }

  /// Emit shapes, grouping maximal runs of consecutive same-fill shapes into
  /// a single `<g fill>` (preserving paint order).
  void _writeGrouped(StringBuffer out, List<Shape> shapes) {
    var i = 0;
    while (i < shapes.length) {
      final fill = _shapeFill(shapes[i]);
      var j = i + 1;
      while (j < shapes.length && _shapeFill(shapes[j]) == fill) {
        j++;
      }
      final run = shapes.sublist(i, j);
      if (run.length > 1) {
        out.write('<g fill="$fill">\n');
        for (final shape in run) {
          _writePath(out, shape, false);
        }
        out.write('</g>\n');
      } else {
        _writePath(out, run[0], true);
      }
      i = j;
    }
  }

  void _writePath(StringBuffer out, Shape shape, bool withFill) {
    final d = _encodePath(shape);
    if (d.isEmpty) {
      return;
    }
    if (withFill) {
      out.write('<path d="$d" fill="${_shapeFill(shape)}"/>\n');
    } else {
      out.write('<path d="$d"/>\n');
    }
  }

  String _encodePath(Shape shape) {
    final emitter = _Emitter(relative, shorthands, precision);
    for (final sub in shape.path.subpaths) {
      emitter.subpath(sub);
    }
    return emitter.finish();
  }
}

String _shapeFill(Shape shape) => shape.paint.color.toHexString();

/// Streaming SVG-path encoder that tracks the current point.
class _Emitter {
  final bool relative;
  final bool shorthands;
  final int? precision;

  final StringBuffer out = StringBuffer();
  PointF64 cur = PointF64.zero();

  /// Start of the current subpath; `cur` returns here after `Z`.
  PointF64 subpathStart = PointF64.zero();
  bool started = false;

  /// Absolute second control point of the previous cubic, for `S` detection.
  PointF64? prevCubicC2;

  _Emitter(this.relative, this.shorthands, this.precision);

  String finish() => out.toString();

  void subpath(SubPath sub) {
    for (final cmd in sub.commands) {
      switch (cmd) {
        case MoveTo(:final p):
          _moveTo(p);
        case LineTo(:final p):
          _lineTo(p);
        case CubicTo(:final c1, :final c2, :final end):
          _cubicTo(c1, c2, end);
        case ClosePath():
          out.write('Z');
          // SVG resets the current point to the subpath's start after Z; a
          // following relative `m`/`l` is measured from there.
          cur = subpathStart.clone();
          prevCubicC2 = null;
      }
    }
  }

  void _moveTo(PointF64 p) {
    if (!started) {
      // First move is always absolute.
      out.write('M${_coord(p)}');
      started = true;
    } else {
      final abs = 'M${_coord(p)}';
      if (relative) {
        final rel = 'm${_coordDelta(p)}';
        out.write(rel.length < abs.length ? rel : abs);
      } else {
        out.write(abs);
      }
    }
    cur = p.clone();
    subpathStart = p.clone();
    prevCubicC2 = null;
  }

  void _lineTo(PointF64 p) {
    final candidates = <String>[];

    // Axis-aligned shorthands.
    if (shorthands) {
      if (p.y == cur.y) {
        candidates.add('H${_num(p.x)}');
        if (relative) {
          candidates.add('h${_num(p.x - cur.x)}');
        }
      }
      if (p.x == cur.x) {
        candidates.add('V${_num(p.y)}');
        if (relative) {
          candidates.add('v${_num(p.y - cur.y)}');
        }
      }
    }

    candidates.add('L${_coord(p)}');
    if (relative) {
      candidates.add('l${_coordDelta(p)}');
    }

    out.write(_shortest(candidates));
    cur = p.clone();
    prevCubicC2 = null;
  }

  void _cubicTo(PointF64 c1, PointF64 c2, PointF64 e) {
    final candidates = <String>[];

    // Smooth continuation: c1 is the reflection of the previous cubic's c2.
    if (shorthands && prevCubicC2 != null) {
      final reflection =
          PointF64(2.0 * cur.x - prevCubicC2!.x, 2.0 * cur.y - prevCubicC2!.y);
      if (_approx(reflection, c1)) {
        candidates.add('S${_coordList([c2, e])}');
        if (relative) {
          candidates.add('s${_deltaList([c2, e])}');
        }
      }
    }

    candidates.add('C${_coordList([c1, c2, e])}');
    if (relative) {
      candidates.add('c${_deltaList([c1, c2, e])}');
    }

    out.write(_shortest(candidates));
    cur = e.clone();
    prevCubicC2 = c2.clone();
  }

  // --- number/coordinate formatting --------------------------------------

  String _num(double v) => _fmtNum(v, precision);

  String _coord(PointF64 p) => _joinNums([_num(p.x), _num(p.y)]);

  String _coordDelta(PointF64 p) =>
      _joinNums([_num(p.x - cur.x), _num(p.y - cur.y)]);

  String _coordList(List<PointF64> pts) {
    final nums = <String>[];
    for (final p in pts) {
      nums.add(_num(p.x));
      nums.add(_num(p.y));
    }
    return _joinNums(nums);
  }

  String _deltaList(List<PointF64> pts) {
    final nums = <String>[];
    for (final p in pts) {
      nums.add(_num(p.x - cur.x));
      nums.add(_num(p.y - cur.y));
    }
    return _joinNums(nums);
  }
}

bool _approx(PointF64 a, PointF64 b) =>
    (a.x - b.x).abs() < 1e-6 && (a.y - b.y).abs() < 1e-6;

String _shortest(List<String> candidates) {
  var best = '';
  for (final c in candidates) {
    if (best.isEmpty || c.length < best.length) {
      best = c;
    }
  }
  return best;
}

/// Join formatted numbers with the minimal separators SVG allows: a comma,
/// except that a leading `-` is self-separating.
String _joinNums(List<String> nums) {
  final s = StringBuffer();
  for (var i = 0; i < nums.length; i++) {
    if (i > 0 && !nums[i].startsWith('-')) {
      s.write(',');
    }
    s.write(nums[i]);
  }
  return s.toString();
}

/// Compact number formatting: round to precision, trim trailing zeros, use a
/// leading-dot for magnitudes below 1.
String _fmtNum(double v, int? precision) {
  double rounded = v;
  if (precision != null) {
    final factor = _pow10(precision);
    rounded = (v * factor).roundToDouble() / factor;
  }
  // Normalize -0.0 to 0.
  if (rounded == 0.0) {
    return '0';
  }

  var s = precision != null ? rounded.toStringAsFixed(precision) : '$rounded';

  if (s.contains('.')) {
    while (s.endsWith('0')) {
      s = s.substring(0, s.length - 1);
    }
    if (s.endsWith('.')) {
      s = s.substring(0, s.length - 1);
    }
  }

  if (s.startsWith('0.')) {
    s = '.${s.substring(2)}';
  } else if (s.startsWith('-0.')) {
    s = '-.${s.substring(3)}';
  }

  return s;
}

double _pow10(int p) {
  const table = [
    1.0, 10.0, 100.0, 1000.0, 10000.0, 100000.0, 1000000.0, 10000000.0,
    100000000.0,
  ];
  if (p < 0) return 1.0;
  return p < table.length ? table[p] : table.last * _pow10(p - table.length + 1);
}
