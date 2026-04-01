//
//  LKMCPHostManager.h
//  Lookin
//

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, LKMCPHostState) {
    LKMCPHostStateOff = 0,
    LKMCPHostStateStarting,
    LKMCPHostStateReady,
    LKMCPHostStateConnected,
    LKMCPHostStateStale,
    LKMCPHostStateError
};

extern NSNotificationName const LKMCPHostManagerDidUpdateNotification;

@interface LKMCPHostManager : NSObject

@property(nonatomic, assign, readonly) LKMCPHostState state;
@property(nonatomic, copy, readonly) NSString *statusText;
@property(nonatomic, copy, readonly) NSString *statusSummaryText;
@property(nonatomic, copy, readonly) NSString *serverAddress;
@property(nonatomic, copy, readonly, nullable) NSString *snapshotID;
@property(nonatomic, copy, readonly, nullable) NSString *capturedAtText;
@property(nonatomic, copy, readonly, nullable) NSString *lastRequestAtText;
@property(nonatomic, copy, readonly, nullable) NSString *lastErrorText;
@property(nonatomic, copy, readonly) NSString *snapshotRootPath;
@property(nonatomic, assign, readonly) BOOL snapshotAvailable;
@property(nonatomic, assign, readonly) BOOL snapshotStale;
@property(nonatomic, assign, readonly) BOOL enabled;

+ (instancetype)sharedInstance;

- (void)startHost;
- (void)stopHost;
- (void)toggleHost;
- (void)refreshStatus;
- (void)reconnectHost;
- (void)copyAddressToPasteboard;
- (NSColor *)statusColor;

@end

NS_ASSUME_NONNULL_END
