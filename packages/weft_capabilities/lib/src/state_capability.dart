import 'package:weft_runtime_api/weft_runtime_api.dart';

import 'capability_errors.dart';
import 'capability_policy.dart';

/// Host-provided storage behind the `weft.state` capability.
///
/// The store is scoped to one document runtime; the engine never persists it
/// or shares it across documents.
abstract interface class WeftStateStore {
  /// Returns the value stored for [key], or null when absent.
  JsValue? get(String key);

  /// Stores [value] under [key], replacing any previous entry.
  void set(String key, JsValue value);
}

/// In-memory store used by tests and as a host default.
final class MemoryWeftStateStore implements WeftStateStore {
  final Map<String, JsValue> _values = <String, JsValue>{};

  @override
  JsValue? get(String key) => _values[key];

  @override
  void set(String key, JsValue value) => _values[key] = value;
}

/// `weft.state`: per-document key/value state for scripts.
///
/// Methods: `get(key)`, `set(key, value)`. Values must be JSON-compatible.
final class StateCapabilityModule implements CapabilityModule {
  /// Creates the module backed by [store].
  StateCapabilityModule({required this.store});

  /// Namespace this module answers on: [WeftCapabilityIds.state].
  static const namespace = WeftCapabilityIds.state;

  /// Storage backing every get and set for this document runtime.
  final WeftStateStore store;

  @override
  CapabilityDescriptor get descriptor => CapabilityDescriptor(
        namespace: namespace,
        apiVersion: 1,
        methods: const {'get', 'set'},
      );

  @override
  Future<JsValue> invoke(BridgeCall call) async {
    switch (call.method) {
      case 'get':
        _requireArity(call, 1);
        return store.get(call.arguments[0] as String? ?? '');
      case 'set':
        _requireArity(call, 2);
        final key = call.arguments[0] as String?;
        if (key == null) {
          throw WeftCapabilityDenied(
              namespace, 'weft.state.set requires a string key.');
        }
        store.set(key, call.arguments[1]);
        return null;
      default:
        throw WeftCapabilityDenied(
          namespace,
          'Unknown weft.state method "${call.method}".',
        );
    }
  }

  void _requireArity(BridgeCall call, int count) {
    if (call.arguments.length < count) {
      throw WeftCapabilityDenied(
        namespace,
        'weft.state.${call.method} requires $count argument(s).',
      );
    }
  }
}
