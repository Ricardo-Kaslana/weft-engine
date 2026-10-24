import 'package:test/test.dart';
import 'package:weft_document/weft_document.dart';

void main() {
  test('support report rejects required fallback and is immutable', () {
    final report = SupportReport(const [
      SupportIssue(
        code: 'canvas.unsupported',
        message: 'Canvas requires a fallback renderer.',
        requiresWebView: true,
      ),
    ]);

    expect(report.requiresWebView, isTrue);
    expect(report.canRender, isFalse);
    expect(
      () => report.issues.add(
        const SupportIssue(code: 'late.issue', message: 'Too late.'),
      ),
      throwsA(isA<UnsupportedError>()),
    );
  });

  test('warnings without errors remain renderable', () {
    final report = SupportReport(const [
      SupportIssue(code: 'css.dropped', message: 'Declaration dropped.'),
    ]);

    expect(report.hasErrors, isFalse);
    expect(report.canRender, isTrue);
  });
}
