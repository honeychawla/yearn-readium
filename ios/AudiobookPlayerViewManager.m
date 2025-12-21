#import "React/RCTViewManager.h"

@interface RCT_EXTERN_MODULE(AudiobookPlayerViewManager, RCTViewManager)

RCT_EXPORT_VIEW_PROPERTY(file, NSDictionary *)
RCT_EXPORT_VIEW_PROPERTY(onLocationChange, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onPlaybackStateChange, RCTDirectEventBlock)

@end
