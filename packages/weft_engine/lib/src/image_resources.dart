import 'package:flutter/painting.dart';

/// A request for one document image. The host decides whether and how the
/// resource can be loaded; the engine never performs implicit network I/O.
final class WeftImageRequest {
  const WeftImageRequest({
    required this.documentId,
    required this.nodeId,
    required this.src,
    required this.alt,
  });

  final String documentId;
  final int nodeId;
  final String src;
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
