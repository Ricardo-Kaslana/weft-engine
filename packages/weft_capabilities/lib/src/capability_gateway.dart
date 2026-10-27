import 'package:weft_runtime_api/weft_runtime_api.dart';

import 'capability_policy.dart';

import 'capability_errors.dart';

/// One settled bridge exchange, retained for dedup across recovery.
final class BridgeJournalEntry {
  const BridgeJournalEntry({required this.call, required this.result});

  final BridgeCall call;
  final JsValue result;
}

/// Routes bridge calls to capability modules and enforces the loadout policy.
///
/// Guarantees (ADR 0033):
/// - only enabled namespaces reach modules — disabled capabilities are
///   rejected with [WeftCapabilityDenied] and stay invisible to scripts;
/// - unknown methods are rejected against the module descriptor;
/// - every settled call is recorded; a re-delivered `(sessionId, sequence)`
///   pair returns the recorded result **without** invoking the module again,
///   which is what makes network side effects idempotent across recovery.
final class CapabilityGateway implements BridgeDispatcher {
  CapabilityGateway({
    required CapabilityPolicy policy,
    required Map<String, CapabilityModule> modules,
    this.journalCapacity = 256,
  })  : _policy = policy,
        _modules = Map<String, CapabilityModule>.unmodifiable(modules) {
    for (final namespace in _modules.keys) {
      if (!_policy.isEnabled(namespace)) {
        throw ArgumentError.value(
          modules,
          'modules',
          'Module "$namespace" is installed but not enabled by the policy; '
              'unloaded capabilities must stay invisible.',
        );
      }
    }
  }

  final CapabilityPolicy _policy;
  final Map<String, CapabilityModule> _modules;
  final int journalCapacity;

  final Map<String, BridgeJournalEntry> _journal =
      <String, BridgeJournalEntry>{};

  CapabilityPolicy get policy => _policy;

  /// All settled calls in insertion order (oldest first).
  List<BridgeJournalEntry> get journal => List.unmodifiable(_journal.values);

  /// Whether this exact exchange has already settled.
  bool hasSeen(String sessionId, int sequence) =>
      _journal.containsKey(_key(sessionId, sequence));

  @override
  Future<JsValue> dispatch(BridgeCall call) async {
    final key = _key(call.sessionId, call.sequence);
    final recorded = _journal[key];
    if (recorded != null) {
      return recorded.result;
    }

    if (!_policy.isEnabled(call.capability)) {
      throw WeftCapabilityDenied(
        call.capability,
        'Capability "${call.capability}" is not enabled for this document.',
      );
    }
    final module = _modules[call.capability];
    if (module == null) {
      throw WeftCapabilityDenied(
        call.capability,
        'Capability "${call.capability}" is enabled but no module is '
        'installed for it.',
      );
    }
    if (!module.descriptor.methods.contains(call.method)) {
      throw WeftCapabilityDenied(
        call.capability,
        'Method "${call.method}" is not offered by '
        '${call.capability} v${module.descriptor.apiVersion}.',
      );
    }

    final result = await module.invoke(call);
    _record(BridgeJournalEntry(call: call, result: result));
    return result;
  }

  void _record(BridgeJournalEntry entry) {
    _journal[_key(entry.call.sessionId, entry.call.sequence)] = entry;
    while (_journal.length > journalCapacity) {
      _journal.remove(_journal.keys.first);
    }
  }

  String _key(String sessionId, int sequence) => '$sessionId#$sequence';
}
