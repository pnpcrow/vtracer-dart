import 'dart:math' as math;
import 'dart:typed_data';

import 'package:visioncortex/visioncortex.dart';

/// Statistical fingerprint of a raster image, used as the compact input for
/// every tuning decision (heuristic rules and the Needle3 model payload).
///
/// All fields are computed from a bounded downsample (long side ~200px), so
/// extraction cost is near-constant regardless of the source resolution.
class ImageFeatures {
  /// Source pixel width/height (of the full-resolution image).
  final int width;
  final int height;

  /// Source size in megapixels.
  final double megapixels;

  /// width / height.
  final double aspectRatio;

  /// Distinct colors after quantizing each RGB channel to 4 significant
  /// bits (4096 possible buckets). A proxy for palette complexity.
  final int quantizedColors;

  /// Share of pixels (0..1) covered by the 8 largest quantized color
  /// buckets. High values mean flat/poster-like art; low values mean
  /// gradients or photos.
  final double paletteShare8;

  /// Share of pixels (0..1) covered by the single dominant color bucket.
  final double dominantShare;

  /// Fraction of sampled pixels whose Sobel gradient exceeds a fixed edge
  /// threshold (0..1). High = detailed / line-dense.
  final double edgeDensity;

  /// Mean Sobel gradient magnitude, normalized to the 0..255 channel scale.
  final double meanGradient;

  /// Share of pixels in near-flat regions (gradient below a small threshold).
  final double flatShare;

  /// Mean absolute Laplacian on flat regions — a robust noise/texture
  /// estimate (0..255 scale). JPEG artifacts and dithering push this up.
  final double noiseLevel;

  /// Hasler–Süsstrunk colorfulness metric. Low (<~15) means grayscale-ish.
  final double colorfulness;

  /// Share of pixels with any transparency (alpha < 250).
  final double transparentShare;

  /// Luminance percentile spread p95 - p5 (0..255).
  final double luminanceSpread;

  /// Share of dark (<64 luma) and light (>192 luma) pixels. Line art tends
  /// to concentrate mass on both ends.
  final double darkShare;
  final double lightShare;

  /// Standard deviation of border-pixel luminance; low values mean a clean,
  /// uniform background.
  final double backgroundUniformity;

  const ImageFeatures({
    required this.width,
    required this.height,
    required this.megapixels,
    required this.aspectRatio,
    required this.quantizedColors,
    required this.paletteShare8,
    required this.dominantShare,
    required this.edgeDensity,
    required this.meanGradient,
    required this.flatShare,
    required this.noiseLevel,
    required this.colorfulness,
    required this.transparentShare,
    required this.luminanceSpread,
    required this.darkShare,
    required this.lightShare,
    required this.backgroundUniformity,
  });

  /// Grayscale-ish inputs (scans, line art, monochrome).
  bool get isGrayscaleish => colorfulness < 14.0;

  /// Poster/flat-art-like inputs: few effective colors, concentrated palette.
  bool get isFlatPalette => paletteShare8 >= 0.80 && quantizedColors <= 64;

  /// Photo-like inputs: many colors, weak palette concentration, texture.
  bool get isPhotoLike =>
      quantizedColors > 96 && paletteShare8 < 0.55 && noiseLevel > 1.5;

  /// Compact, rounded payload for an LLM prompt (JSON-ready).
  Map<String, Object> toPromptPayload() => {
        'width_px': width,
        'height_px': height,
        'megapixels': _r(megapixels, 2),
        'aspect_ratio': _r(aspectRatio, 2),
        'quantized_colors': quantizedColors,
        'palette_share_top8': _r(paletteShare8, 3),
        'dominant_color_share': _r(dominantShare, 3),
        'edge_density': _r(edgeDensity, 3),
        'mean_gradient': _r(meanGradient, 1),
        'flat_share': _r(flatShare, 3),
        'noise_level': _r(noiseLevel, 1),
        'colorfulness': _r(colorfulness, 1),
        'transparent_share': _r(transparentShare, 3),
        'luminance_spread': _r(luminanceSpread, 1),
        'dark_share': _r(darkShare, 3),
        'light_share': _r(lightShare, 3),
        'background_uniformity': _r(backgroundUniformity, 1),
      };

  Map<String, Object> toJson() => toPromptPayload();

