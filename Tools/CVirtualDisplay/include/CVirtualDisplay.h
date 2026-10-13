#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Adds a virtual HiDPI display of `width` x `height` points to this login session, using the
/// private CGVirtualDisplay API. The display exists for as long as the returned object does.
/// Returns nil if the API is unavailable or the display couldn't be created.
id _Nullable FSCreateVirtualDisplay(NSString *name, unsigned int width, unsigned int height,
                                    CGDirectDisplayID *displayID);

NS_ASSUME_NONNULL_END
