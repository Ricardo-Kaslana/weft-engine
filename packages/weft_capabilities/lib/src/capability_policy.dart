/// Namespace identifiers and the default loadout of the built-in
/// capabilities.
abstract final class WeftCapabilityIds {
  /// Namespace of the per-document key/value capability.
  static const state = 'weft.state';

  /// Namespace of the script-to-host event capability.
  static const events = 'weft.events';

  /// Namespace of the whitelisted fetch capability.
  static const network = 'weft.net';

  /// The set of capabilities shipped with the engine.
  static const builtIn = <String>{state, events, network};
}

/// Which capability namespaces a document's scripts may call.
///
/// The gateway consults this before routing every bridge call; disabled
/// namespaces are rejected and stay invisible to scripts.
final class CapabilityPolicy {
  /// Creates a policy enabling exactly [enabled]; an empty set means no
  /// capabilities.
  CapabilityPolicy({Iterable<String> enabled = const []})
      : enabledNamespaces = Set<String>.unmodifiable(enabled) {
    if (enabledNamespaces.any((namespace) => namespace.trim().isEmpty)) {
      throw ArgumentError.value(
          enabled, 'enabled', 'Namespace cannot be empty.');
    }
  }

  /// Unmodifiable set of enabled namespace identifiers.
  final Set<String> enabledNamespaces;

  /// Whether [namespace] may be called from scripts.
  bool isEnabled(String namespace) => enabledNamespaces.contains(namespace);
}
