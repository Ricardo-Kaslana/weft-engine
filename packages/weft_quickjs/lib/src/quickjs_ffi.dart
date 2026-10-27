import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Opaque handle to the C-side `WeftRuntime` struct declared in
/// `native/weft_glue.c`.
final class WeftRuntimeFfi extends Opaque {}

typedef _BridgeNotifyNative = Void Function(Pointer<Utf8>, Pointer<Void>);

typedef _NewRuntimeNative = Pointer<WeftRuntimeFfi> Function(Size, Size);
typedef _NewRuntimeDart = Pointer<WeftRuntimeFfi> Function(int, int);

typedef _SetDeadlineNative = Void Function(Pointer<WeftRuntimeFfi>, Double);
typedef _SetDeadlineDart = void Function(Pointer<WeftRuntimeFfi>, double);

typedef _NowNative = Double Function();
typedef _NowDart = double Function();

typedef _EvalNative = Pointer<Utf8> Function(
    Pointer<WeftRuntimeFfi>, Pointer<Utf8>, Size, Pointer<Utf8>);
typedef _EvalDart = Pointer<Utf8> Function(
    Pointer<WeftRuntimeFfi>, Pointer<Utf8>, int, Pointer<Utf8>);

typedef _PumpJobsNative = Int32 Function(
    Pointer<WeftRuntimeFfi>, Int32, Pointer<Int32>, Pointer<Pointer<Utf8>>);
typedef _PumpJobsDart = int Function(
    Pointer<WeftRuntimeFfi>, int, Pointer<Int32>, Pointer<Pointer<Utf8>>);

typedef _ResolveNative = Int32 Function(
    Pointer<WeftRuntimeFfi>, Uint64, Pointer<Utf8>, Int32);
typedef _ResolveDart = int Function(
    Pointer<WeftRuntimeFfi>, int, Pointer<Utf8>, int);

typedef _SendEventNative = Int32 Function(
    Pointer<WeftRuntimeFfi>, Pointer<Utf8>, Pointer<Pointer<Utf8>>);
typedef _SendEventDart = int Function(
    Pointer<WeftRuntimeFfi>, Pointer<Utf8>, Pointer<Pointer<Utf8>>);

typedef _InstallBridgeNative = Void Function(Pointer<WeftRuntimeFfi>,
    Pointer<NativeFunction<_BridgeNotifyNative>>, Pointer<Void>);
typedef _InstallBridgeDart = void Function(Pointer<WeftRuntimeFfi>,
    Pointer<NativeFunction<_BridgeNotifyNative>>, Pointer<Void>);

typedef _FreeRuntimeNative = Void Function(Pointer<WeftRuntimeFfi>);
typedef _FreeRuntimeDart = void Function(Pointer<WeftRuntimeFfi>);

typedef _FreeStringNative = Void Function(Pointer<Utf8>);
typedef _FreeStringDart = void Function(Pointer<Utf8>);

/// Status returned by [QuickJsNativeLibrary.pumpJobs] when a pending job threw.
const int kPumpJobError = -1;

/// Status returned by [QuickJsNativeLibrary.pumpJobs] when the microtask
/// budget stopped the pump before the job queue drained.
const int kPumpBudgetExceeded = 1;

/// Status returned by [QuickJsNativeLibrary.sendEvent] when no JS handler is
/// installed for host events.
const int kSendEventNoListener = 1;

/// Status returned by [QuickJsNativeLibrary.sendEvent] when the event payload
/// is not valid JSON.
const int kSendEventBadPayload = 2;

/// Status returned by [QuickJsNativeLibrary.sendEvent] when the JS handler
/// threw; the error envelope is written to the out parameter.
const int kSendEventHandlerThrew = 3;

/// Resolved `weft_new_runtime` bindings over the dynamic library.
final class QuickJsNativeLibrary {
  QuickJsNativeLibrary._(DynamicLibrary library)
      : newRuntime = library.lookupFunction<_NewRuntimeNative, _NewRuntimeDart>(
            'weft_new_runtime'),
        setDeadline =
            library.lookupFunction<_SetDeadlineNative, _SetDeadlineDart>(
                'weft_set_deadline'),
        nowMs = library.lookupFunction<_NowNative, _NowDart>('weft_now_ms'),
        eval = library.lookupFunction<_EvalNative, _EvalDart>('weft_eval'),
        pumpJobs = library
            .lookupFunction<_PumpJobsNative, _PumpJobsDart>('weft_pump_jobs'),
        resolve = library
            .lookupFunction<_ResolveNative, _ResolveDart>('weft_resolve'),
        sendEvent = library.lookupFunction<_SendEventNative, _SendEventDart>(
            'weft_send_event'),
        installBridge =
            library.lookupFunction<_InstallBridgeNative, _InstallBridgeDart>(
                'weft_install_bridge'),
        freeRuntime =
            library.lookupFunction<_FreeRuntimeNative, _FreeRuntimeDart>(
                'weft_free_runtime'),
        freeString = library.lookupFunction<_FreeStringNative, _FreeStringDart>(
            'weft_free_string');

  static QuickJsNativeLibrary? _instance;

  /// Loads the shared library once per process. [explicitPath] wins over the
  /// `WEFT_QUICKJS_LIBRARY` environment variable and the default search.
  static QuickJsNativeLibrary load({String? explicitPath}) {
    final cached = _instance;
    if (cached != null) {
      return cached;
    }
    final path = explicitPath ?? resolveLibraryPath();
    try {
      return _instance = QuickJsNativeLibrary._(DynamicLibrary.open(path));
    } catch (error) {
      throw StateError(
        'Unable to load the Weft QuickJS native library at "$path" ($error).\n'
        'Build it with: packages/weft_quickjs/tool/build_native.sh\n'
        'or point WEFT_QUICKJS_LIBRARY at an existing binary.',
      );
    }
  }

  /// Whether the native library can be loaded; used by tests to skip
  /// gracefully on machines without the build.
  static bool get isLoadable {
    try {
      load();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Candidate locations for the shared library, relative to the current
  /// directory. Covers running inside the package, from a sibling package,
  /// and from the workspace root.
  static List<String> defaultLibraryCandidates() {
    final name = Platform.isWindows ? 'weft_quickjs.dll' : 'libweft_quickjs.so';
    return <String>[
      'native/build/$name',
      '../weft_quickjs/native/build/$name',
      'packages/weft_quickjs/native/build/$name',
      'example/packages/weft_quickjs/native/build/$name',
    ];
  }

  static String resolveLibraryPath({String? explicitPath}) {
    final override =
        explicitPath ?? Platform.environment['WEFT_QUICKJS_LIBRARY'];
    if (override != null && override.trim().isNotEmpty) {
      return override;
    }
    for (final candidate in defaultLibraryCandidates()) {
      if (File(candidate).existsSync()) {
        return File(candidate).absolute.path;
      }
    }
    throw StateError(
      'Weft QuickJS native library not found. Looked in:\n'
      '${defaultLibraryCandidates().map((path) => '  - $path').join('\n')}\n'
      'Build it with: packages/weft_quickjs/tool/build_native.sh',
    );
  }

  final _NewRuntimeDart newRuntime;
  final _SetDeadlineDart setDeadline;
  final _NowDart nowMs;
  final _EvalDart eval;
  final _PumpJobsDart pumpJobs;
  final _ResolveDart resolve;
  final _SendEventDart sendEvent;
  final _InstallBridgeDart installBridge;
  final _FreeRuntimeDart freeRuntime;
  final _FreeStringDart freeString;
}
