abstract final class WeftHtmlSpec {
  static const allowedTags = <String>{
    'a',
    'b',
    'blockquote',
    'br',
    'code',
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
    'u',
    'ul',
  };

  static const voidTags = <String>{'br', 'hr'};

  static const fallbackTags = <String>{
    'audio',
    'button',
    'canvas',
    'embed',
    'form',
    'iframe',
    'img',
    'input',
    'object',
    'select',
    'svg',
    'table',
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
  };
}
