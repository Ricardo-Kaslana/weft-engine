import 'package:weft_runtime_api/weft_runtime_api.dart';

import 'capability_errors.dart';
import 'capability_policy.dart';

/// URL rules enforced by the network capability before any host client runs.
///
/// V1 semantics (ADR 0033):
/// - the scheme must be listed in [allowedSchemes];
/// - the host must appear verbatim in [allowedHosts]; an empty set allows no
///   hosts at all;
/// - every redirect hop the client reports is validated the same way, so a
///   redirect that leaves the whitelist fails the request instead of
///   delivering its body.
final class WeftNetworkPolicy {
  /// Creates a policy; schemes must be lowercase, and an empty host whitelist
  /// allows no requests at all.
  WeftNetworkPolicy({
    this.allowedSchemes = const {'https'},
    this.allowedHosts = const <String>{},
    this.maxResponseBytes = 1 << 20,
    this.maxRedirects = 5,
  }) {
    for (final scheme in allowedSchemes) {
      if (scheme != scheme.toLowerCase()) {
        throw ArgumentError.value(
            allowedSchemes, 'allowedSchemes', 'Schemes must be lowercase.');
      }
    }
  }

  /// URL schemes a request may use; defaults to HTTPS only.
  final Set<String> allowedSchemes;

  /// Exact hostnames a request may target; empty allows nothing.
  final Set<String> allowedHosts;

  /// Largest accepted response body; larger bodies fail the fetch.
  final int maxResponseBytes;

  /// Maximum redirect hops a response may report.
  final int maxRedirects;

  /// Validates one URL hop; throws [WeftNetworkPolicyError] on violation.
  void validate(Uri uri, {String? context}) {
    final scheme = uri.scheme.toLowerCase();
    if (!allowedSchemes.contains(scheme)) {
      throw WeftNetworkPolicyError(
        '${context ?? 'URL'} scheme "$scheme" is not allowed '
        '(allowed: ${allowedSchemes.join(', ')}).',
      );
    }
    final host = uri.host.toLowerCase();
    if (!allowedHosts.contains(host)) {
      throw WeftNetworkPolicyError(
        '${context ?? 'URL'} host "$host" is not in the whitelist.',
      );
    }
  }

  /// Non-throwing form of [validate]: true when [uri] passes the policy.
  bool allows(Uri uri) {
    try {
      validate(uri);
      return true;
    } on WeftNetworkPolicyError {
      return false;
    }
  }
}

/// A single-hop request the capability passes to the host client.
final class WeftNetworkRequest {
  /// Creates a request; defaults to a GET with no headers.
  const WeftNetworkRequest({
    required this.url,
    this.method = 'GET',
    this.headers = const <String, String>{},
  });

  /// URL to request; the capability validates it against the policy first.
  final Uri url;

  /// HTTP method; v1 issues GET only.
  final String method;

  /// Request headers; defaults to empty.
  final Map<String, String> headers;
}

/// Host client response. [redirectChain] must list every URL the client
/// followed (in order, including the initial URL when it redirected); the
/// capability validates each hop against the policy.
final class WeftNetworkResponse {
  /// Creates a response; fields other than [status] and [body] default empty.
  const WeftNetworkResponse({
    required this.status,
    required this.body,
    this.headers = const <String, String>{},
    this.redirectChain = const <Uri>[],
  });

  /// HTTP status code reported by the host client.
  final int status;

  /// Response headers; defaults to empty.
  final Map<String, String> headers;

  /// Response body as text; checked against the policy's size limit.
  final String body;

  /// Every URL the client followed, in order; each hop is re-validated.
  final List<Uri> redirectChain;
}

/// Host-provided HTTP transport. The engine never creates sockets or HTTP
/// clients itself; hosts inject their own client with their own auth and
/// caching.
abstract interface class WeftNetworkClient {
  /// Performs [request] and resolves with the response; implementations must
  /// report every redirect hop so the capability can validate each one.
  Future<WeftNetworkResponse> request(WeftNetworkRequest request);
}

/// Lifecycle stage recorded for one fetch in the [WeftNetworkJournal].
enum WeftNetworkOutcome { requested, completed, blocked, failed }

/// Audit record of one network side effect. Entries survive recovery so the
/// orchestrator can prove that no request is silently replayed and hosts can
/// reconcile side effects after a crash.
final class WeftNetworkJournalEntry {
  /// Creates an entry describing one fetch attempt.
  const WeftNetworkJournalEntry({
    required this.sessionId,
    required this.sequence,
    required this.url,
    required this.outcome,
    this.detail,
  });

  /// Session that issued the fetch.
  final String sessionId;

  /// Bridge call sequence pairing this entry with its gateway exchange.
  final int sequence;

  /// Requested URL, or the final URL for a completed redirect chain.
  final String url;

  /// What happened to the request.
  final WeftNetworkOutcome outcome;

  /// Optional context such as the failure reason or response status.
  final String? detail;
}

