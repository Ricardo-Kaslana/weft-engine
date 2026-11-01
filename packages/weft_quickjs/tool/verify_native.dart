import 'dart:io';

import 'package:weft_quickjs/weft_quickjs.dart';

/// Fails when the QuickJS native library is unavailable.
///
/// Tests skip the FFI groups on machines without a native build so local
/// development remains possible. CI runs this check after building the library
/// so a missing or broken artifact cannot turn the test job green by skipping.
void main() {
  try {
    QuickJsNativeLibrary.load();
  } on Object catch (error) {
    stderr.writeln('QuickJS native library verification failed:\n$error');
    exitCode = 1;
    return;
  }
  stdout.writeln(
    'QuickJS native library loaded: ${QuickJsNativeLibrary.resolveLibraryPath()}',
  );
}
