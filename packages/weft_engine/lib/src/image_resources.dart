import 'package:flutter/painting.dart';

/// A request for one document image. The host decides whether and how the
/// resource can be loaded; the engine never performs implicit network I/O.
final class WeftImageRequest {
  /// Creates a request describing one image occurrence in a document.
  const WeftImageRequest({
    required this.documentId,
    required this.nodeId,
    required this.src,
    required this.alt,
  });

  /// Id of the document containing the image.
  final String documentId;

  /// Id of the `img` element that requested the image.
  final int nodeId;

  /// Raw source attribute as written in the document.
  final String src;

  /// Alternative text painted when the image cannot be resolved.
  final String alt;
}

/// Resolves an image source to a Flutter [ImageProvider].
///
/// Returning `null` leaves the image unresolved and lets the layout render its
/// alternative text. A resolver should apply the host's own URL allowlist,
/// caching, authentication, and resource-size policies.
typedef WeftImageResolver = ImageProvider<Object>? Function(
  WeftImageRequest request,
);
