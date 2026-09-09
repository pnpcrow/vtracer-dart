/// Errors produced by the framework stages and the pipeline driver.
sealed class VtracerError implements Exception {
  const VtracerError();

  @override
  String toString() {
    return switch (this) {
      EmptyImageError() => 'input image is empty',
      NoKeyColorError() => 'unable to find an unused color in image to use as key',
      UnsupportedError(:final what) => 'unsupported: $what',
      CancelledError() => 'conversion cancelled',
      OtherError(:final message) => message,
    };
  }
}

class EmptyImageError extends VtracerError {
  const EmptyImageError();
}

class NoKeyColorError extends VtracerError {
  const NoKeyColorError();
}

class UnsupportedError extends VtracerError {
  final String what;
  const UnsupportedError(this.what);
}

class CancelledError extends VtracerError {
  const CancelledError();
}

class OtherError extends VtracerError {
  final String message;
  const OtherError(this.message);
}
