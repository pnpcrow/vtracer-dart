import 'package:visioncortex/visioncortex.dart';


import '../ir.dart';
import '../progress.dart';

/// A frontend segments a raster image into ordered paint layers.
abstract class Frontend {
  Segmentation segment(ColorImage img);

  /// Progress- and cancellation-aware segmentation.
  ///
  /// The default runs [segment] then reports completion. Frontends that can
  /// step incrementally — like the color-cluster frontend — override this to
  /// report fine-grained progress and observe cancellation between batches.
  Segmentation segmentWith(ColorImage img, Ctx ctx) {
    final seg = segment(img);
    ctx.check();
    ctx.report(Phase.segment, 1.0);
    return seg;
  }

  /// Cooperative variant of [segmentWith]: yields to the event loop between
  /// work batches so a UI stays responsive without worker threads (works on
  /// platforms without isolates, e.g. Flutter web). The default wraps the
  /// synchronous path with a yield.
  Future<Segmentation> segmentWithAsync(ColorImage img, Ctx ctx) async {
    await Future<void>.delayed(Duration.zero);
    return segmentWith(img, ctx);
  }
}
