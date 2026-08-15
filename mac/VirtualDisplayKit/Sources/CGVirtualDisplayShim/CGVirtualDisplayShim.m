//
//  CGVirtualDisplayShim.m
//  VirtualDisplayKit
//
//  No CGVirtualDisplay* classes are implemented in this file — they already
//  exist inside CoreGraphics.framework. This translation unit only provides
//  the runtime-availability guard declared in the umbrella header, using
//  the classic (and here, deliberately last-resort) NSClassFromString
//  technique. We reserve NSClassFromString for exactly this one
//  yes/no existence check — never for driving the actual API, which is why
//  the rest of this package calls the classes directly through the typed
//  @interface declarations instead.
//
#import "include/CGVirtualDisplayShim.h"

BOOL CGVirtualDisplayShimIsAvailable(void) {
    Class descriptor = NSClassFromString(@"CGVirtualDisplayDescriptor");
    Class display = NSClassFromString(@"CGVirtualDisplay");
    Class settings = NSClassFromString(@"CGVirtualDisplaySettings");
    Class mode = NSClassFromString(@"CGVirtualDisplayMode");
    return descriptor != nil && display != nil && settings != nil && mode != nil;
}
