import 'runtime_contracts.dart';

/// Declares what a [CapabilityModule] offers: its namespace, API version, and
/// method set.
final class CapabilityDescriptor {
  /// Creates a descriptor; the method set is captured unmodifiable.
  CapabilityDescriptor({
    required this.namespace,
    required this.apiVersion,
    required Iterable<String> methods,
  })  : assert(apiVersion > 0),

        /// Stored unmodifiable so a registered module cannot change its
        /// surface after registration.
        methods = Set<String>.unmodifiable(methods);

  /// Namespace the module answers on, for example `weft.net`.
  final String namespace;

  /// Monotonic API version of the namespace's method surface.
  final int apiVersion;

  /// Method names the module implements; the gateway rejects anything else.
  final Set<String> methods;
}

/// Implementation of one capability namespace behind the bridge.
///
/// The gateway invokes [invoke] only for calls whose namespace the policy
/// enables and whose method the [descriptor] advertises.
abstract interface class CapabilityModule {
  /// The descriptor this module is registered and validated against.
  CapabilityDescriptor get descriptor;

  /// Handles one [BridgeCall] and resolves with the JSON-compatible result.
  Future<JsValue> invoke(BridgeCall call);
}