  static ImageFeatures fromJson(Map<String, Object?> json) => ImageFeatures(
        width: (json['width_px'] as num?)?.toInt() ?? 0,
        height: (json['height_px'] as num?)?.toInt() ?? 0,
        megapixels: (json['megapixels'] as num?)?.toDouble() ?? 0,
        aspectRatio: (json['aspect_ratio'] as num?)?.toDouble() ?? 1,
        quantizedColors: (json['quantized_colors'] as num?)?.toInt() ?? 0,
        paletteShare8: (json['palette_share_top8'] as num?)?.toDouble() ?? 0,
        dominantShare: (json['dominant_color_share'] as num?)?.toDouble() ?? 0,
        edgeDensity: (json['edge_density'] as num?)?.toDouble() ?? 0,
        meanGradient: (json['mean_gradient'] as num?)?.toDouble() ?? 0,
        flatShare: (json['flat_share'] as num?)?.toDouble() ?? 0,
        noiseLevel: (json['noise_level'] as num?)?.toDouble() ?? 0,
        colorfulness: (json['colorfulness'] as num?)?.toDouble() ?? 0,
        transparentShare: (json['transparent_share'] as num?)?.toDouble() ?? 0,
        luminanceSpread: (json['luminance_spread'] as num?)?.toDouble() ?? 0,
        darkShare: (json['dark_share'] as num?)?.toDouble() ?? 0,
        lightShare: (json['light_share'] as num?)?.toDouble() ?? 0,
        backgroundUniformity:
            (json['background_uniformity'] as num?)?.toDouble() ?? 0,
      );

  static double _r(double v, int digits) =>
      double.parse(v.toStringAsFixed(digits));
}

/// Computes [ImageFeatures] from RGBA pixel data.
class FeatureExtractor {
  /// Long-side bound of the analysis downsample; ~40k samples total.
  final int maxSamplesPerSide;

  const FeatureExtractor({this.maxSamplesPerSide = 200});

