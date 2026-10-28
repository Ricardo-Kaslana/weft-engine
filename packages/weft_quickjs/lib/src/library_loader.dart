import 'dart:ffi';

/// File name the Android Gradle module packages into the APK. It is loaded by
/// name so the dynamic linker picks the ABI directory matching the process.
const String androidLibraryName = 'libweft_quickjs.so';

/// Where the native Weft QuickJS library comes from on the current platform.
///
/// Desktop builds the library once with `tool/build_native.sh`; the mobile
/// platforms get it from the Flutter plugin build instead (see ADR 0035).
enum QuickJsLibrarySource {
  /// A caller-supplied path: [QuickJsNativeLibrary.load]'s `explicitPath` or
  /// the `WEFT_QUICKJS_LIBRARY` environment variable.
  explicitPath,

  /// iOS: the CocoaPods target compiles the shim into the app image, so the
  /// entry points are resolved from the running process, not from a file.
  appImage,

  /// Android: the Gradle module ships `libweft_quickjs.so` inside the APK and
  /// the dynamic linker finds it by name.
  androidPackaged,

  /// Desktop: the shared library produced by `tool/build_native.sh`.
  desktopBuild,
}

/// Chooses the library source for the current platform.
///
/// [override] is the explicit path argument or the `WEFT_QUICKJS_LIBRARY`
/// value; when it is not blank it wins everywhere so a host can point the
/// engine at a custom build, including on a device.
QuickJsLibrarySource librarySourceFor({
  required bool isIOS,
  required bool isAndroid,
  String? override,
}) {
  if (override != null && override.trim().isNotEmpty) {
    return QuickJsLibrarySource.explicitPath;
  }
  if (isIOS) {
    return QuickJsLibrarySource.appImage;
  }
  if (isAndroid) {
    return QuickJsLibrarySource.androidPackaged;
  }
  return QuickJsLibrarySource.desktopBuild;
}

/// Opens the dynamic library backing [source].
///
/// [desktopPath] resolves the file for [QuickJsLibrarySource.desktopBuild] and
/// is injectable so the search order stays testable without a real build.
DynamicLibrary openLibraryForSource(
  QuickJsLibrarySource source, {
  String? override,
  String Function()? desktopPath,
}) {
  switch (source) {
    case QuickJsLibrarySource.explicitPath:
      return DynamicLibrary.open(override!);
    case QuickJsLibrarySource.appImage:
      return DynamicLibrary.process();
    case QuickJsLibrarySource.androidPackaged:
      return DynamicLibrary.open(androidLibraryName);
    case QuickJsLibrarySource.desktopBuild:
      final resolve = desktopPath;
      if (resolve == null) {
        throw StateError(
          'desktopBuild requires a desktopPath resolver (see resolveLibraryPath).',
        );
      }
      return DynamicLibrary.open(resolve());
  }
}

/// Explains why loading failed and what to do about it, per source.
String describeLoadFailure(
  QuickJsLibrarySource source,
  String? override,
  Object error,
) {
  final hint = switch (source) {
    QuickJsLibrarySource.explicitPath =>
      'Check the path passed as explicitPath or in WEFT_QUICKJS_LIBRARY.',
    QuickJsLibrarySource.appImage =>
      'The iOS pod compiles the shim into the app image. Run `pod install` '
          'and rebuild the app so the pod target is linked.',
    QuickJsLibrarySource.androidPackaged =>
      'The Android module packages $androidLibraryName at build time. '
          'Rebuild the APK/App Bundle after a `flutter clean`.',
    QuickJsLibrarySource.desktopBuild =>
      'Build it with: packages/weft_quickjs/tool/build_native.sh\n'
          'or point WEFT_QUICKJS_LIBRARY at an existing binary.',
  };
  final target = switch (source) {
    QuickJsLibrarySource.explicitPath => ' at "$override"',
    QuickJsLibrarySource.appImage => ' from the app image',
    QuickJsLibrarySource.androidPackaged => ' ($androidLibraryName)',
    QuickJsLibrarySource.desktopBuild => ' from the desktop build',
  };
  return 'Unable to load the Weft QuickJS native library$target ($error).\n'
      '$hint';
}
