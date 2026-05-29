//
//  LKStaticWindowController.h
//  Lookin
//
//  Created by Li Kai on 2018/11/4.
//  https://lookin.work
//

#import "LKWindowController.h"
#import "LKMenuPopoverAppsListController.h"

@class LKStaticViewController;

typedef NS_ENUM(NSInteger, LKMCPRefreshWaitUntil) {
    LKMCPRefreshWaitUntilHierarchy = 0,
    LKMCPRefreshWaitUntilDetails = 1
};

@interface LKStaticWindowController : LKWindowController

@property(nonatomic, strong, readonly) LKStaticViewController *viewController;

- (void)popupAllInspectableAppsWithSource:(MenuPopoverAppsListControllerEventSource)source;
- (void)requestMCPRefreshWithRequestID:(NSString *)requestID
                            waitUntil:(LKMCPRefreshWaitUntil)waitUntil
                            timeoutMs:(NSInteger)timeoutMs
                           completion:(void (^)(BOOL success,
                                                NSString *_Nullable phase,
                                                NSString *_Nullable snapshotID,
                                                NSString *_Nullable capturedAt,
                                                NSString *_Nullable appName,
                                                NSError *_Nullable error))completion;

@end
