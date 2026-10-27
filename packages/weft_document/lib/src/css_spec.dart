/// The CSS property whitelist — the supported subset this engine commits
/// to laying out. Everything else is dropped with `css.property.unsupported`.
abstract final class WeftCssSpec {
  /// Properties accepted on selectors and inline styles.
  static const supportedProperties = <String>{
    'background-color',
    'border',
    'border-bottom',
    'border-collapse',
    'border-left',
    'border-right',
    'border-spacing',
    'border-top',
    'box-sizing',
    'clear',
    'color',
    'display',
    'float',
    'font-family',
    'font-size',
    'font-style',
    'font-weight',
    'height',
    'line-height',
    'list-style-type',
    'margin',
    'margin-bottom',
    'margin-left',
    'margin-right',
    'margin-top',
    'max-width',
    'min-width',
    'padding',
    'padding-bottom',
    'padding-left',
    'padding-right',
    'padding-top',
    'text-align',
    'text-decoration',
    'vertical-align',
    'white-space',
    'width',
  };

  /// Whether [property] (case-insensitive) is in the supported subset.
  static bool supportsProperty(String property) {
    return supportedProperties.contains(property.toLowerCase());
  }
}
