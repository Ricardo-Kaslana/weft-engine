// API doc coverage gate (ADR 0034).
//
//   dart run tool/doc_coverage.dart            # gate: exit 1 on gaps
//   dart run tool/doc_coverage.dart --report   # print gaps only
//
// Scans every library exported from each package entry point (following
// export/part directives) and requires a `///` doc comment on every public
// declaration: classes, enums, typedefs, extensions, top-level functions
// and variables, plus class members (constructors, methods, getters,
// fields). Private declarations and `@override` members are exempt.
//
// The gate keeps the published dartdoc complete — a host evaluating Weft
// reads the API reference, and undocumented surface is unshippable surface.
import 'dart:io';

const packages = <String>[
  'weft',
  'weft_document',
  'weft_engine',
  'weft_runtime_api',
  'weft_capabilities',
  'weft_runtime_fake',
  'weft_runtime_contract',
  'weft_quickjs',
];

final _typeDecl = RegExp(
  r'^\s*(?:abstract\s+|base\s+|final\s+|sealed\s+|interface\s+)*'
  r'(class|enum|mixin|typedef|extension)\s+([A-Za-z_][A-Za-z0-9_]*)',
);
final _topFunction = RegExp(
  r'^\s*(?:[A-Za-z_][A-Za-z0-9_<>, ?]*\s+)?([A-Za-z_][A-Za-z0-9_]*)'
  r'\s*(?:<[^(]*>)?\s*\(',
);
final _topVar = RegExp(
  r'^\s*(?:final|const|late\s+final|var)\s+(?:[A-Za-z_][A-Za-z0-9_<>, ?]*\s+)?'
  r'([A-Za-z_][A-Za-z0-9_]*)\s*[=;]',
);
final _memberMethod = RegExp(
  r'^\s*(?:static\s+|const\s+|final\s+|late\s+|covariant\s+)*'
  r'(?:[A-Za-z_][A-Za-z0-9_<>, ?]*\s+)?([a-z][A-Za-z0-9_]*)'
  r'\s*(?:<[^(]*>)?\s*\(',
);
final _memberGetter = RegExp(
  r'^\s*(?:static\s+)?[A-Za-z_][A-Za-z0-9_<>, ?]*\s+get\s+([a-z][A-Za-z0-9_]*)',
);
final _memberField = RegExp(
  r'^\s*(?:static\s+)?(?:final|const|late\s+final|late)?\s*'
  r'(?:[A-Za-z_][A-Za-z0-9_<>, ?]*\s+)?([a-z][A-Za-z0-9_]*)\s*[=;]',
);
final _constructor = RegExp(
  r'^\s*(?:const\s+|factory\s+)?([A-Z][A-Za-z0-9_]*)(?:\.[a-z][A-Za-z0-9_]*)?\s*\(',
);
final _exportDirective = RegExp(r"^\s*(?:export|part)\s+'([^']+)'");
final _hasDocs = RegExp(r'^\s*///');
final _isOverride = RegExp(r'^\s*@override');

void main(List<String> arguments) {
  final reportOnly = arguments.contains('--report');
  final gaps = <String>[];

  for (final package in packages) {
    final entryCandidates = Directory('packages/$package/lib')
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .toList();
    final entry = entryCandidates.firstWhere(
      (file) => file.uri.pathSegments.last == '$package.dart',
      orElse: () => entryCandidates.firstWhere(
        (file) => !file.uri.pathSegments.last.startsWith('_'),
      ),
    );
    final exported = _resolveExports(package, entry.path);
    for (final file in exported) {
      gaps.addAll(_scanFile(file));
    }
  }

  if (gaps.isEmpty) {
    stdout.writeln('doc coverage: all public API documented');
    return;
  }
  stdout.writeln('doc coverage: ${gaps.length} undocumented public members');
  for (final gap in gaps) {
    stdout.writeln('  $gap');
  }
  if (!reportOnly) exitCode = 1;
}

Set<String> _resolveExports(String package, String entryPath) {
  final base = Directory('packages/$package/lib').path;
  final resolved = <String>{entryPath};
  final queue = <String>[entryPath];
  while (queue.isNotEmpty) {
    final file = queue.removeLast();
    for (final line in File(file).readAsLinesSync()) {
      final match = _exportDirective.firstMatch(line);
      if (match == null) continue;
      final target = match.group(1)!;
      final path = '$base/${target.replaceAll("/", r"\")}';
      if (File(path).existsSync() && !resolved.contains(path)) {
        resolved.add(path);
        queue.add(path);
      }
    }
  }
  return resolved;
}

