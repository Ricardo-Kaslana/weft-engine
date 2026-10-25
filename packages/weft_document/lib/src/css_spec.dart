abstract final class WeftCssSpec {
  static const supportedProperties = <String>{
    'background-color',
    'border',
    'border-bottom',
    'border-left',
    'border-right',
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
    'white-space',
    'width',
  };

  static bool supportsProperty(String property) {
    return supportedProperties.contains(property.toLowerCase());
  }
}
