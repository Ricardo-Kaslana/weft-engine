/// Thrown by the capability gateway when a bridge call cannot be routed.
///
/// The owning session resolves the JS-side promise with the message, so the
/// script observes an `Error` carrying this text.
final class WeftCapabilityDenied implements Exception {
  /// Creates a denial naming the [capability] and a script-visible [message].
  WeftCapabilityDenied(this.capability, this.message);

  /// Namespace the denied call targeted.
  final String capability;

  /// Rejection reason; the script observes it as the thrown `Error` text.
  final String message;

  @override
  String toString() => 'WeftCapabilityDenied($capability): $message';
}

/// Thrown by the network capability when a URL or redirect violates the
/// configured [WeftNetworkPolicy].
final class WeftNetworkPolicyError implements Exception {
  /// Creates a violation with a human-readable [message].
  WeftNetworkPolicyError(this.message);

  /// Human-readable description of the violated rule.
  final String message;

  @override
  String toString() => 'WeftNetworkPolicyError: $message';
}
