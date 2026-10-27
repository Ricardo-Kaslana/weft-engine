// Regenerates the normalization consistency vectors under
// conformance/normalization/ (ADR 0034).
//
//   dart run tool/normalization_vectors.dart
//
// Each vector pins one normalization contract: the recorded input HTML, the
// normalizer configuration, and the exact expected snapshot in the canonical
// WeftDocumentJson encoding. `packages/weft_document/test/
// normalization_consistency_test.dart` re-normalizes every input on every CI
// run; any engine change that alters normalization output must regenerate
// these files and get the diff human-reviewed before commit — the same
// policy as the browser geometry references in conformance/reference/.
//
// A server-side producer is "conformant" when normalizing the recorded
// input with the recorded configuration emits exactly the recorded snapshot
// bytes; a client-side consumer is conformant when decoding the recorded
// snapshot reproduces the same document tree.
import 'dart:convert';
import 'dart:io';

import 'package:weft_document/weft_document.dart';

final syntheticCases = <Map<String, Object?>>[
  {
    'id': 'synthetic_script_fallback',
    'input': '<body><p>visible</p><script>alert(1)</script>'
        '<noscript>no</noscript></body>',
  },
  {
    'id': 'synthetic_nested_table_fallback',
    'input': '<body><table><tr><td><table><tr><td>inner</td></tr>'
        '</table></td></tr></table></body>',
  },
  {
    'id': 'synthetic_custom_tags',
    'normalizer': <String, Object?>{
      'customTags': <String>['weft-badge']
    },
    'input': '<head><style>weft-badge { color: red; }</style></head>'
        '<body><p>Rating: <weft-badge data-label="New" '
        'style="background: #fee">badge text</weft-badge></p></body>',
  },
  {
    'id': 'synthetic_cjk_and_emoji',
    'input': '<body><p>中文排版测试，标点禁则。Emoji 😃 follows.</p>'
        '<pre>pre  spaces\nkeep</pre></body>',
  },
  {
    'id': 'synthetic_entities',
    'input': '<body><p title="a&amp;b">&lt;tag&gt; &amp; &#x1F600; '
        '&quot;q&quot;</p></body>',
  },
  {
    'id': 'synthetic_void_and_comments',
    'input': '<body><p>line<br>break</p><!-- hidden --><hr><img '
        'src="https://example.com/x.png" alt="x"></body>',
  },
  {
    'id': 'synthetic_unsupported_elements',
    'input': '<body><video src="a.mp4"></video><iframe src="b"></iframe>'
        '<form><input type="text"><button>go</button></form></body>',
  },
  {
    'id': 'synthetic_table_tracks',
    'input': '<head><style>table { border-collapse: collapse; }</style>'
        '</head><body><table><colgroup><col style="width: 40px">'
        '<col style="width: 30%" span="2"></colgroup>'
        '<tr><th colspan="2">head</th><th>tail</th></tr>'
        '<tr><td>a</td><td>b</td><td>c</td></tr></table></body>',
  },
  {
    'id': 'synthetic_parse_warnings',
    'input': '<body><p>unclosed <em>emphasis</p></body>',
  },
  {
    'id': 'synthetic_lists_and_quotes',
    'input': '<body><ol start="3"><li>one<ul><li>nested</li></ul></li>'
        '</ol><blockquote><p>quote</p></blockquote><pre><code>x = 1;'
        '</code></pre></body>',
  },
];

void main() {
  final outDir = Directory('conformance/normalization');
  if (!outDir.existsSync()) outDir.createSync(recursive: true);

  const encoder = JsonEncoder.withIndent('  ');
  var count = 0;

  void writeVector({
    required String id,
    required String source,
    required String input,
    Map<String, Object?> normalizer = const <String, Object?>{},
    String snapshotId = 'vector',
    int revision = 1,
  }) {
    final customTags =
        (normalizer['customTags'] as List<String>? ?? const <String>[])
            .cast<String>();
    final snapshot = WeftNormalizer(customTags: customTags.toSet()).normalize(
      input,
      id: snapshotId,
      revision: revision,
    );
    final vector = <String, Object?>{
      'id': id,
      'source': source,
      'normalizer': <String, Object?>{'customTags': customTags},
      'snapshot': <String, Object?>{'id': snapshotId, 'revision': revision},
      'input': input,
      'expected': WeftDocumentJson.encode(snapshot),
    };
    File('${outDir.path}/$id.json').writeAsStringSync(
      '${encoder.convert(vector)}\n',
    );
    count += 1;
    stdout.writeln('wrote ${outDir.path}/$id.json '
        '(${snapshot.supportReport.issues.length} issues)');
  }

  final casesDir = Directory('conformance/cases');
  for (final entity in casesDir.listSync().whereType<File>().toList()
    ..sort(
      (a, b) => a.path.compareTo(b.path),
    )) {
    if (!entity.path.endsWith('.html')) continue;
    final id = 'case_${entity.uri.pathSegments.last.replaceAll('.html', '')}';
    writeVector(
      id: id,
      source: 'conformance/cases/${entity.uri.pathSegments.last}',
      input: entity.readAsStringSync(),
      snapshotId: 'vector-$id',
    );
  }

  for (final item in syntheticCases) {
    writeVector(
      id: item['id']! as String,
      source: 'inline',
      input: item['input']! as String,
      normalizer: (item['normalizer'] as Map<String, Object?>?) ??
          const <String, Object?>{},
      snapshotId: 'vector-${item['id']}',
    );
  }

  stdout.writeln('generated $count vectors');
}
