import 'package:weft_runtime_api/weft_runtime_api.dart';

import 'capability_errors.dart';
import 'capability_policy.dart';

/// `weft.events`: scripts emit named events to the host.
///
/// Methods: `emit(name, payload)`. Delivery into JS (host -> script) is the
/// runtime's [send] path handled by the bootstrap `__weftOnEvent` dispatcher.
final class EventsCapabilityModule implements CapabilityModule {
  EventsCapabilityModule({required this.onEmit});

  static const namespace = WeftCapabilityIds.events;

  final void Function(String name, Map<String, JsValue> payload) onEmit;

  @override
  CapabilityDescriptor get descriptor => CapabilityDescriptor(
        namespace: namespace,
        apiVersion: 1,
        methods: const {'emit'},
      );

  @override
  Future<JsValue> invoke(BridgeCall call) async {
    if (call.method != 'emit') {
      throw WeftCapabilityDenied(
        namespace,
        'Unknown weft.events method "${call.method}".',
      );
    }
    if (call.arguments.isEmpty) {
      throw WeftCapabilityDenied(
          namespace, 'weft.events.emit requires a name.');
    }
    final name = call.arguments[0] as String?;
    if (name == null || name.isEmpty) {
      throw WeftCapabilityDenied(
          namespace, 'weft.events.emit requires a non-empty string name.');
    }
    final rawPayload = call.arguments.length > 1 ? call.arguments[1] : null;
    Map<String, JsValue> payload;
    if (rawPayload == null) {
      payload = <String, JsValue>{};
    } else if (rawPayload is Map<String, JsValue>) {
      payload = rawPayload;
    } else {
      throw WeftCapabilityDenied(
          namespace, 'weft.events.emit payload must be an object.');
    }
    onEmit(name, payload);
    return null;
  }
}
