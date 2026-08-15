//
//  CGVirtualDisplayShim.h
//  VirtualDisplayKit
//
//  Compiler-visible @interface declarations for CoreGraphics' PRIVATE
//  CGVirtualDisplay family of classes.
//
//  IMPORTANT: These classes are NOT implemented here. They already exist,
//  fully implemented, inside CoreGraphics.framework starting with macOS
//  12.3. This header exists purely so the Objective-C / Swift compiler
//  knows the selectors and can emit direct, statically-typed `objc_msgSend`
//  calls against them — exactly the same technique used by open-source
//  projects such as BetterDisplay (waydabber/BetterDisplay) and Lunar
//  (alin23/Lunar) to drive this API.
//
//  Why a header of @interface declarations instead of
//  NSClassFromString + NSInvocation:
//    - NSClassFromString/NSInvocation still works, but every argument and
//      return value must be boxed/unboxed by hand through NSInvocation's
//      untyped `void *` argument slots. Struct-returning methods
//      (CGSize-ish dimensions, CGDirectDisplayID, C-string-backed
//      properties, block-typed termination handlers) are exactly the cases
//      NSInvocation handles worst on arm64 (invisible struct-return
//      conventions, non-trivial ownership for blocks) and where subtle
//      crashes/leaks show up first.
//    - Declaring the real @interface lets ARC manage retain/release
//      correctly, lets the Swift importer generate a proper Swift-facing
//      class with correctly typed initializers/properties, and gives us
//      compile-time selector/argument-type checking against the header —
//      so a typo in a selector name is a build error, not a runtime crash.
//    - This is the same approach documented by BetterDisplay/Lunar's own
//      private headers (see e.g. Lunar's `CGVirtualDisplay.h` /
//      `CGVirtualDisplayDescriptor.h` shims), so we're following prior art
//      that has shipped and been runtime-validated across many macOS point
//      releases, rather than inventing a new binding strategy.
//
//  The method signatures below reflect the layout reverse-engineered from
//  CoreGraphics' Objective-C runtime metadata (class-dump / runtime
//  introspection) by the open-source projects referenced above. Apple does
//  not publish headers for these classes; they may change or disappear in
//  a future macOS release without notice. This is a deliberate trade-off
//  documented in ../../README.md.
//
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

// MARK: - CGVirtualDisplayMode

/// A single supported timing mode (resolution + refresh rate) advertised
/// by a virtual display.
__attribute__((visibility("default")))
@interface CGVirtualDisplayMode : NSObject

- (instancetype)initWithWidth:(NSUInteger)width
                        height:(NSUInteger)height
                   refreshRate:(double)refreshRate;

@property(nonatomic, readonly) NSUInteger width;
@property(nonatomic, readonly) NSUInteger height;
@property(nonatomic, readonly) double refreshRate;

@end

// MARK: - CGVirtualDisplaySettings

/// The set of modes + HiDPI flag applied to a display after creation via
/// `-[CGVirtualDisplay applySettings:]`.
__attribute__((visibility("default")))
@interface CGVirtualDisplaySettings : NSObject

@property(nonatomic, copy) NSArray<CGVirtualDisplayMode *> *modes;
@property(nonatomic) NSUInteger hiDPI;

@end

// MARK: - CGVirtualDisplayDescriptor

/// Static identity/metadata for a virtual display, consumed once by
/// `-[CGVirtualDisplay initWithDescriptor:]`.
__attribute__((visibility("default")))
@interface CGVirtualDisplayDescriptor : NSObject <NSCopying>

/// Human readable name shown in System Settings > Displays.
@property(nonatomic, copy) NSString *name;

@property(nonatomic) NSUInteger maxPixelsWide;
@property(nonatomic) NSUInteger maxPixelsHigh;

/// Physical size hint used to derive the panel's reported PPI.
@property(nonatomic) CGSize sizeInMillimeters;

@property(nonatomic) uint32_t serialNum;
@property(nonatomic) uint32_t productID;
@property(nonatomic) uint32_t vendorID;

/// Invoked by CoreGraphics when the display is torn down (either explicitly
/// via -[CGVirtualDisplay class] deallocation or system-initiated).
/// `flags` reasons are undocumented by Apple; treat as opaque.
@property(nonatomic, copy) void (^terminationHandler)(void *cgVirtualDisplay, uint32_t flags);

@end

// MARK: - CGVirtualDisplay

/// The live virtual display object. Owns a real `CGDirectDisplayID` for as
/// long as it is retained.
__attribute__((visibility("default")))
@interface CGVirtualDisplay : NSObject

- (instancetype)initWithDescriptor:(CGVirtualDisplayDescriptor *)descriptor;

/// Applies (or re-applies) the mode list / HiDPI setting. Must be called at
/// least once after init before the display is usable.
- (BOOL)applySettings:(CGVirtualDisplaySettings *)settings;

/// The real display ID this virtual display was assigned by WindowServer.
/// Usable anywhere a normal `CGDirectDisplayID` is accepted, including
/// `SCShareableContent` / ScreenCaptureKit lookups.
@property(nonatomic, readonly) CGDirectDisplayID displayID;

@end

// MARK: - Runtime availability guard

/// Defensive runtime check performed BEFORE any of the classes above are
/// touched. Because these are undocumented classes, we do not trust that
/// they exist just because we linked against CoreGraphics.framework; a
/// future macOS release could remove or rename them. Callers (see
/// VirtualDisplay.swift) must check this before calling `alloc`/`init` on
/// any of the classes declared above.
FOUNDATION_EXPORT BOOL CGVirtualDisplayShimIsAvailable(void);

NS_ASSUME_NONNULL_END
