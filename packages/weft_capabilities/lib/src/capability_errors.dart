/// Thrown by the capability gateway when a bridge call cannot be routed.
///
/// The owning session resolves the JS-side promise with the message, so the
/// script observes an `Error` carrying this text.
final class WeftCapabilityDenied implements Exception {
  WeftCapabilityDenied(this.capability, this.message);

  final String capability;
  final String message;

  @override
  String toString() => 'WeftCapabilityDenied($capability): $message';
}

/// Thrown by the network capability when a URL or redirect violates the
/// configured [WeftNetworkPolicy].
final class WeftNetworkPolicyError implements Exception {
  WeftNetworkPolicyError(this.message);

  final String message;

  @override
  String toString() => 'WeftNetworkPolicyError: $message';
}
