import 'package:test/test.dart';
import 'package:weft_quickjs/src/library_loader.dart';

void main() {
  group('librarySourceFor', () {
    test('an explicit path wins on every platform', () {
      for (final platform in const [
        (isIOS: true, isAndroid: false),
        (isIOS: false, isAndroid: true),
        (isIOS: false, isAndroid: false),
      ]) {
        expect(
          librarySourceFor(
            isIOS: platform.isIOS,
            isAndroid: platform.isAndroid,
            override: '/opt/weft/libweft_quickjs.so',
          ),
          QuickJsLibrarySource.explicitPath,
        );
      }
    });

    test('iOS resolves the entry points from the app image', () {
      expect(
        librarySourceFor(isIOS: true, isAndroid: false),
        QuickJsLibrarySource.appImage,
      );
    });

    test('Android opens the library the plugin packages', () {
      expect(
        librarySourceFor(isIOS: false, isAndroid: true),
        QuickJsLibrarySource.androidPackaged,
      );
    });

    test('desktop falls back to the local build', () {
      expect(
        librarySourceFor(isIOS: false, isAndroid: false),
        QuickJsLibrarySource.desktopBuild,
      );
    });

    test('a blank override is not an explicit path', () {
      for (final blank in const ['', '   ']) {
        expect(
          librarySourceFor(isIOS: false, isAndroid: true, override: blank),
          QuickJsLibrarySource.androidPackaged,
        );
      }
    });
  });

  group('describeLoadFailure', () {
    test('names the platform specific remedy', () {
      expect(
        describeLoadFailure(QuickJsLibrarySource.androidPackaged, null, 'boom'),
        allOf(contains(androidLibraryName), contains('Rebuild the APK')),
      );
      expect(
        describeLoadFailure(QuickJsLibrarySource.appImage, null, 'boom'),
        contains('pod install'),
      );
      expect(
        describeLoadFailure(QuickJsLibrarySource.desktopBuild, null, 'boom'),
        contains('build_native.sh'),
      );
      expect(
        describeLoadFailure(
            QuickJsLibrarySource.explicitPath, '/opt/weft/libx.so', 'boom'),
        contains('/opt/weft/libx.so'),
      );
    });
  });
}
