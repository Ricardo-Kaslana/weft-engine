abstract final class WeftCssSpec {
  static const supportedProperties = <String>{
    'background-color',
    'color',
    'display',
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
    'padding',
    'padding-bottom',
    'padding-left',
    'padding-right',
    'padding-top',
    'text-align',
    'text-decoration',
    'white-space',
  };

  static bool supportsProperty(String property) {
    return supportedProperties.contains(property.toLowerCase());
  }
}
