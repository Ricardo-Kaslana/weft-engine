/// The HTML tag/attribute whitelist (single source of truth for the
/// normalizer's policy tables, docs/supported-subset.md matrix).
abstract final class WeftHtmlSpec {
  /// Tags rendered natively; anything else is unwrapped, dropped with a
  /// diagnostic, or routed to [fallbackTags].
  static const allowedTags = <String>{
    'a',
    'b',
    'blockquote',
    'br',
    'caption',
    'code',
    'col',
    'colgroup',
    'dd',
    'div',
    'dl',
    'dt',
    'em',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'hr',
    'i',
    'img',
    'li',
    'ol',
    'p',
    'pre',
    's',
    'small',
    'span',
    'strong',
    'sub',
    'sup',
    'table',
    'tbody',
    'td',
    'tfoot',
    'th',
    'thead',
    'tr',
    'u',
    'ul',
  };

  /// Empty elements that never have children.
  static const voidTags = <String>{'br', 'col', 'hr', 'img'};

  /// Interactive/embedded tags the engine will not render; each produces
  /// a `requiresWebView` diagnostic (ADR 0006).
  static const fallbackTags = <String>{
    'audio',
    'button',
    'canvas',
    'embed',
    'form',
    'iframe',
    'input',
    'object',
    'select',
    'svg',
    'textarea',
    'video',
  };

  /// Metadata containers stripped before the tree is built.
  static const ignoredContainerTags = <String>{
    'base',
    'head',
    'link',
    'meta',
    'noscript',
    'title',
  };

  /// Containers whose children are visited directly (not rendered as
  /// boxes themselves).
  static const transparentTags = <String>{'body', 'html'};

  /// Attributes allowed on every element.
  static const globalAttributes = <String>{
    'aria-atomic',
    'aria-hidden',
    'aria-label',
    'aria-live',
    'class',
    'id',
    'role',
    'style',
    'title',
  };

  /// `role` values the semantic layer understands (ADR 0040). Anything else
  /// is dropped with an `aria.role.unsupported` diagnostic; rendering is
  /// never affected. The set is deliberately conservative: Flutter's debug
  /// role validation rejects role trees that violate parent/child or state
  /// invariants, so roles needing them (table/list overrides, tab, menu,
  /// radio, landmarks) are not offered yet.
  static const supportedRoles = <String>{
    'alert',
    'button',
    'dialog',
    'alertdialog',
    'heading',
    'img',
    'link',
    'none',
    'presentation',
    'status',
  };

  /// Per-tag attribute whitelist on top of [globalAttributes].
  static const tagAttributes = <String, Set<String>>{
    'a': {'href'},
    'col': {'span', 'width'},
    'colgroup': {'span'},
    'img': {'src', 'alt', 'width', 'height'},
    'li': {'value'},
    'ol': {'start'},
    'td': {'colspan', 'rowspan'},
    'th': {'colspan', 'rowspan'},
  };

  /// The upper bound for colspan/rowspan clamping, matching the HTML limit
  /// browsers apply to colspan.
  static const maxSpan = 1000;
}
