import 'dart:convert';

/// Resource caps for values crossing the JS/Dart bridge in both directions.
///
/// Every backend applies the same caps to the same three crossings — bridge
/// call arguments (JS to Dart), capability results (Dart to JS) and event
/// payloads (host to JS) — using [checkValue], so a message a script can send
/// is a message every backend rejects identically. A value past a cap must be
/// rejected with [RuntimeFailureKind.bridgeLimit] before it reaches the
/// dispatcher; the caps bound decode, dispatch and journal work, not the
/// transient copy (the request direction materializes its string under the
/// engine heap budget first, ADR 0055).
final class BridgeLimits {
  /// Creates limits; every cap must be positive.
  const BridgeLimits({
    this.maxMessageBytes = 256 * 1024,
    this.maxDepth = 32,
    this.maxInflightCalls = 256,
  })  : assert(maxMessageBytes > 0),
        assert(maxDepth > 0),
        assert(maxInflightCalls > 0);

  /// UTF-8 byte ceiling for one message's JSON encoding.
  final int maxMessageBytes;

  /// Maximum Map/List nesting depth of one message.
  final int maxDepth;

  /// Maximum number of concurrently unsettled capability dispatches one
  /// session may hold; further calls are rejected without being queued.
  final int maxInflightCalls;

  /// Checks [value] against the message caps; returns the first violation or
  /// null when the value fits.
  ///
  /// Depth is checked first because it is a cheap walk; bytes are measured on
  /// the JSON encoding. Values that are not JSON-compatible throw from
  /// `jsonEncode` as before — the typedef contract already requires
  /// JSON-compatible values.
  BridgeLimitViolation? checkValue(Object? value) {
    return _checkDepth(value, 0) ?? _checkBytes(value);
  }

  BridgeLimitViolation? _checkDepth(Object? value, int depth) {
    if (value is Map<Object?, Object?>) {
      if (depth >= maxDepth) {
        return BridgeLimitViolation(
            limitName: 'maxDepth', actual: depth, limit: maxDepth);
      }
      for (final child in value.values) {
        final violation = _checkDepth(child, depth + 1);
        if (violation != null) {
          return violation;
        }
      }
    } else if (value is List<Object?>) {
      if (depth >= maxDepth) {
        return BridgeLimitViolation(
            limitName: 'maxDepth', actual: depth, limit: maxDepth);
      }
      for (final child in value) {
        final violation = _checkDepth(child, depth + 1);
        if (violation != null) {
          return violation;
        }
      }
    }
    return null;
  }

  BridgeLimitViolation? _checkBytes(Object? value) {
    final bytes = utf8.encode(jsonEncode(value)).length;
    if (bytes > maxMessageBytes) {
      return BridgeLimitViolation(
          limitName: 'maxMessageBytes', actual: bytes, limit: maxMessageBytes);
    }
    return null;
  }
}

/// Why a value crossed a [BridgeLimits] cap.
final class BridgeLimitViolation {
  /// Creates a violation; [limitName] names the tripped cap.
  const BridgeLimitViolation({
    required this.limitName,
    required this.actual,
    required this.limit,
  });

  /// The tripped cap: `maxMessageBytes` or `maxDepth`.
  final String limitName;

  /// Measured size of the rejected value.
  final int actual;

  /// Configured cap the value ran past.
  final int limit;

  /// Structured message for the [RuntimeFailureKind.bridgeLimit] failure.
  String get message => 'Bridge message $limitName exceeded: $actual > $limit.';
}
