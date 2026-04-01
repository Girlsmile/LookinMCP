#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface LKMBridge : NSObject

- (instancetype)init NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

- (NSArray<NSDictionary<NSString *, id> *> *)listApps:(NSError **)error;
- (nullable NSDictionary<NSString *, id> *)selectAppWithID:(NSString *)appID error:(NSError **)error;
- (nullable NSDictionary<NSString *, id> *)captureSnapshotWithParameters:(NSDictionary<NSString *, id> *)parameters error:(NSError **)error;

@end

FOUNDATION_EXPORT NSErrorDomain const LKMBridgeErrorDomain;

typedef NS_ENUM(NSInteger, LKMBridgeErrorCode) {
    LKMBridgeErrorCodeNoAppSelected = 1001,
    LKMBridgeErrorCodeUnknownApp = 1002,
    LKMBridgeErrorCodeDisconnected = 1003,
    LKMBridgeErrorCodeInvalidRequest = 1004
};

NS_ASSUME_NONNULL_END