List<String> _scanFile(String path) {
  final gaps = <String>[];
  final lines = File(path).readAsLinesSync();
  var depth = 0;
  // Depths at which a class/enum/extension body is directly open; a line is
  // a member declaration only at these depths, never inside method bodies.
  // Members of private types are not public API and are skipped.
  final classBodyDepths = <int, bool>{};
  // Paren/bracket nesting across lines: continuation lines of expression
  // bodies or argument lists are never declarations.
  var paren = 0;
  var afterArrow = false;
  var pendingType = false;
  var hadDocs = false;
  var hadOverride = false;

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].replaceAll(RegExp(r'//.*$'), '');

    if (_hasDocs.hasMatch(lines[i])) {
      hadDocs = true;
      continue;
    }
    if (line.trim().isEmpty) continue;
    if (line.trim().startsWith('@')) {
      if (_isOverride.hasMatch(line)) {
        hadOverride = true;
      } else {
        hadOverride = false;
      }
      continue;
    }

    final typeMatch = _typeDecl.firstMatch(line);
    if (typeMatch != null && !line.contains('{') && !line.contains('}')) {
      if (!typeMatch.group(2)!.startsWith('_') && !hadDocs) {
        gaps.add('${_relative(path)}:${i + 1}: ${typeMatch.group(2)}');
      }
      pendingType = true;
      hadDocs = false;
      hadOverride = false;
      continue;
    }

    final opens = '{'.allMatches(line).length;
    final closes = '}'.allMatches(line).length;
    final parenOpens =
        '('.allMatches(line).length + '['.allMatches(line).length;
    final parenCloses =
        ')'.allMatches(line).length + ']'.allMatches(line).length;

    final isContinuation = paren > 0 || afterArrow;
    final isMemberPosition =
        classBodyDepths[depth] == false; // public class body only
    final topLevel = depth == 0 && !pendingType;
    final name = typeMatch != null
        ? typeMatch.group(2)
        : _memberName(line, isMemberPosition, topLevel);
    if (name != null &&
        !isContinuation &&
        !name.startsWith('_') &&
        !hadDocs &&
        !hadOverride) {
      gaps.add('${_relative(path)}:${i + 1}: $name');
    }

    final trimmed = line.trim();
    afterArrow = trimmed.endsWith('=>');
    paren += parenOpens - parenCloses;
    if (paren < 0) paren = 0;

    pendingType = false;
    hadDocs = false;
    hadOverride = false;

    if (opens > 0 && (typeMatch != null || pendingType)) {
      // Type bodies opening on (or after) the declaration line.
    }
    for (var o = 0; o < opens; o++) {
      depth += 1;
      if (typeMatch != null && o == 0) {
        classBodyDepths[depth] = typeMatch.group(2)!.startsWith('_');
      }
    }
    for (var c = 0; c < closes; c++) {
      classBodyDepths.remove(depth);
      depth -= 1;
    }
    if (depth < 0) depth = 0;
  }
  return gaps;
}

String? _memberName(String line, bool memberPosition, bool topLevel) {
  if (memberPosition) {
    const memberKeywords = {'super', 'assert', 'this', 'return', 'if', 'for'};
    final head = line.trim().split(RegExp(r'[\s(]')).first;
    if (memberKeywords.contains(head)) return null;
    // Constructor initializer-list assignments (`field = expr,`) and other
    // bare assignments are continuation lines, not declarations.
    if (RegExp(r'^\s*[a-zA-Z_]\w*\s*=').hasMatch(line)) return null;
    final ctor = _constructor.firstMatch(line);
    if (ctor != null && !line.contains('return ')) return ctor.group(1);
    final getter = _memberGetter.firstMatch(line);
    if (getter != null) return getter.group(1);
    final method = _memberMethod.firstMatch(line);
    if (method != null) return method.group(1);
    final field = _memberField.firstMatch(line);
    if (field != null) return field.group(1);
    return null;
  }
  if (topLevel) {
    final function = _topFunction.firstMatch(line);
    if (function != null && !line.contains('=')) {
      final name = function.group(1)!;
      const keywords = {'if', 'for', 'while', 'switch', 'return', 'catch'};
      if (!keywords.contains(name)) return name;
    }
    final variable = _topVar.firstMatch(line);
    if (variable != null) return variable.group(1);
  }
  return null;
}

String _relative(String path) => path.replaceAll(r'\', '/');
