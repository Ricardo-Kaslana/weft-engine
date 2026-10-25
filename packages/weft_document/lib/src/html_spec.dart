abstract final class WeftHtmlSpec {
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

  static const voidTags = <String>{'br', 'col', 'hr', 'img'};

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

  static const ignoredContainerTags = <String>{
    'base',
    'head',
    'link',
    'meta',
    'noscript',
    'title',
  };

  static const transparentTags = <String>{'body', 'html'};

  static const globalAttributes = <String>{'class', 'id', 'style', 'title'};

  static const tagAttributes = <String, Set<String>>{
    'a': {'href'},
    'col': {'span', 'width'},
    'colgroup': {'span'},
    'img': {'src', 'alt', 'width', 'height'},
    'td': {'colspan', 'rowspan'},
    'th': {'colspan', 'rowspan'},
  };

  /// The upper bound for colspan/rowspan clamping, matching the HTML limit
  /// browsers apply to colspan.
  static const maxSpan = 1000;
}
