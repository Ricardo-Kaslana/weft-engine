import 'runtime_contracts.dart';

final class CapabilityDescriptor {
  CapabilityDescriptor({
    required this.namespace,
    required this.apiVersion,
    required Iterable<String> methods,
  })  : assert(apiVersion > 0),
        methods = Set<String>.unmodifiable(methods);

  final String namespace;
  final int apiVersion;
  final Set<String> methods;
}

abstract interface class CapabilityModule {
  CapabilityDescriptor get descriptor;

  Future<JsValue> invoke(BridgeCall call);
}
