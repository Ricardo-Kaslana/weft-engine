#
# Weft QuickJS iOS pod (ADR 0035).
#
# iOS apps cannot ship and open a separate dylib the way desktop does, so the
# vendored engine and the FFI shim are compiled straight into the host app
# image. Dart then resolves the `weft_*` entry points with
# `DynamicLibrary.process()`.
#
# Native sources are referenced relatively from the pod root. CocoaPods
# rejects absolute source patterns, so the vendored engine must stay relative
# to this podspec; do not reintroduce File.expand_path here.
#
# The ObjC anchor in Classes/ keeps the C objects alive when the app is linked
# with -dead_strip; see the comment in WeftQuickJsAnchor.m.
#
Pod::Spec.new do |s|
  s.name             = 'weft_quickjs'
  s.version          = '0.7.0-dev.1'
  s.summary          = 'QuickJS native backend for the Weft rendering engine.'
  s.description      = <<-DESC
Compiles the vendored QuickJS 2024-01-13 engine and the Weft FFI shim into the
host application and exposes the weft_* entry points to dart:ffi.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :type => 'MIT', :file => '../native/quickjs/LICENSE' }
  s.author           = { 'Weft' => 'weft@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = '../native/**/*.{c,h}', 'Classes/**/*.{h,m}'
  s.dependency 'Flutter'
  s.ios.deployment_target = '13.0'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'GCC_PREPROCESSOR_DEFINITIONS' =>
      '$(inherited) _GNU_SOURCE=1 CONFIG_BIGNUM=1',
    'OTHER_CFLAGS' =>
      '$(inherited) -DCONFIG_VERSION=\"2024-01-13\" -fno-strict-aliasing -Wno-unused-parameter'
  }
  # Flutter hosts do not guarantee `-ObjC`, so a static pod's ObjC anchor can be
  # dropped before its `+load` reference is considered. Force the entry point to
  # remain undefined at the final link; the linker then pulls weft_glue.o and
  # the QuickJS objects it references. The ObjC anchor remains as a second line
  # of defense for hosts that do link with `-ObjC`.
  s.user_target_xcconfig = {
    'OTHER_LDFLAGS' => '$(inherited) -Wl,-u,_weft_now_ms'
  }
end
