import 'package:weft_runtime_api/weft_runtime_api.dart';

import 'capability_policy.dart';

/// Generates the session bootstrap that turns the raw `__weftBridge` native
/// function into the `weft.*` API surface.
///
/// Visibility rule: a namespace only gets a JS object when its capability is
/// enabled — `typeof weft.net` is `'undefined'` unless `weft.net` is enabled,
/// and the gateway rejects stray calls as a second line of defense.
ScriptUnit weftCapabilityBootstrap(Iterable<String> enabledNamespaces) {
  final enabled = enabledNamespaces.toSet();
  return ScriptUnit(
    id: 'weft/bootstrap',
    source: _bootstrapSource(enabled),
    sourceUrl: Uri.parse('weft:bootstrap'),
  );
}

const String _bootstrapPrelude = '''
(function (global) {
  'use strict';
  var enabled = __WEFT_ENABLED__;
  function call(ns, method, args) {
    return __weftBridge(ns, method, JSON.stringify(args)).then(
      function (reply) { return reply; },
      function (failure) {
        throw new Error(
          failure && failure.message ? failure.message : String(failure));
      });
  }
  var weft = { bridgeVersion: 1 };
''';

const String _bootstrapState = '''
  if (enabled.indexOf('weft.state') !== -1) {
    weft.state = {
      get: function (key) { return call('weft.state', 'get', [String(key)]); },
      set: function (key, value) {
        return call('weft.state', 'set', [String(key), value === undefined ? null : value]);
      }
    };
  }
''';

const String _bootstrapEvents = '''
  if (enabled.indexOf('weft.events') !== -1) {
    var eventHandlers = {};
    weft.events = {
      emit: function (name, payload) {
        return call('weft.events', 'emit',
          [String(name), payload == null ? {} : payload]);
      },
      on: function (name, handler) {
        if (typeof handler !== 'function') {
          throw new TypeError('weft.events.on requires a handler function');
        }
        var list = eventHandlers[name] = eventHandlers[name] || [];
        list.push(handler);
        return function () {
          var current = eventHandlers[name] || [];
          var index = current.indexOf(handler);
          if (index !== -1) { current.splice(index, 1); }
        };
      }
    };
    global.__weftOnEvent = function (event) {
      var list = (eventHandlers[event.name] || []).slice();
      for (var i = 0; i < list.length; i++) { list[i](event.payload); }
    };
  }
''';

const String _bootstrapNetwork = '''
  if (enabled.indexOf('weft.net') !== -1) {
    weft.net = {
      fetch: function (url, options) {
        return call('weft.net', 'fetch', [String(url), options || {}]);
      }
    };
  }
''';

const String _bootstrapEpilogue = '''
  global.weft = weft;
})(globalThis);
''';

String _bootstrapSource(Set<String> enabled) {
  final list = enabled.map((namespace) => "'$namespace'").join(', ');
  final buffer = StringBuffer(_bootstrapPrelude.replaceFirst(
    '__WEFT_ENABLED__',
    '[$list]',
  ));
  if (enabled.contains(WeftCapabilityIds.state)) {
    buffer.write(_bootstrapState);
  }
  if (enabled.contains(WeftCapabilityIds.events)) {
    buffer.write(_bootstrapEvents);
  }
  if (enabled.contains(WeftCapabilityIds.network)) {
    buffer.write(_bootstrapNetwork);
  }
  buffer.write(_bootstrapEpilogue);
  return buffer.toString();
}