/// In-memory audit log of network side effects for one document runtime.
///
/// Hosts persist these entries across recovery so a settled fetch is never
/// silently replayed after a crash.
final class WeftNetworkJournal {
  final List<WeftNetworkJournalEntry> _entries = <WeftNetworkJournalEntry>[];

  /// All recorded entries in order, oldest first.
  List<WeftNetworkJournalEntry> get entries => List.unmodifiable(_entries);

  /// Number of entries whose outcome is [WeftNetworkOutcome.completed].
  int get completedCount => _entries
      .where((entry) => entry.outcome == WeftNetworkOutcome.completed)
      .length;

  /// Appends one entry to the log.
  void record(WeftNetworkJournalEntry entry) => _entries.add(entry);
}

/// `weft.net`: whitelisted, audited fetch for scripts.
///
/// Methods: `fetch(url, options?)` — GET only in v1. Resolves with
/// `{status, body, url}`.
final class NetworkCapabilityModule implements CapabilityModule {
  /// Creates the module; a fresh journal is created when none is injected.
  NetworkCapabilityModule({
    required this.client,
    required this.policy,
    WeftNetworkJournal? journal,
  }) : journal = journal ?? WeftNetworkJournal();

  /// Namespace this module answers on: [WeftCapabilityIds.network].
  static const namespace = WeftCapabilityIds.network;

  /// Host transport used for every fetch.
  final WeftNetworkClient client;

  /// URL and response rules validated before and after the client runs.
  final WeftNetworkPolicy policy;

  /// Audit log receiving one entry per fetch attempt.
  final WeftNetworkJournal journal;

  @override
  CapabilityDescriptor get descriptor => CapabilityDescriptor(
        namespace: namespace,
        apiVersion: 1,
        methods: const {'fetch'},
      );

  @override
  Future<JsValue> invoke(BridgeCall call) async {
    if (call.method != 'fetch') {
      throw WeftCapabilityDenied(
        namespace,
        'Unknown weft.net method "${call.method}".',
      );
    }
    if (call.arguments.isEmpty || call.arguments.first is! String) {
      throw WeftCapabilityDenied(
          namespace, 'weft.net.fetch requires a string URL.');
    }
    final rawUrl = call.arguments.first as String;
    final Uri url;
    try {
      url = Uri.parse(rawUrl);
    } on FormatException {
      throw WeftNetworkPolicyError('URL "$rawUrl" could not be parsed.');
    }
    try {
      policy.validate(url, context: 'fetch');
    } on WeftNetworkPolicyError catch (error) {
      journal.record(WeftNetworkJournalEntry(
        sessionId: call.sessionId,
        sequence: call.sequence,
        url: rawUrl,
        outcome: WeftNetworkOutcome.blocked,
        detail: error.message,
      ));
      rethrow;
    }
    if (url.host.isEmpty) {
      throw WeftNetworkPolicyError('URL "$rawUrl" has no host.');
    }
    journal.record(WeftNetworkJournalEntry(
      sessionId: call.sessionId,
      sequence: call.sequence,
      url: rawUrl,
      outcome: WeftNetworkOutcome.requested,
    ));

    final WeftNetworkResponse response;
    try {
      response = await client.request(WeftNetworkRequest(url: url));
    } catch (error) {
      journal.record(WeftNetworkJournalEntry(
        sessionId: call.sessionId,
        sequence: call.sequence,
        url: rawUrl,
        outcome: WeftNetworkOutcome.failed,
        detail: error.toString(),
      ));
      throw WeftNetworkPolicyError('fetch failed: $error');
    }

    if (response.redirectChain.length > policy.maxRedirects + 1) {
      journal.record(WeftNetworkJournalEntry(
        sessionId: call.sessionId,
        sequence: call.sequence,
        url: rawUrl,
        outcome: WeftNetworkOutcome.blocked,
        detail: 'too many redirects',
      ));
      throw WeftNetworkPolicyError(
        'Redirect chain of ${response.redirectChain.length - 1} hops '
        'exceeds the limit of ${policy.maxRedirects}.',
      );
    }
    for (final hop in response.redirectChain) {
      policy.validate(hop, context: 'redirect');
    }
    if (response.body.length > policy.maxResponseBytes) {
      throw WeftNetworkPolicyError(
        'Response body of ${response.body.length} bytes exceeds the '
        '${policy.maxResponseBytes} byte limit.',
      );
    }
    final finalUrl = response.redirectChain.isEmpty
        ? url.toString()
        : response.redirectChain.last.toString();
    journal.record(WeftNetworkJournalEntry(
      sessionId: call.sessionId,
      sequence: call.sequence,
      url: finalUrl,
      outcome: WeftNetworkOutcome.completed,
      detail: 'status ${response.status}',
    ));
    return <String, JsValue>{
      'status': response.status,
      'body': response.body,
      'url': finalUrl,
    };
  }
}
