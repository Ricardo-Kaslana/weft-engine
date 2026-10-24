import 'package:weft_runtime_api/weft_runtime_api.dart';

abstract interface class QuickJsNativeAdapter {
  Future<JsSession> open(RuntimeConfig config, BridgeDispatcher bridge);
}

final class QuickJsRuntimeBackend implements JsRuntimeBackend {
  const QuickJsRuntimeBackend(this.nativeAdapter);

  final QuickJsNativeAdapter nativeAdapter;

  @override
  Future<JsSession> open(RuntimeConfig config, BridgeDispatcher bridge) {
    return nativeAdapter.open(config, bridge);
  }
}