  ImageFeatures extract(ColorImage image) {
    final w = image.width, h = image.height;
    if (w < 1 || h < 1 || image.pixels.length < w * h * 4) {
      return ImageFeatures(
        width: w, height: h, megapixels: 0, aspectRatio: 1,
        quantizedColors: 0, paletteShare8: 0, dominantShare: 0,
        edgeDensity: 0, meanGradient: 0, flatShare: 1, noiseLevel: 0,
        colorfulness: 0, transparentShare: 0, luminanceSpread: 0,
        darkShare: 0, lightShare: 0, backgroundUniformity: 0,
      );
    }

    // Nearest-neighbor downsample (preserves noise texture, unlike box
    // filtering which would average it away and defeat `noiseLevel`).
    final scale = math.sqrt(w * h / (maxSamplesPerSide * maxSamplesPerSide));
    final dw = scale <= 1 ? w : math.max(2, (w / scale).round());
    final dh = scale <= 1 ? h : math.max(2, (h / scale).round());
    final luma = Float64List(dw * dh);
    final rg = Float64List(dw * dh);
    final yb = Float64List(dw * dh);
    final hist = Int32List(4096);
    var transparent = 0;

    for (var y = 0; y < dh; y++) {
      final sy = math.min(h - 1, (y * h) ~/ dh);
      for (var x = 0; x < dw; x++) {
        final sx = math.min(w - 1, (x * w) ~/ dw);
        final i = (sy * w + sx) * 4;
        final r = image.pixels[i], g = image.pixels[i + 1],
            b = image.pixels[i + 2], a = image.pixels[i + 3];
        final idx = y * dw + x;
        luma[idx] = 0.299 * r + 0.587 * g + 0.114 * b;
        rg[idx] = (r - g).toDouble();
        yb[idx] = 0.5 * (r + g) - b;
        if (a < 250) transparent++;
        hist[((r >> 4) << 8) | ((g >> 4) << 4) | (b >> 4)]++;
      }
    }
    final total = dw * dh;

    var quantizedColors = 0;
    var paletteShare8 = 0.0, dominantShare = 0.0;
    {
      final buckets = hist.where((c) => c > 0).toList()..sort();
      quantizedColors = buckets.length;
      var top8 = 0;
      for (var i = 0; i < buckets.length; i++) {
        final c = buckets[buckets.length - 1 - i];
        if (i < 8) top8 += c;
        if (i == 0) dominantShare = c / total;
      }
      paletteShare8 = top8 / total;
    }

    // Sobel gradient + Laplacian (3x3, borders skipped).
    var edgePixels = 0, gradSum = 0.0, flatPixels = 0, flatLapSum = 0.0;
    for (var y = 1; y < dh - 1; y++) {
      for (var x = 1; x < dw - 1; x++) {
        final i = y * dw + x;
        final tl = luma[i - dw - 1], t = luma[i - dw], tr = luma[i - dw + 1];
        final l = luma[i - 1], c = luma[i], r = luma[i + 1];
        final bl = luma[i + dw - 1], b = luma[i + dw], br = luma[i + dw + 1];
        final gx = (tr + 2 * r + br) - (tl + 2 * l + bl);
        final gy = (bl + 2 * b + br) - (tl + 2 * t + tr);
        final grad = math.sqrt(gx * gx + gy * gy) / 8;
        final lap = ((t + b + l + r) - 4 * c).abs();
        gradSum += grad;
        if (grad > 48) edgePixels++;
        if (grad < 24) {
          flatPixels++;
          flatLapSum += lap;
        }
      }
    }
    final inner = (dw - 2) * (dh - 2);
    final meanGradient = gradSum / inner;
    final edgeDensity = edgePixels / inner;
    final flatShare = flatPixels / inner;
    final noiseLevel = flatPixels > 0 ? flatLapSum / flatPixels : 0.0;

    // Colorfulness (Hasler & Süsstrunk 2003).
    final colorfulness = _colorfulness(rg, yb, total);

    // Luminance histogram stats + border uniformity.
    final lumaHist = Int32List(32);
    for (var i = 0; i < total; i++) {
      lumaHist[luma[i].clamp(0, 255).toInt() >> 3]++;
    }
    final p5 = _percentileFromHist(lumaHist, total, 0.05);
    final p95 = _percentileFromHist(lumaHist, total, 0.95);
    var dark = 0, light = 0;
    for (var i = 0; i < total; i++) {
      if (luma[i] < 64) dark++;
      if (luma[i] > 192) light++;
    }

    final bw = math.max(1, (math.min(dw, dh) * 0.08).round());
    final borderLuma = <double>[];
    for (var y = 0; y < dh; y++) {
      for (var x = 0; x < dw; x++) {
        if (x < bw || y < bw || x >= dw - bw || y >= dh - bw) {
          borderLuma.add(luma[y * dw + x]);
        }
      }
    }
    final backgroundUniformity = _stdDev(borderLuma);

    return ImageFeatures(
      width: w,
      height: h,
      megapixels: w * h / 1000000,
      aspectRatio: w / h,
      quantizedColors: quantizedColors,
      paletteShare8: paletteShare8,
      dominantShare: dominantShare,
      edgeDensity: edgeDensity,
      meanGradient: meanGradient,
      flatShare: flatShare,
      noiseLevel: noiseLevel,
      colorfulness: colorfulness,
      transparentShare: transparent / total,
      luminanceSpread: (p95 - p5).toDouble(),
      darkShare: dark / total,
      lightShare: light / total,
      backgroundUniformity: backgroundUniformity,
    );
  }

  static double _colorfulness(Float64List rg, Float64List yb, int n) {
    double sumRg = 0, sumYb = 0, sumRg2 = 0, sumYb2 = 0;
    for (var i = 0; i < n; i++) {
      sumRg += rg[i];
      sumYb += yb[i];
      sumRg2 += rg[i] * rg[i];
      sumYb2 += yb[i] * yb[i];
    }
    final meanRg = sumRg / n, meanYb = sumYb / n;
    final sdRg = math.sqrt(math.max(0, sumRg2 / n - meanRg * meanRg));
    final sdYb = math.sqrt(math.max(0, sumYb2 / n - meanYb * meanYb));
    final rootMeanSquare = math.sqrt(sdRg * sdRg + sdYb * sdYb);
    final meanRoot = math.sqrt(meanRg * meanRg + meanYb * meanYb);
    return rootMeanSquare + 0.3 * meanRoot;
  }

  static int _percentileFromHist(Int32List hist, int total, double p) {
    var acc = 0;
    final target = (total * p).round();
    for (var i = 0; i < hist.length; i++) {
      acc += hist[i];
      if (acc >= target) return (i * 8) + 4;
    }
    return 255;
  }

  static double _stdDev(List<double> values) {
    if (values.isEmpty) return 0;
    var mean = 0.0;
    for (final v in values) {
      mean += v;
    }
    mean /= values.length;
    var variance = 0.0;
    for (final v in values) {
      variance += (v - mean) * (v - mean);
    }
    return math.sqrt(variance / values.length);
  }
}
