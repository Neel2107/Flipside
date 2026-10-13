#import "CVirtualDisplay.h"

// Private CoreGraphics classes, declared here and looked up by name at run time so that
// nothing fails to link if a future macOS removes them.

@interface CGVirtualDisplayMode : NSObject
- (instancetype)initWithWidth:(NSUInteger)width height:(NSUInteger)height refreshRate:(double)refreshRate;
@end

@interface CGVirtualDisplaySettings : NSObject
@property(nonatomic) unsigned int hiDPI;
@property(nonatomic, retain) NSArray *modes;
@end

@interface CGVirtualDisplayDescriptor : NSObject
@property(nonatomic, retain) dispatch_queue_t queue;
@property(nonatomic, retain) NSString *name;
@property(nonatomic) unsigned int maxPixelsWide;
@property(nonatomic) unsigned int maxPixelsHigh;
@property(nonatomic) CGSize sizeInMillimeters;
@property(nonatomic) unsigned int vendorID;
@property(nonatomic) unsigned int productID;
@property(nonatomic) unsigned int serialNum;
@end

@interface CGVirtualDisplay : NSObject
- (instancetype)initWithDescriptor:(CGVirtualDisplayDescriptor *)descriptor;
- (BOOL)applySettings:(CGVirtualDisplaySettings *)settings;
@property(nonatomic, readonly) CGDirectDisplayID displayID;
@end

id FSCreateVirtualDisplay(NSString *name, unsigned int width, unsigned int height, CGDirectDisplayID *displayID) {
    Class Descriptor = NSClassFromString(@"CGVirtualDisplayDescriptor");
    Class Settings = NSClassFromString(@"CGVirtualDisplaySettings");
    Class Mode = NSClassFromString(@"CGVirtualDisplayMode");
    Class VirtualDisplay = NSClassFromString(@"CGVirtualDisplay");
    if (!Descriptor || !Settings || !Mode || !VirtualDisplay) return nil;

    CGVirtualDisplayDescriptor *descriptor = [[Descriptor alloc] init];
    descriptor.queue = dispatch_get_main_queue();
    descriptor.name = name;
    descriptor.maxPixelsWide = width * 2;
    descriptor.maxPixelsHigh = height * 2;
    descriptor.sizeInMillimeters = CGSizeMake(597, 336);  // a 27-inch 16:9 panel
    descriptor.vendorID = 0xF11D;
    descriptor.productID = 0x51DE;
    descriptor.serialNum = 1;

    CGVirtualDisplay *display = [[VirtualDisplay alloc] initWithDescriptor:descriptor];
    if (!display) return nil;

    CGVirtualDisplaySettings *settings = [[Settings alloc] init];
    settings.hiDPI = 1;
    settings.modes = @[[[Mode alloc] initWithWidth:width height:height refreshRate:60]];
    if (![display applySettings:settings]) return nil;

    *displayID = display.displayID;
    return display;
}
