abstract final class WeftCapabilityIds {
  static const state = 'weft.state';
  static const events = 'weft.events';
  static const network = 'weft.net';

  static const builtIn = <String>{state, events, network};
}

final class CapabilityPolicy {
  CapabilityPolicy({Iterable<String> enabled = const []})
      : enabledNamespaces = Set<String>.unmodifiable(enabled) {
    if (enabledNamespaces.any((namespace) => namespace.trim().isEmpty)) {
      throw ArgumentError.value(
          enabled, 'enabled', 'Namespace cannot be empty.');
    }
  }

  final Set<String> enabledNamespaces;

  bool isEnabled(String namespace) => enabledNamespaces.contains(namespace);
}
