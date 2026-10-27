/// Configurable CJK line-breaking prohibitions (kinsoku shori).
///
/// The tables hold UTF-16 code units so they can be queried directly with
/// `String.codeUnitAt`, which is how the line-by-line layout path inspects
/// break candidates.
final class WeftLineBreakRules {
  /// Creates rules with the given prohibition tables.
  const WeftLineBreakRules({
    this.lineStartProhibited = defaultLineStart,
    this.lineEndProhibited = defaultLineEnd,
  });

  /// Characters that must not open a line: closing brackets, closing quotes
  /// and trailing punctuation.
  final Set<int> lineStartProhibited;

  /// Characters that must not close a line: opening brackets and quotes.
  final Set<int> lineEndProhibited;

  /// Characters prohibited at the start of a line.
  static const defaultLineStart = <int>{
    0x005D, // ]
    0x2014, // — em dash
    0x2026, // … ellipsis
    0x3001, // 、 ideographic comma
    0x3002, // 。 ideographic full stop
    0x3009, // 〉 right angle bracket
    0x300B, // 》 right double angle bracket
    0x300D, // 」 right corner bracket
    0x300F, // 』 right white corner bracket
    0x3011, // 】 right black lenticular bracket
    0x3015, // 〕 right tortoise shell bracket
    0x309B, // ゛ katakana-Hiragana voiced sound mark
    0x309C, // ゜ katakana-Hiragana semi-voiced sound mark
    0x30FB, // ・ katakana middle dot
    0xFF01, // ！ fullwidth exclamation mark
    0xFF09, // ） fullwidth right parenthesis
    0xFF0C, // ， fullwidth comma
    0xFF0E, // ． fullwidth full stop
    0xFF1A, // ： fullwidth colon
    0xFF1B, // ； fullwidth semicolon
    0xFF1F, // ？ fullwidth question mark
  };

  /// Characters prohibited at the end of a line.
  static const defaultLineEnd = <int>{
    0x3008, // 〈 left angle bracket
    0x300A, // 《 left double angle bracket
    0x300C, // 「 left corner bracket
    0x300E, // 『 left white corner bracket
    0x3010, // 【 left black lenticular bracket
    0x3014, // 〔 left tortoise shell bracket
    0xFF08, // （ fullwidth left parenthesis
  };

  /// Empty rule tables: line breaking behaves exactly as before this class
  /// existed. The sets must be const so the instance itself stays const.
  static const off = WeftLineBreakRules(
    lineStartProhibited: <int>{},
    lineEndProhibited: <int>{},
  );
}
