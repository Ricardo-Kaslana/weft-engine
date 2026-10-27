import 'package:weft_runtime_api/weft_runtime_api.dart';

/// Injection seam for session creation: hosts and tests supply their own
/// [JsSession] source while the standard [JsRuntimeBackend] wiring stays
/// unchanged.
abstract interface class QuickJsNativeAdapter {
  /// Opens one QuickJS-backed session for [config], routing capability
  /// calls through [bridge].
  Future<JsSession> open(RuntimeConfig config, BridgeDispatcher bridge);
}

/// [JsRuntimeBackend] that forwards every `open` to [nativeAdapter].
///
/// The indirection lets tests drive the QuickJS wiring with a scripted
/// adapter while production code binds the FFI-backed session.
final class QuickJsRuntimeBackend implements JsRuntimeBackend {
  /// Creates a backend that delegates session creation to [nativeAdapter].
  const QuickJsRuntimeBackend(this.nativeAdapter);

  /// Session factory every [JsRuntimeBackend.open] call is delegated to.
  final QuickJsNativeAdapter nativeAdapter;

  @override
  Future<JsSession> open(RuntimeConfig config, BridgeDispatcher bridge) {
    return nativeAdapter.open(config, bridge);
  }
}
