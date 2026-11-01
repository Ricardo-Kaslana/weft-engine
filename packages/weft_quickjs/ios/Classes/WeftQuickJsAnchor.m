// Keeps the QuickJS FFI shim linked into the iOS app image (ADR 0035).
//
// CocoaPods links pods as static libraries, and the linker only pulls in
// object files that satisfy an undefined symbol. Nothing in C calls the
// `weft_*` entry points — Dart resolves them at runtime with dlsym — so
// without an anchor the shim (and the engine it references) would be dropped
// when the app is built with -dead_strip.
//
// Some hosts link CocoaPods with -ObjC, in which case an ObjC class carrying
// +load is pulled in automatically. Taking the address of `weft_now_ms` creates
// the missing reference, which pulls in weft_glue.o and, through it, the
// QuickJS objects. Flutter does not guarantee -ObjC, so the podspec also adds
// -Wl,-u,_weft_now_ms to the host link as the primary guard. `WEFT_EXPORT`
// carries __attribute__((used)) for the same reason.

#import <Foundation/Foundation.h>

extern double weft_now_ms(void);

@interface WeftQuickJsAnchor : NSObject
@end

@implementation WeftQuickJsAnchor

+ (void)load {
  // Referenced at load time so the linker cannot prove it is unused.
  double (*entryPoint)(void) = &weft_now_ms;
  (void)entryPoint;
}

@end
