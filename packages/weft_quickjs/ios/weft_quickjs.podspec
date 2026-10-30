#
# Weft QuickJS iOS pod (ADR 0035).
#
# iOS apps cannot ship and open a separate dylib the way desktop does, so the
# vendored engine and the FFI shim are compiled straight into the host app
# image. Dart then resolves the `weft_*` entry points with
# `DynamicLibrary.process()`.
#
# CocoaPods file *patterns* do not support traversing `..` (podspec guide,
# "File patterns"), so the native sources are expanded to absolute paths here
# instead of writing '../native/**/*'. Development pods already live outside
# the Pods sandbox, so absolute references are the same mechanism the sandbox
# uses for every Flutter plugin.
#
# The ObjC anchor in Classes/ keeps the C objects alive when the app is linked
# with -dead_strip; see the comment in WeftQuickJsAnchor.m.
#
Pod::Spec.new do |s|
  native_dir = File.expand_path('../native', __dir__)

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
  s.source_files     = Dir.glob(File.join(native_dir, '**/*.{c,h}')) +
                       Dir.glob(File.join(__dir__, 'Classes/**/*.{h,m}'))
  s.dependency 'Flutter'
  s.ios.deployment_target = '13.0'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'GCC_PREPROCESSOR_DEFINITIONS' =>
      '$(inherited) _GNU_SOURCE=1 CONFIG_BIGNUM=1',
    'OTHER_CFLAGS' =>
      '$(inherited) -DCONFIG_VERSION=\"2024-01-13\" -fno-strict-aliasing -Wno-unused-parameter'
  }
end
