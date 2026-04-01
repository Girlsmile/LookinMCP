#import "LKMBridge.h"

#import <AppKit/AppKit.h>

#import "LookinAppInfo.h"
#import "LookinAttrIdentifiers.h"
#import "LookinAttribute.h"
#import "LookinAttributesGroup.h"
#import "LookinAttributesSection.h"
#import "LookinAutoLayoutConstraint.h"
#import "LookinConnectionAttachment.h"
#import "LookinConnectionResponseAttachment.h"
#import "LookinDefines.h"
#import "LookinDisplayItem.h"
#import "LookinDisplayItemDetail.h"
#import "LookinHierarchyInfo.h"
#import "LookinIvarTrace.h"
#import "LookinObject.h"
#import "LookinStaticAsyncUpdateTask.h"
#import "Peertalk/Lookin_PTChannel.h"
#import "Peertalk/Lookin_PTProtocol.h"
#import "Peertalk/Lookin_PTUSBHub.h"

NSErrorDomain const LKMBridgeErrorDomain = @"LKMBridgeErrorDomain";

static NSString * const LKMBridgeClientVersion = @"lookin-mcp/0.1.0";
static NSUInteger const LKMBridgeDefaultTreeDepth = 2;
static NSUInteger const LKMBridgeDefaultMaxMatches = 10;
static NSUInteger const LKMBridgeAbsoluteMaxMatches = 20;
static NSUInteger const LKMBridgeMaxExcerptNodes = 120;

static BOOL LKMBridgeDebugEnabled(void) {
    static BOOL enabled = NO;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *value = NSProcessInfo.processInfo.environment[@"LOOKIN_MCP_DEBUG"];
        enabled = value.length > 0 && ![value isEqualToString:@"0"];
    });
    return enabled;
}

static void LKMBridgeDebugLog(NSString *format, ...) {
    if (!LKMBridgeDebugEnabled()) {
        return;
    }
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    fprintf(stderr, "[lookin-mcp] %s\n", message.UTF8String);
}

@interface LKMBridgeEndpoint : NSObject

@property(nonatomic, copy) NSString *transport;
@property(nonatomic, assign) int port;
@property(nonatomic, strong, nullable) NSNumber *deviceID;

@end

@implementation LKMBridgeEndpoint
@end

@interface LKMBridgePendingRequest : NSObject

@property(nonatomic, assign) uint32_t type;
@property(nonatomic, assign) uint32_t tag;
@property(nonatomic, assign) NSInteger channelUniqueID;
@property(nonatomic, strong) dispatch_semaphore_t semaphore;
@property(nonatomic, strong) NSMutableArray<LookinConnectionResponseAttachment *> *attachments;
@property(nonatomic, strong, nullable) NSError *error;
@property(nonatomic, assign) NSUInteger expectedDataCount;
@property(nonatomic, assign) NSUInteger receivedDataCount;
@property(nonatomic, assign) BOOL finished;

@end

@implementation LKMBridgePendingRequest
@end

@interface LKMBridgeSession : NSObject

@property(nonatomic, copy) NSString *appID;
@property(nonatomic, strong) LKMBridgeEndpoint *endpoint;
@property(nonatomic, strong) Lookin_PTChannel *channel;
@property(nonatomic, strong) LookinAppInfo *appInfo;
@property(nonatomic, assign) BOOL disconnected;

- (NSDictionary<NSString *, id> *)metadataDictionary;
- (NSString *)endpointKey;

@end

@implementation LKMBridgeSession

- (NSDictionary<NSString *,id> *)metadataDictionary {
    NSMutableDictionary<NSString *, id> *payload = [NSMutableDictionary dictionary];
    payload[@"app_id"] = self.appID;
    payload[@"app_name"] = self.appInfo.appName ?: @"";
    payload[@"bundle_id"] = self.appInfo.appBundleIdentifier ?: @"";
    payload[@"device_description"] = self.appInfo.deviceDescription ?: @"";
    payload[@"os_description"] = self.appInfo.osDescription ?: @"";
    payload[@"transport"] = self.endpoint.transport ?: @"unknown";
    payload[@"port"] = @(self.endpoint.port);
    payload[@"is_connected"] = @(!self.disconnected && self.channel.isConnected);

    if (self.endpoint.deviceID != nil) {
        payload[@"device_id"] = self.endpoint.deviceID;
    }

    payload[@"screen"] = @{
        @"width": @(self.appInfo.screenWidth),
        @"height": @(self.appInfo.screenHeight),
        @"scale": @(self.appInfo.screenScale)
    };

    if (self.appInfo.serverReadableVersion.length > 0) {
        payload[@"lookin_server_version"] = self.appInfo.serverReadableVersion;
    } else {
        payload[@"lookin_server_version"] = @(self.appInfo.serverVersion);
    }

    return payload;
}

- (NSString *)endpointKey {
    if ([self.endpoint.transport isEqualToString:@"usb"]) {
        return [NSString stringWithFormat:@"usb:%@:%d", self.endpoint.deviceID ?: @0, self.endpoint.port];
    }
    return [NSString stringWithFormat:@"sim:%d", self.endpoint.port];
}

@end

@interface LKMBridge () <Lookin_PTChannelDelegate>

@property(nonatomic, strong) dispatch_queue_t operationQueue;
@property(nonatomic, strong) dispatch_queue_t protocolQueue;
@property(nonatomic, strong) NSMutableDictionary<NSString *, LKMBridgeSession *> *sessionsByAppID;
@property(nonatomic, strong) NSMutableDictionary<NSString *, LKMBridgePendingRequest *> *pendingRequests;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, LKMBridgeSession *> *sessionsByChannelID;
@property(nonatomic, strong) NSMutableSet<NSNumber *> *attachedUSBDeviceIDs;
@property(nonatomic, copy, nullable) NSString *selectedAppID;

@end

@implementation LKMBridge

- (instancetype)init {
    self = [super init];
    if (self) {
        _operationQueue = dispatch_queue_create("work.lookin.mcp.bridge.operations", DISPATCH_QUEUE_SERIAL);
        _protocolQueue = dispatch_queue_create("work.lookin.mcp.bridge.protocol", DISPATCH_QUEUE_SERIAL);
        _sessionsByAppID = [NSMutableDictionary dictionary];
        _pendingRequests = [NSMutableDictionary dictionary];
        _sessionsByChannelID = [NSMutableDictionary dictionary];
        _attachedUSBDeviceIDs = [NSMutableSet set];

        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        __weak typeof(self) weakSelf = self;
        [center addObserverForName:Lookin_PTUSBDeviceDidAttachNotification object:nil queue:nil usingBlock:^(NSNotification * _Nonnull note) {
            NSNumber *deviceID = note.userInfo[@"DeviceID"];
            if (deviceID == nil) {
                return;
            }
            @synchronized (weakSelf) {
                [weakSelf.attachedUSBDeviceIDs addObject:deviceID];
            }
            LKMBridgeDebugLog(@"usb attached deviceID=%@", deviceID);
        }];
        [center addObserverForName:Lookin_PTUSBDeviceDidDetachNotification object:nil queue:nil usingBlock:^(NSNotification * _Nonnull note) {
            NSNumber *deviceID = note.userInfo[@"DeviceID"];
            if (deviceID == nil) {
                return;
            }
            @synchronized (weakSelf) {
                [weakSelf.attachedUSBDeviceIDs removeObject:deviceID];
            }
            LKMBridgeDebugLog(@"usb detached deviceID=%@", deviceID);
        }];

        [Lookin_PTUSBHub sharedHub];
        LKMBridgeDebugLog(@"bridge initialized");
    }
    return self;
}

- (NSArray<NSDictionary<NSString *,id> *> *)listApps:(NSError **)error {
    id result = [self _performSyncReturningObject:^id(NSError **operationError) {
        NSArray<LKMBridgeSession *> *sessions = [self _discoverApps:operationError];
        if (sessions == nil) {
            return nil;
        }

        NSMutableArray<NSDictionary<NSString *, id> *> *apps = [NSMutableArray array];
        for (LKMBridgeSession *session in sessions) {
            [apps addObject:session.metadataDictionary];
        }
        return apps;
    } error:error];
    return result ?: @[];
}

- (NSDictionary<NSString *,id> *)selectAppWithID:(NSString *)appID error:(NSError **)error {
    return [self _performSyncReturningObject:^id(NSError **operationError) {
        if (appID.length == 0) {
            if (operationError) {
                *operationError = [self _bridgeErrorWithCode:LKMBridgeErrorCodeUnknownApp description:@"No discovered app matches the requested app id."];
            }
            return nil;
        }

        NSArray<LKMBridgeSession *> *sessions = [self _discoverApps:operationError];
        if (sessions == nil) {
            return nil;
        }
        (void)sessions;

        LKMBridgeSession *session = self.sessionsByAppID[appID];
        if (session == nil) {
            if (operationError) {
                *operationError = [self _bridgeErrorWithCode:LKMBridgeErrorCodeUnknownApp description:@"No discovered app matches the requested app id."];
            }
            return nil;
        }
        if (session.disconnected || !session.channel.isConnected) {
            [self _invalidateSelectedAppIfNeeded:session];
            if (operationError) {
                *operationError = [self _bridgeErrorWithCode:LKMBridgeErrorCodeDisconnected description:@"The selected app disconnected before it could be activated."];
            }
            return nil;
        }

        self.selectedAppID = session.appID;
        NSMutableDictionary<NSString *, id> *result = [session.metadataDictionary mutableCopy];
        result[@"selected"] = @YES;
        return result;
    } error:error];
}

- (NSDictionary<NSString *,id> *)captureSnapshotWithParameters:(NSDictionary<NSString *,id> *)parameters error:(NSError **)error {
    return [self _performSyncReturningObject:^id(NSError **operationError) {
        NSDictionary *target = [parameters[@"target"] isKindOfClass:[NSDictionary class]] ? parameters[@"target"] : @{};

        NSString *requestedAppID = [self _stringForKey:@"app_id" inDictionary:parameters];
        LKMBridgeSession *session = [self _resolveSessionForSnapshotWithRequestedAppID:requestedAppID error:operationError];
        if (session == nil) {
            return nil;
        }

        LookinHierarchyInfo *hierarchy = [self _fetchHierarchyForSession:session error:operationError];
        if (hierarchy == nil) {
            return nil;
        }

        NSArray<LookinDisplayItem *> *flatItems = [LookinDisplayItem flatItemsFromHierarchicalItems:hierarchy.displayItems ?: @[]];
        NSDictionary<NSNumber *, LookinDisplayItem *> *itemsByOID = [self _itemsByOIDFromFlatItems:flatItems];

        NSString *vcName = [self _stringForKey:@"vc_name" inDictionary:target] ?: [self _stringForKey:@"vc_name" inDictionary:parameters];
        NSString *ivarName = [self _stringForKey:@"ivar_name" inDictionary:target] ?: [self _stringForKey:@"ivar_name" inDictionary:parameters];
        NSString *className = [self _stringForKey:@"class_name" inDictionary:target] ?: [self _stringForKey:@"class_name" inDictionary:parameters];
        NSString *text = [self _stringForKey:@"text" inDictionary:target] ?: [self _stringForKey:@"text" inDictionary:parameters];

        NSUInteger treeDepth = [self _unsignedIntegerForKey:@"tree_depth" inDictionary:parameters defaultValue:LKMBridgeDefaultTreeDepth];
        NSUInteger maxMatches = [self _unsignedIntegerForKey:@"max_matches" inDictionary:parameters defaultValue:LKMBridgeDefaultMaxMatches];
        maxMatches = MAX(1, MIN(maxMatches, LKMBridgeAbsoluteMaxMatches));

        BOOL includeTree = [self _boolForKey:@"include_tree" inDictionary:parameters defaultValue:YES];
        BOOL includeScreenshot = [self _boolForKey:@"include_screenshot" inDictionary:parameters defaultValue:YES];

        BOOL needsDetailForAllItems = (text.length > 0);
        NSDictionary<NSNumber *, LookinDisplayItemDetail *> *allDetailsByOID = @{};
        if (needsDetailForAllItems && flatItems.count > 0) {
            allDetailsByOID = [self _fetchDetailsForItems:flatItems session:session error:operationError];
            if (allDetailsByOID == nil) {
                return nil;
            }
        }

        NSMutableArray<LookinDisplayItem *> *matchedItems = [NSMutableArray array];
        for (LookinDisplayItem *item in flatItems) {
            LookinDisplayItemDetail *detail = allDetailsByOID[@([self _oidForItem:item])];
            if ([self _item:item matchesVCName:vcName ivarName:ivarName className:className text:text detail:detail]) {
                [matchedItems addObject:item];
                if (matchedItems.count >= maxMatches) {
                    break;
                }
            }
        }

        NSDictionary<NSNumber *, LookinDisplayItemDetail *> *matchedDetailsByOID = allDetailsByOID;
        if (matchedItems.count > 0 && matchedDetailsByOID.count == 0) {
            matchedDetailsByOID = [self _fetchDetailsForItems:matchedItems session:session error:operationError];
            if (matchedDetailsByOID == nil) {
                return nil;
            }
        }

        NSMutableArray<NSDictionary<NSString *, id> *> *matches = [NSMutableArray array];
        for (LookinDisplayItem *item in matchedItems) {
            LookinDisplayItemDetail *detail = matchedDetailsByOID[@([self _oidForItem:item])];
            [matches addObject:[self _matchDictionaryForItem:item detail:detail]];
        }

        NSMutableDictionary<NSString *, id> *payload = [NSMutableDictionary dictionary];
        payload[@"app"] = session.metadataDictionary;
        payload[@"active_app_id"] = session.appID;
        payload[@"visible_view_controller_names"] = [self _visibleViewControllerNamesFromItems:flatItems];
        payload[@"filters_applied"] = @{
            @"vc_name": vcName ?: [NSNull null],
            @"ivar_name": ivarName ?: [NSNull null],
            @"class_name": className ?: [NSNull null],
            @"text": text ?: [NSNull null]
        };
        payload[@"matches"] = matches;
        payload[@"match_count"] = @(matches.count);
        payload[@"diagnostic_notes"] = [self _diagnosticNotesForMatchesCount:matches.count maxMatches:maxMatches];

        if (includeScreenshot) {
            NSDictionary<NSString *, id> *screenshot = [self _encodedImageDictionaryFromImage:hierarchy.appInfo.screenshot ?: session.appInfo.screenshot];
            if (screenshot != nil) {
                payload[@"screenshot"] = screenshot;
            }
        }

        if (includeTree) {
            payload[@"hierarchy_excerpt"] = [self _hierarchyExcerptFromRoots:hierarchy.displayItems ?: @[]
                                                                      matches:matchedItems
                                                                   itemsByOID:itemsByOID
                                                                     detailsByOID:matchedDetailsByOID
                                                                   maximumDepth:treeDepth];
        }

        return payload;
    } error:error];
}

#pragma mark - Sync Helpers

- (id)_performSyncReturningObject:(id (^)(NSError **error))block error:(NSError **)error {
    __block id result = nil;
    __block NSError *operationError = nil;
    __block BOOL finished = NO;

    dispatch_block_t work = ^{
        result = block(&operationError);
        finished = YES;
    };

    if ([NSThread isMainThread]) {
        dispatch_async(self.operationQueue, work);
        while (!finished) {
            @autoreleasepool {
                [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
            }
        }
    } else {
        dispatch_sync(self.operationQueue, work);
    }

    if (error) {
        *error = operationError;
    }
    return result;
}

#pragma mark - Discovery

- (NSArray<LKMBridgeSession *> *)_discoverApps:(NSError **)error {
    NSMutableArray<LKMBridgeEndpoint *> *endpoints = [NSMutableArray array];
    for (int port = LookinSimulatorIPv4PortNumberStart; port <= LookinSimulatorIPv4PortNumberEnd; port++) {
        LKMBridgeEndpoint *endpoint = [LKMBridgeEndpoint new];
        endpoint.transport = @"simulator";
        endpoint.port = port;
        [endpoints addObject:endpoint];
    }

    NSArray<NSNumber *> *deviceIDs = nil;
    @synchronized (self) {
        deviceIDs = self.attachedUSBDeviceIDs.allObjects;
    }
    for (NSNumber *deviceID in deviceIDs) {
        for (int port = LookinUSBDeviceIPv4PortNumberStart; port <= LookinUSBDeviceIPv4PortNumberEnd; port++) {
            LKMBridgeEndpoint *endpoint = [LKMBridgeEndpoint new];
            endpoint.transport = @"usb";
            endpoint.port = port;
            endpoint.deviceID = deviceID;
            [endpoints addObject:endpoint];
        }
    }

    LKMBridgeDebugLog(@"discover begin simulatorPorts=%d usbDevices=%@", (LookinSimulatorIPv4PortNumberEnd - LookinSimulatorIPv4PortNumberStart + 1), deviceIDs);

    NSDictionary<NSString *, LKMBridgeSession *> *existingSessionsByEndpoint = [self _sessionsIndexedByEndpoint];
    NSMutableDictionary<NSString *, LKMBridgeSession *> *freshSessions = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSNumber *, LKMBridgeSession *> *freshSessionsByChannelID = [NSMutableDictionary dictionary];

    for (LKMBridgeEndpoint *endpoint in endpoints) {
        NSString *endpointKey = [self _endpointKeyForEndpoint:endpoint];
        LKMBridgeSession *session = existingSessionsByEndpoint[endpointKey];
        Lookin_PTChannel *channel = session.channel;
        if (channel == nil || !channel.isConnected || session.disconnected) {
            [channel close];
            channel = [self _connectToEndpoint:endpoint error:nil];
        }
        if (channel == nil || !channel.isConnected) {
            LKMBridgeDebugLog(@"endpoint unavailable transport=%@ port=%d deviceID=%@", endpoint.transport, endpoint.port, endpoint.deviceID);
            continue;
        }

        LookinAppInfo *appInfo = [self _fetchAppInfoForChannel:channel error:nil];
        if (appInfo == nil) {
            [channel close];
            LKMBridgeDebugLog(@"endpoint connected but app info unavailable transport=%@ port=%d deviceID=%@", endpoint.transport, endpoint.port, endpoint.deviceID);
            continue;
        }

        if (session == nil) {
            session = [LKMBridgeSession new];
        }
        session.endpoint = endpoint;
        session.channel = channel;
        session.appInfo = appInfo;
        session.disconnected = NO;
        session.appID = [self _appIDForAppInfo:appInfo endpoint:endpoint];

        freshSessions[session.appID] = session;
        freshSessionsByChannelID[@(channel.uniqueID)] = session;
        LKMBridgeDebugLog(@"discovered app appID=%@ app=%@ bundle=%@ transport=%@ port=%d deviceID=%@", session.appID, appInfo.appName, appInfo.appBundleIdentifier, endpoint.transport, endpoint.port, endpoint.deviceID);
    }

    for (NSString *appID in self.sessionsByAppID) {
        if (freshSessions[appID] == nil) {
            [self.sessionsByAppID[appID].channel close];
        }
    }

    self.sessionsByAppID = freshSessions;
    self.sessionsByChannelID = freshSessionsByChannelID;

    if (self.selectedAppID.length > 0 && self.sessionsByAppID[self.selectedAppID] == nil) {
        self.selectedAppID = nil;
    }

    NSArray<LKMBridgeSession *> *sessions = [freshSessions.allValues sortedArrayUsingComparator:^NSComparisonResult(LKMBridgeSession * _Nonnull left, LKMBridgeSession * _Nonnull right) {
        NSString *leftKey = [NSString stringWithFormat:@"%@|%@", left.appInfo.appName ?: @"", left.appInfo.deviceDescription ?: @""];
        NSString *rightKey = [NSString stringWithFormat:@"%@|%@", right.appInfo.appName ?: @"", right.appInfo.deviceDescription ?: @""];
        return [leftKey compare:rightKey];
    }];

    if (error) {
        *error = nil;
    }
    LKMBridgeDebugLog(@"discover end count=%@", @(sessions.count));
    return sessions;
}

- (NSDictionary<NSString *, LKMBridgeSession *> *)_sessionsIndexedByEndpoint {
    NSMutableDictionary<NSString *, LKMBridgeSession *> *index = [NSMutableDictionary dictionary];
    [self.sessionsByAppID enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, LKMBridgeSession * _Nonnull session, BOOL * _Nonnull stop) {
        index[session.endpointKey] = session;
    }];
    return index;
}

- (NSString *)_endpointKeyForEndpoint:(LKMBridgeEndpoint *)endpoint {
    if ([endpoint.transport isEqualToString:@"usb"]) {
        return [NSString stringWithFormat:@"usb:%@:%d", endpoint.deviceID ?: @0, endpoint.port];
    }
    return [NSString stringWithFormat:@"sim:%d", endpoint.port];
}

- (Lookin_PTChannel *)_connectToEndpoint:(LKMBridgeEndpoint *)endpoint error:(NSError **)error {
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block NSError *connectError = nil;

    Lookin_PTProtocol *protocol = [Lookin_PTProtocol sharedProtocolForQueue:self.protocolQueue];
    Lookin_PTChannel *channel = [[Lookin_PTChannel alloc] initWithProtocol:protocol delegate:self];
    channel.targetPort = endpoint.port;

    if ([endpoint.transport isEqualToString:@"usb"]) {
        LKMBridgeDebugLog(@"connect usb port=%d deviceID=%@", endpoint.port, endpoint.deviceID);
        [channel connectToPort:endpoint.port overUSBHub:[Lookin_PTUSBHub sharedHub] deviceID:endpoint.deviceID callback:^(NSError * _Nonnull responseError) {
            connectError = responseError;
            LKMBridgeDebugLog(@"connect usb result port=%d deviceID=%@ error=%@", endpoint.port, endpoint.deviceID, responseError);
            dispatch_semaphore_signal(semaphore);
        }];
    } else {
        LKMBridgeDebugLog(@"connect simulator port=%d", endpoint.port);
        [channel connectToPort:endpoint.port IPv4Address:INADDR_LOOPBACK callback:^(NSError * _Nonnull responseError, Lookin_PTAddress * _Nonnull address) {
            (void)address;
            connectError = responseError;
            LKMBridgeDebugLog(@"connect simulator result port=%d error=%@", endpoint.port, responseError);
            dispatch_semaphore_signal(semaphore);
        }];
    }

    dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC));
    long waitResult = dispatch_semaphore_wait(semaphore, timeout);
    if (waitResult != 0 || connectError != nil || !channel.isConnected) {
        [channel close];
        if (error) {
            *error = connectError;
        }
        return nil;
    }

    if (error) {
        *error = nil;
    }
    return channel;
}

- (LookinAppInfo *)_fetchAppInfoForChannel:(Lookin_PTChannel *)channel error:(NSError **)error {
    NSDictionary *params = @{@"needImages": @NO, @"local": @[]};
    NSArray<LookinConnectionResponseAttachment *> *responses = [self _performRoundTripRequestWithType:LookinRequestTypeApp
                                                                                                  data:params
                                                                                               channel:channel
                                                                                                 error:error];
    LookinConnectionResponseAttachment *attachment = responses.firstObject;
    if (![attachment.data isKindOfClass:[LookinAppInfo class]]) {
        if (error && *error == nil) {
            *error = [self _bridgeErrorWithCode:LKMBridgeErrorCodeDisconnected description:@"Failed to decode app metadata from the inspected app."];
        }
        return nil;
    }
    LKMBridgeDebugLog(@"app info fetched app=%@ bundle=%@", ((LookinAppInfo *)attachment.data).appName, ((LookinAppInfo *)attachment.data).appBundleIdentifier);
    return attachment.data;
}

- (LookinHierarchyInfo *)_fetchHierarchyForSession:(LKMBridgeSession *)session error:(NSError **)error {
    NSDictionary *params = @{@"clientVersion": LKMBridgeClientVersion};
    NSArray<LookinConnectionResponseAttachment *> *responses = [self _performRoundTripRequestWithType:LookinRequestTypeHierarchy
                                                                                                  data:params
                                                                                               channel:session.channel
                                                                                                 error:error];
    if (responses.count == 0) {
        return nil;
    }

    LookinConnectionResponseAttachment *attachment = responses.firstObject;
    if (![attachment.data isKindOfClass:[LookinHierarchyInfo class]]) {
        if (error && *error == nil) {
            *error = [self _bridgeErrorWithCode:LKMBridgeErrorCodeDisconnected description:@"Failed to decode hierarchy information from the inspected app."];
        }
        return nil;
    }
    return attachment.data;
}

#pragma mark - Snapshot Details

- (NSDictionary<NSNumber *, LookinDisplayItemDetail *> *)_fetchDetailsForItems:(NSArray<LookinDisplayItem *> *)items
                                                                        session:(LKMBridgeSession *)session
                                                                          error:(NSError **)error {
    if (items.count == 0) {
        return @{};
    }

    NSMutableArray<LookinStaticAsyncUpdateTask *> *tasks = [NSMutableArray array];
    for (LookinDisplayItem *item in items) {
        unsigned long oid = [self _oidForItem:item];
        if (oid == 0) {
            continue;
        }

        LookinStaticAsyncUpdateTask *task = [LookinStaticAsyncUpdateTask new];
        task.oid = oid;
        task.taskType = LookinStaticAsyncUpdateTaskTypeNoScreenshot;
        task.attrRequest = LookinDetailUpdateTaskAttrRequest_Need;
        task.needBasisVisualInfo = YES;
        task.clientReadableVersion = LKMBridgeClientVersion;
        [tasks addObject:task];
    }

    if (tasks.count == 0) {
        return @{};
    }

    NSMutableArray<LookinStaticAsyncUpdateTasksPackage *> *packages = [NSMutableArray array];
    NSMutableArray<LookinStaticAsyncUpdateTask *> *buffer = [NSMutableArray array];
    for (LookinStaticAsyncUpdateTask *task in tasks) {
        [buffer addObject:task];
        if (buffer.count >= 50) {
            LookinStaticAsyncUpdateTasksPackage *package = [LookinStaticAsyncUpdateTasksPackage new];
            package.tasks = buffer.copy;
            [packages addObject:package];
            [buffer removeAllObjects];
        }
    }
    if (buffer.count > 0) {
        LookinStaticAsyncUpdateTasksPackage *package = [LookinStaticAsyncUpdateTasksPackage new];
        package.tasks = buffer.copy;
        [packages addObject:package];
    }

    NSArray<LookinConnectionResponseAttachment *> *responses = [self _performRoundTripRequestWithType:LookinRequestTypeHierarchyDetails
                                                                                                  data:packages
                                                                                               channel:session.channel
                                                                                                 error:error];
    if (responses == nil) {
        return nil;
    }

    NSMutableDictionary<NSNumber *, LookinDisplayItemDetail *> *detailsByOID = [NSMutableDictionary dictionary];
    for (LookinConnectionResponseAttachment *attachment in responses) {
        if (![attachment.data isKindOfClass:[NSArray class]]) {
            continue;
        }
        for (id candidate in (NSArray *)attachment.data) {
            if (![candidate isKindOfClass:[LookinDisplayItemDetail class]]) {
                continue;
            }
            LookinDisplayItemDetail *detail = candidate;
            detailsByOID[@(detail.displayItemOid)] = detail;
        }
    }
    return detailsByOID;
}

#pragma mark - Request / Response

- (NSArray<LookinConnectionResponseAttachment *> *)_performRoundTripRequestWithType:(uint32_t)requestType
                                                                               data:(id)data
                                                                            channel:(Lookin_PTChannel *)channel
                                                                              error:(NSError **)error {
    NSTimeInterval pingTimeout = requestType == LookinRequestTypeApp ? 0.5 : 2;
    NSArray<LookinConnectionResponseAttachment *> *pingResponses = [self _sendRequestType:LookinRequestTypePing
                                                                                      data:nil
                                                                                   channel:channel
                                                                                   timeout:pingTimeout
                                                                                     error:error];
    if (pingResponses == nil || pingResponses.count == 0) {
        LKMBridgeDebugLog(@"roundtrip ping failed type=%u channel=%d", requestType, channel.uniqueID);
        return nil;
    }

    NSError *versionError = [self _serverVersionErrorFromPingResponse:pingResponses.firstObject];
    if (versionError != nil) {
        if (error) {
            *error = versionError;
        }
        return nil;
    }

    LKMBridgeDebugLog(@"roundtrip request type=%u channel=%d", requestType, channel.uniqueID);
    return [self _sendRequestType:requestType data:data channel:channel timeout:5 error:error];
}

- (NSArray<LookinConnectionResponseAttachment *> *)_sendRequestType:(uint32_t)type
                                                               data:(id)data
                                                            channel:(Lookin_PTChannel *)channel
                                                            timeout:(NSTimeInterval)timeout
                                                              error:(NSError **)error {
    if (channel == nil || !channel.isConnected) {
        if (error) {
            *error = [self _bridgeErrorWithCode:LKMBridgeErrorCodeDisconnected description:@"The target app is not currently connected."];
        }
        return nil;
    }

    LKMBridgePendingRequest *request = [LKMBridgePendingRequest new];
    request.type = type;
    request.tag = [self _newRequestTag];
    request.channelUniqueID = channel.uniqueID;
    request.semaphore = dispatch_semaphore_create(0);
    request.attachments = [NSMutableArray array];

    NSString *requestKey = [self _requestKeyForChannelUniqueID:request.channelUniqueID type:type tag:request.tag];
    @synchronized (self) {
        self.pendingRequests[requestKey] = request;
    }

    LookinConnectionAttachment *attachment = [LookinConnectionAttachment new];
    attachment.data = data;

    NSError *archiveError = nil;
    NSData *archivedData = [NSKeyedArchiver archivedDataWithRootObject:attachment requiringSecureCoding:YES error:&archiveError];
    if (archiveError != nil) {
        @synchronized (self) {
            [self.pendingRequests removeObjectForKey:requestKey];
        }
        if (error) {
            *error = archiveError;
        }
        return nil;
    }

    dispatch_data_t payload = [archivedData createReferencingDispatchData];
    [channel sendFrameOfType:type tag:request.tag withPayload:payload callback:^(NSError * _Nonnull sendError) {
        if (sendError != nil) {
            @synchronized (self) {
                LKMBridgePendingRequest *stored = self.pendingRequests[requestKey];
                if (stored != nil && !stored.finished) {
                    stored.error = sendError;
                    stored.finished = YES;
                    dispatch_semaphore_signal(stored.semaphore);
                }
            }
        }
    }];
    LKMBridgeDebugLog(@"request sent type=%u tag=%u channel=%ld", type, request.tag, (long)request.channelUniqueID);

    dispatch_time_t timeoutTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC));
    long waitResult = dispatch_semaphore_wait(request.semaphore, timeoutTime);

    @synchronized (self) {
        [self.pendingRequests removeObjectForKey:requestKey];
    }

    if (waitResult != 0) {
        LKMBridgeDebugLog(@"request timeout type=%u tag=%u channel=%ld", type, request.tag, (long)request.channelUniqueID);
        if (error) {
            *error = [self _bridgeErrorWithCode:LKMBridgeErrorCodeDisconnected description:@"Timed out while waiting for the inspected app to respond."];
        }
        return nil;
    }

    if (request.error != nil) {
        LKMBridgeDebugLog(@"request failed type=%u tag=%u channel=%ld error=%@", type, request.tag, (long)request.channelUniqueID, request.error);
        if (error) {
            *error = request.error;
        }
        return nil;
    }

    if (error) {
        *error = nil;
    }
    LKMBridgeDebugLog(@"request completed type=%u tag=%u channel=%ld responses=%@", type, request.tag, (long)request.channelUniqueID, @(request.attachments.count));
    return request.attachments.copy;
}

- (NSError *)_serverVersionErrorFromPingResponse:(LookinConnectionResponseAttachment *)pingResponse {
    int serverVersion = pingResponse.lookinServerVersion;
    if (serverVersion > LOOKIN_SUPPORTED_SERVER_MAX || serverVersion < LOOKIN_SUPPORTED_SERVER_MIN) {
        return [self _bridgeErrorWithCode:LKMBridgeErrorCodeDisconnected description:@"Lookin client/server protocol versions are incompatible."];
    }
    return nil;
}

- (uint32_t)_newRequestTag {
    static uint32_t tag = 1000;
    tag += 1;
    return tag;
}

- (NSString *)_requestKeyForChannelUniqueID:(NSInteger)channelUniqueID type:(uint32_t)type tag:(uint32_t)tag {
    return [NSString stringWithFormat:@"%ld:%u:%u", (long)channelUniqueID, type, tag];
}

#pragma mark - Session Resolution

- (LKMBridgeSession *)_resolveSessionForSnapshotWithRequestedAppID:(NSString *)requestedAppID error:(NSError **)error {
    NSString *appID = requestedAppID.length > 0 ? requestedAppID : self.selectedAppID;
    if (appID.length == 0) {
        if (error) {
            *error = [self _bridgeErrorWithCode:LKMBridgeErrorCodeNoAppSelected description:@"No app is currently selected."];
        }
        return nil;
    }

    NSArray<LKMBridgeSession *> *sessions = [self _discoverApps:error];
    if (sessions == nil) {
        return nil;
    }
    (void)sessions;

    LKMBridgeSession *session = self.sessionsByAppID[appID];
    if (session == nil) {
        if (error) {
            *error = [self _bridgeErrorWithCode:LKMBridgeErrorCodeUnknownApp description:@"No discovered app matches the requested app id."];
        }
        return nil;
    }

    if (session.disconnected || !session.channel.isConnected) {
        [self _invalidateSelectedAppIfNeeded:session];
        if (error) {
            *error = [self _bridgeErrorWithCode:LKMBridgeErrorCodeDisconnected description:@"The selected app is no longer connected."];
        }
        return nil;
    }

    return session;
}

- (void)_invalidateSelectedAppIfNeeded:(LKMBridgeSession *)session {
    if ([self.selectedAppID isEqualToString:session.appID]) {
        self.selectedAppID = nil;
    }
}

#pragma mark - Matching / JSON

- (NSDictionary<NSNumber *, LookinDisplayItem *> *)_itemsByOIDFromFlatItems:(NSArray<LookinDisplayItem *> *)flatItems {
    NSMutableDictionary<NSNumber *, LookinDisplayItem *> *itemsByOID = [NSMutableDictionary dictionary];
    for (LookinDisplayItem *item in flatItems) {
        unsigned long oid = [self _oidForItem:item];
        if (oid != 0) {
            itemsByOID[@(oid)] = item;
        }
    }
    return itemsByOID;
}

- (BOOL)_item:(LookinDisplayItem *)item
  matchesVCName:(NSString *)vcName
       ivarName:(NSString *)ivarName
      className:(NSString *)className
           text:(NSString *)text
         detail:(LookinDisplayItemDetail *)detail {
    if (vcName.length == 0 && ivarName.length == 0 && className.length == 0 && text.length == 0) {
        return NO;
    }

    if (vcName.length > 0) {
        LookinObject *vc = item.hostViewControllerObject;
        BOOL vcMatched = [vc.rawClassName isEqualToString:vcName] || [vc.classChainList containsObject:vcName];
        if (!vcMatched) {
            return NO;
        }
    }

    if (ivarName.length > 0) {
        NSArray<LookinIvarTrace *> *traces = [self _ivarTracesForItem:item];
        BOOL ivarMatched = NO;
        for (LookinIvarTrace *trace in traces) {
            if ([trace.ivarName isEqualToString:ivarName]) {
                ivarMatched = YES;
                break;
            }
        }
        if (!ivarMatched) {
            return NO;
        }
    }

    if (className.length > 0) {
        LookinObject *displayObject = [self _displayObjectForItem:item];
        BOOL classMatched = [displayObject.rawClassName isEqualToString:className] || [displayObject.classChainList containsObject:className];
        if (!classMatched) {
            return NO;
        }
    }

    if (text.length > 0) {
        NSArray<NSString *> *textCandidates = [self _textCandidatesForItem:item detail:detail];
        BOOL textMatched = NO;
        for (NSString *candidate in textCandidates) {
            if ([candidate rangeOfString:text options:NSCaseInsensitiveSearch].location != NSNotFound) {
                textMatched = YES;
                break;
            }
        }
        if (!textMatched) {
            return NO;
        }
    }

    return YES;
}

- (NSDictionary<NSString *, id> *)_matchDictionaryForItem:(LookinDisplayItem *)item detail:(LookinDisplayItemDetail *)detail {
    NSMutableDictionary<NSString *, id> *payload = [[self _baseNodeDictionaryForItem:item detail:detail isMatch:YES] mutableCopy];
    payload[@"layout_evidence"] = [self _layoutEvidenceForItem:item detail:detail];
    return payload;
}

- (NSDictionary<NSString *, id> *)_baseNodeDictionaryForItem:(LookinDisplayItem *)item
                                                      detail:(LookinDisplayItemDetail *)detail
                                                     isMatch:(BOOL)isMatch {
    unsigned long oid = [self _oidForItem:item];
    LookinObject *displayObject = [self _displayObjectForItem:item];
    NSDictionary<NSString *, id> *basis = [self _basisVisualDictionaryForItem:item detail:detail];

    NSMutableDictionary<NSString *, id> *payload = [NSMutableDictionary dictionary];
    payload[@"node_id"] = [NSString stringWithFormat:@"%lu", oid];
    payload[@"class_name"] = displayObject.rawClassName ?: @"";
    payload[@"class_chain"] = displayObject.classChainList ?: @[];
    payload[@"host_view_controller"] = item.hostViewControllerObject.rawClassName ?: [NSNull null];
    payload[@"ivar_names"] = [self _ivarNamesForItem:item];
    payload[@"frame"] = basis[@"frame"] ?: [NSNull null];
    payload[@"bounds"] = basis[@"bounds"] ?: [NSNull null];
    payload[@"is_hidden"] = basis[@"is_hidden"] ?: @(item.isHidden);
    payload[@"alpha"] = basis[@"alpha"] ?: @(item.alpha);
    payload[@"texts"] = [self _textCandidatesForItem:item detail:detail];
    payload[@"is_match"] = @(isMatch);
    return payload;
}

- (NSDictionary<NSString *, id> *)_basisVisualDictionaryForItem:(LookinDisplayItem *)item detail:(LookinDisplayItemDetail *)detail {
    CGRect frame = item.frame;
    CGRect bounds = item.bounds;
    BOOL hidden = item.isHidden;
    CGFloat alpha = item.alpha;

    if (detail.frameValue != nil) {
        frame = detail.frameValue.rectValue;
    }
    if (detail.boundsValue != nil) {
        bounds = detail.boundsValue.rectValue;
    }
    if (detail.hiddenValue != nil) {
        hidden = detail.hiddenValue.boolValue;
    }
    if (detail.alphaValue != nil) {
        alpha = detail.alphaValue.doubleValue;
    }

    return @{
        @"frame": [self _rectDictionary:frame],
        @"bounds": [self _rectDictionary:bounds],
        @"is_hidden": @(hidden),
        @"alpha": @(alpha)
    };
}

- (NSDictionary<NSString *, id> *)_layoutEvidenceForItem:(LookinDisplayItem *)item detail:(LookinDisplayItemDetail *)detail {
    NSMutableDictionary<NSString *, id> *payload = [[self _basisVisualDictionaryForItem:item detail:detail] mutableCopy];
    NSArray<LookinAttributesGroup *> *groups = [self _attributeGroupsForItem:item detail:detail];
    NSDictionary<NSString *, LookinAttribute *> *attributes = [self _attributeIndexFromGroups:groups];

    LookinAttribute *intrinsic = attributes[LookinAttr_AutoLayout_IntrinsicSize_Size];
    if (intrinsic.value != nil) {
        payload[@"intrinsic_content_size"] = [self _jsonValueFromObject:intrinsic.value];
    }

    NSDictionary<NSString *, id> *hugging = [self _axisPriorityDictionaryWithHorizontal:attributes[LookinAttr_AutoLayout_Hugging_Hor]
                                                                               vertical:attributes[LookinAttr_AutoLayout_Hugging_Ver]];
    if (hugging.count > 0) {
        payload[@"hugging"] = hugging;
    }

    NSDictionary<NSString *, id> *compression = [self _axisPriorityDictionaryWithHorizontal:attributes[LookinAttr_AutoLayout_Resistance_Hor]
                                                                                    vertical:attributes[LookinAttr_AutoLayout_Resistance_Ver]];
    if (compression.count > 0) {
        payload[@"compression_resistance"] = compression;
    }

    LookinAttribute *constraintsAttr = attributes[LookinAttr_AutoLayout_Constraints_Constraints];
    if ([constraintsAttr.value isKindOfClass:[NSArray class]]) {
        NSMutableArray<NSDictionary<NSString *, id> *> *constraints = [NSMutableArray array];
        for (id candidate in (NSArray *)constraintsAttr.value) {
            if (![candidate isKindOfClass:[LookinAutoLayoutConstraint class]]) {
                continue;
            }
            LookinAutoLayoutConstraint *constraint = candidate;
            [constraints addObject:@{
                @"effective": @(constraint.effective),
                @"active": @(constraint.active),
                @"priority": @(constraint.priority),
                @"identifier": constraint.identifier ?: [NSNull null],
                @"summary": [self _constraintSummary:constraint],
                @"first_item_type": [self _constraintItemTypeString:constraint.firstItemType],
                @"first_attribute": [self _constraintAttributeName:constraint.firstAttribute],
                @"relation": [self _constraintRelationString:constraint.relation],
                @"second_item_type": [self _constraintItemTypeString:constraint.secondItemType],
                @"second_attribute": [self _constraintAttributeName:constraint.secondAttribute],
                @"multiplier": @(constraint.multiplier),
                @"constant": @(constraint.constant)
            }];
        }
        payload[@"constraints"] = constraints;
    }

    return payload;
}

- (NSDictionary<NSString *, id> *)_axisPriorityDictionaryWithHorizontal:(LookinAttribute *)horizontal vertical:(LookinAttribute *)vertical {
    NSMutableDictionary<NSString *, id> *payload = [NSMutableDictionary dictionary];
    if (horizontal.value != nil) {
        payload[@"horizontal"] = [self _jsonValueFromObject:horizontal.value];
    }
    if (vertical.value != nil) {
        payload[@"vertical"] = [self _jsonValueFromObject:vertical.value];
    }
    return payload;
}

- (NSArray<NSString *> *)_visibleViewControllerNamesFromItems:(NSArray<LookinDisplayItem *> *)items {
    NSMutableOrderedSet<NSString *> *names = [NSMutableOrderedSet orderedSet];
    for (LookinDisplayItem *item in items) {
        NSString *name = item.hostViewControllerObject.rawClassName;
        if (name.length > 0) {
            [names addObject:name];
        }
    }
    return names.array;
}

- (NSArray<NSString *> *)_ivarNamesForItem:(LookinDisplayItem *)item {
    NSMutableOrderedSet<NSString *> *names = [NSMutableOrderedSet orderedSet];
    for (LookinIvarTrace *trace in [self _ivarTracesForItem:item]) {
        if (trace.ivarName.length > 0) {
            [names addObject:trace.ivarName];
        }
    }
    return names.array;
}

- (NSArray<LookinIvarTrace *> *)_ivarTracesForItem:(LookinDisplayItem *)item {
    NSMutableArray<LookinIvarTrace *> *traces = [NSMutableArray array];
    if (item.viewObject.ivarTraces.count > 0) {
        [traces addObjectsFromArray:item.viewObject.ivarTraces];
    }
    if (item.layerObject.ivarTraces.count > 0) {
        [traces addObjectsFromArray:item.layerObject.ivarTraces];
    }
    return traces;
}

- (LookinObject *)_displayObjectForItem:(LookinDisplayItem *)item {
    return item.viewObject ?: item.layerObject ?: [LookinObject new];
}

- (NSArray<LookinAttributesGroup *> *)_attributeGroupsForItem:(LookinDisplayItem *)item detail:(LookinDisplayItemDetail *)detail {
    if (detail.attributesGroupList.count > 0 || detail.customAttrGroupList.count > 0) {
        NSMutableArray<LookinAttributesGroup *> *groups = [NSMutableArray array];
        if (detail.attributesGroupList.count > 0) {
            [groups addObjectsFromArray:detail.attributesGroupList];
        }
        if (detail.customAttrGroupList.count > 0) {
            [groups addObjectsFromArray:detail.customAttrGroupList];
        }
        return groups;
    }
    return [item queryAllAttrGroupList] ?: @[];
}

- (NSDictionary<NSString *, LookinAttribute *> *)_attributeIndexFromGroups:(NSArray<LookinAttributesGroup *> *)groups {
    NSMutableDictionary<NSString *, LookinAttribute *> *index = [NSMutableDictionary dictionary];
    for (LookinAttributesGroup *group in groups) {
        for (LookinAttributesSection *section in group.attrSections) {
            for (LookinAttribute *attribute in section.attributes) {
                if (attribute.identifier.length > 0) {
                    index[attribute.identifier] = attribute;
                }
            }
        }
    }
    return index;
}

- (NSArray<NSString *> *)_textCandidatesForItem:(LookinDisplayItem *)item detail:(LookinDisplayItemDetail *)detail {
    NSMutableOrderedSet<NSString *> *texts = [NSMutableOrderedSet orderedSet];
    NSArray<LookinAttributesGroup *> *groups = [self _attributeGroupsForItem:item detail:detail];
    NSDictionary<NSString *, LookinAttribute *> *attributes = [self _attributeIndexFromGroups:groups];

    NSArray<NSString *> *textAttributeIDs = @[
        LookinAttr_UILabel_Text_Text,
        LookinAttr_UITextField_Text_Text,
        LookinAttr_UITextField_Placeholder_Placeholder,
        LookinAttr_UITextView_Text_Text,
        LookinAttr_UIImageView_Name_Name
    ];

    for (NSString *identifier in textAttributeIDs) {
        id value = attributes[identifier].value;
        if ([value isKindOfClass:[NSString class]] && [(NSString *)value length] > 0) {
            [texts addObject:value];
        }
    }

    if (detail.customDisplayTitle.length > 0) {
        [texts addObject:detail.customDisplayTitle];
    } else if (item.customDisplayTitle.length > 0) {
        [texts addObject:item.customDisplayTitle];
    }

    return texts.array;
}

- (NSArray<NSString *> *)_diagnosticNotesForMatchesCount:(NSUInteger)matchesCount maxMatches:(NSUInteger)maxMatches {
    if (matchesCount == 0) {
        return @[@"No view matched the requested filters. Returning the current page excerpt instead."];
    }
    if (matchesCount >= maxMatches) {
        return @[@"Match results were truncated to the requested max_matches limit."];
    }
    return @[];
}

- (NSArray<NSDictionary<NSString *, id> *> *)_hierarchyExcerptFromRoots:(NSArray<LookinDisplayItem *> *)roots
                                                                 matches:(NSArray<LookinDisplayItem *> *)matches
                                                              itemsByOID:(NSDictionary<NSNumber *, LookinDisplayItem *> *)itemsByOID
                                                              detailsByOID:(NSDictionary<NSNumber *, LookinDisplayItemDetail *> *)detailsByOID
                                                            maximumDepth:(NSUInteger)maximumDepth {
    NSMutableSet<NSNumber *> *includedOIDs = [NSMutableSet set];
    NSMutableDictionary<NSNumber *, NSNumber *> *childDepthByOID = [NSMutableDictionary dictionary];

    if (matches.count == 0) {
        for (LookinDisplayItem *root in roots) {
            [self _collectSubtreeFromItem:root depth:maximumDepth intoSet:includedOIDs];
        }
    } else {
        for (LookinDisplayItem *match in matches) {
            LookinDisplayItem *cursor = match;
            while (cursor != nil) {
                unsigned long oid = [self _oidForItem:cursor];
                if (oid != 0) {
                    [includedOIDs addObject:@(oid)];
                }
                cursor = cursor.superItem;
            }

            unsigned long matchOID = [self _oidForItem:match];
            if (matchOID != 0) {
                childDepthByOID[@(matchOID)] = @(maximumDepth);
                [self _collectNearbySiblingsForItem:match intoSet:includedOIDs];
            }
        }
    }

    NSMutableArray<NSDictionary<NSString *, id> *> *excerpt = [NSMutableArray array];
    NSUInteger remainingNodes = LKMBridgeMaxExcerptNodes;
    for (LookinDisplayItem *root in roots) {
        NSDictionary<NSString *, id> *node = [self _excerptNodeFromItem:root
                                                            includedOIDs:includedOIDs
                                                           childDepthByOID:childDepthByOID
                                                             detailsByOID:detailsByOID
                                                          remainingNodes:&remainingNodes];
        if (node != nil) {
            [excerpt addObject:node];
        }
        if (remainingNodes == 0) {
            break;
        }
    }
    return excerpt;
}

- (NSDictionary<NSString *, id> *)_excerptNodeFromItem:(LookinDisplayItem *)item
                                            includedOIDs:(NSMutableSet<NSNumber *> *)includedOIDs
                                         childDepthByOID:(NSMutableDictionary<NSNumber *, NSNumber *> *)childDepthByOID
                                             detailsByOID:(NSDictionary<NSNumber *, LookinDisplayItemDetail *> *)detailsByOID
                                          remainingNodes:(NSUInteger *)remainingNodes {
    if (*remainingNodes == 0) {
        return nil;
    }

    unsigned long oid = [self _oidForItem:item];
    NSNumber *oidNumber = oid != 0 ? @(oid) : nil;
    BOOL explicitlyIncluded = oidNumber != nil && [includedOIDs containsObject:oidNumber];
    NSUInteger descendantDepth = oidNumber != nil ? childDepthByOID[oidNumber].unsignedIntegerValue : 0;

    NSMutableArray<NSDictionary<NSString *, id> *> *children = [NSMutableArray array];
    if (descendantDepth > 0) {
        for (LookinDisplayItem *child in item.subitems ?: @[]) {
            unsigned long childOID = [self _oidForItem:child];
            if (childOID != 0) {
                [includedOIDs addObject:@(childOID)];
                childDepthByOID[@(childOID)] = @(descendantDepth - 1);
            }
        }
    }

    for (LookinDisplayItem *child in item.subitems ?: @[]) {
        NSDictionary<NSString *, id> *childNode = [self _excerptNodeFromItem:child
                                                                  includedOIDs:includedOIDs
                                                               childDepthByOID:childDepthByOID
                                                                   detailsByOID:detailsByOID
                                                                remainingNodes:remainingNodes];
        if (childNode != nil) {
            [children addObject:childNode];
        }
    }

    if (!explicitlyIncluded && children.count == 0) {
        return nil;
    }

    *remainingNodes -= 1;
    LookinDisplayItemDetail *detail = detailsByOID[oidNumber];
    NSMutableDictionary<NSString *, id> *node = [[self _baseNodeDictionaryForItem:item detail:detail isMatch:NO] mutableCopy];
    node[@"children"] = children;
    return node;
}

- (void)_collectSubtreeFromItem:(LookinDisplayItem *)item depth:(NSUInteger)depth intoSet:(NSMutableSet<NSNumber *> *)set {
    unsigned long oid = [self _oidForItem:item];
    if (oid != 0) {
        [set addObject:@(oid)];
    }
    if (depth == 0) {
        return;
    }
    for (LookinDisplayItem *child in item.subitems ?: @[]) {
        [self _collectSubtreeFromItem:child depth:(depth - 1) intoSet:set];
    }
}

- (void)_collectNearbySiblingsForItem:(LookinDisplayItem *)item intoSet:(NSMutableSet<NSNumber *> *)set {
    NSArray<LookinDisplayItem *> *siblings = item.superItem != nil ? item.superItem.subitems : nil;
    if (siblings.count == 0) {
        return;
    }

    NSUInteger index = [siblings indexOfObject:item];
    if (index == NSNotFound) {
        return;
    }

    NSInteger start = MAX((NSInteger)index - 2, 0);
    NSInteger end = MIN((NSInteger)index + 2, (NSInteger)siblings.count - 1);
    for (NSInteger idx = start; idx <= end; idx++) {
        unsigned long oid = [self _oidForItem:siblings[(NSUInteger)idx]];
        if (oid != 0) {
            [set addObject:@(oid)];
        }
    }
}

#pragma mark - Serialization Helpers

- (NSDictionary<NSString *, id> *)_rectDictionary:(CGRect)rect {
    return @{
        @"x": @(rect.origin.x),
        @"y": @(rect.origin.y),
        @"width": @(rect.size.width),
        @"height": @(rect.size.height)
    };
}

- (id)_jsonValueFromObject:(id)object {
    if (object == nil) {
        return [NSNull null];
    }
    if ([object isKindOfClass:[NSString class]] ||
        [object isKindOfClass:[NSNumber class]] ||
        [object isKindOfClass:[NSNull class]]) {
        return object;
    }
    if ([object isKindOfClass:[NSArray class]]) {
        NSMutableArray *array = [NSMutableArray array];
        for (id value in (NSArray *)object) {
            [array addObject:[self _jsonValueFromObject:value]];
        }
        return array;
    }
    if ([object isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
        [(NSDictionary *)object enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull value, BOOL * _Nonnull stop) {
            dictionary[[key description]] = [self _jsonValueFromObject:value];
        }];
        return dictionary;
    }
    if ([object isKindOfClass:[NSValue class]]) {
        const char *objCType = [(NSValue *)object objCType];
        if (strcmp(objCType, @encode(CGRect)) == 0) {
            return [self _rectDictionary:[(NSValue *)object rectValue]];
        }
        if (strcmp(objCType, @encode(CGSize)) == 0) {
            CGSize size = [(NSValue *)object sizeValue];
            return @{@"width": @(size.width), @"height": @(size.height)};
        }
        if (strcmp(objCType, @encode(CGPoint)) == 0) {
            CGPoint point = [(NSValue *)object pointValue];
            return @{@"x": @(point.x), @"y": @(point.y)};
        }
        return [(NSValue *)object description];
    }
    return [object description];
}

- (NSDictionary<NSString *, id> *)_encodedImageDictionaryFromImage:(NSImage *)image {
    if (image == nil) {
        return nil;
    }

    NSData *tiffData = image.TIFFRepresentation;
    if (tiffData.length == 0) {
        return nil;
    }

    NSBitmapImageRep *bitmap = [NSBitmapImageRep imageRepWithData:tiffData];
    NSData *pngData = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    NSData *finalData = pngData ?: tiffData;
    NSString *mimeType = pngData != nil ? @"image/png" : @"image/tiff";

    return @{
        @"mime_type": mimeType,
        @"base64_data": [finalData base64EncodedStringWithOptions:0],
        @"width": @(image.size.width),
        @"height": @(image.size.height)
    };
}

#pragma mark - Constraint Helpers

- (NSString *)_constraintSummary:(LookinAutoLayoutConstraint *)constraint {
    NSMutableString *summary = [NSMutableString string];
    [summary appendFormat:@"%@.%@ %@",
     [self _constraintItemDescriptionForObject:constraint.firstItem type:constraint.firstItemType],
     [self _constraintAttributeName:constraint.firstAttribute],
     [self _constraintRelationSymbol:constraint.relation]];

    if (constraint.secondAttribute == 0) {
        [summary appendFormat:@" %@", @(constraint.constant)];
    } else {
        [summary appendFormat:@" %@.%@",
         [self _constraintItemDescriptionForObject:constraint.secondItem type:constraint.secondItemType],
         [self _constraintAttributeName:constraint.secondAttribute]];
        if (constraint.multiplier != 1) {
            [summary appendFormat:@" * %@", @(constraint.multiplier)];
        }
        if (constraint.constant > 0) {
            [summary appendFormat:@" + %@", @(constraint.constant)];
        } else if (constraint.constant < 0) {
            [summary appendFormat:@" - %@", @(-constraint.constant)];
        }
    }

    if (constraint.priority != 1000) {
        [summary appendFormat:@" @ %@", @(constraint.priority)];
    }
    return summary;
}

- (NSString *)_constraintItemDescriptionForObject:(LookinObject *)object type:(LookinConstraintItemType)type {
    switch (type) {
        case LookinConstraintItemTypeNil:
            return @"nil";
        case LookinConstraintItemTypeSelf:
            return @"self";
        case LookinConstraintItemTypeSuper:
            return @"super";
        case LookinConstraintItemTypeView:
        case LookinConstraintItemTypeLayoutGuide:
            return [NSString stringWithFormat:@"(%@*)", object.rawClassName ?: @"Unknown"];
        default:
            return object.rawClassName ?: @"unknown";
    }
}

- (NSString *)_constraintItemTypeString:(LookinConstraintItemType)type {
    switch (type) {
        case LookinConstraintItemTypeNil:
            return @"nil";
        case LookinConstraintItemTypeSelf:
            return @"self";
        case LookinConstraintItemTypeSuper:
            return @"super";
        case LookinConstraintItemTypeView:
            return @"view";
        case LookinConstraintItemTypeLayoutGuide:
            return @"layout_guide";
        default:
            return @"unknown";
    }
}

- (NSString *)_constraintAttributeName:(NSInteger)attribute {
    switch (attribute) {
        case 0: return @"notAnAttribute";
        case 1: return @"left";
        case 2: return @"right";
        case 3: return @"top";
        case 4: return @"bottom";
        case 5: return @"leading";
        case 6: return @"trailing";
        case 7: return @"width";
        case 8: return @"height";
        case 9: return @"centerX";
        case 10: return @"centerY";
        case 11: return @"lastBaseline";
        case 12: return @"firstBaseline";
        case 13: return @"leftMargin";
        case 14: return @"rightMargin";
        case 15: return @"topMargin";
        case 16: return @"bottomMargin";
        case 17: return @"leadingMargin";
        case 18: return @"trailingMargin";
        case 19: return @"centerXWithinMargins";
        case 20: return @"centerYWithinMargins";
        case 32: return @"minX";
        case 33: return @"minY";
        case 34: return @"midX";
        case 35: return @"midY";
        case 36: return @"maxX";
        case 37: return @"maxY";
        default: return [NSString stringWithFormat:@"unknown(%@)", @(attribute)];
    }
}

- (NSString *)_constraintRelationString:(NSLayoutRelation)relation {
    switch (relation) {
        case NSLayoutRelationLessThanOrEqual:
            return @"less_than_or_equal";
        case NSLayoutRelationEqual:
            return @"equal";
        case NSLayoutRelationGreaterThanOrEqual:
            return @"greater_than_or_equal";
    }
}

- (NSString *)_constraintRelationSymbol:(NSLayoutRelation)relation {
    switch (relation) {
        case NSLayoutRelationLessThanOrEqual:
            return @"<=";
        case NSLayoutRelationEqual:
            return @"=";
        case NSLayoutRelationGreaterThanOrEqual:
            return @">=";
    }
}

#pragma mark - Generic Helpers

- (unsigned long)_oidForItem:(LookinDisplayItem *)item {
    if (item.layerObject.oid != 0) {
        return item.layerObject.oid;
    }
    return item.viewObject.oid;
}

- (NSString *)_appIDForAppInfo:(LookinAppInfo *)appInfo endpoint:(LKMBridgeEndpoint *)endpoint {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    [parts addObject:[endpoint.transport isEqualToString:@"usb"] ? @"usb" : @"sim"];
    if (endpoint.deviceID != nil) {
        [parts addObject:endpoint.deviceID.stringValue];
    }
    [parts addObject:[NSString stringWithFormat:@"%d", endpoint.port]];
    [parts addObject:[NSString stringWithFormat:@"%lu", (unsigned long)appInfo.appInfoIdentifier]];
    [parts addObject:appInfo.appBundleIdentifier ?: @""];
    return [parts componentsJoinedByString:@":"];
}

- (NSString *)_stringForKey:(NSString *)key inDictionary:(NSDictionary *)dictionary {
    id value = dictionary[key];
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

- (BOOL)_boolForKey:(NSString *)key inDictionary:(NSDictionary *)dictionary defaultValue:(BOOL)defaultValue {
    id value = dictionary[key];
    if ([value respondsToSelector:@selector(boolValue)]) {
        return [value boolValue];
    }
    return defaultValue;
}

- (NSUInteger)_unsignedIntegerForKey:(NSString *)key inDictionary:(NSDictionary *)dictionary defaultValue:(NSUInteger)defaultValue {
    id value = dictionary[key];
    if ([value respondsToSelector:@selector(unsignedIntegerValue)]) {
        return [value unsignedIntegerValue];
    }
    return defaultValue;
}

- (NSError *)_bridgeErrorWithCode:(LKMBridgeErrorCode)code description:(NSString *)description {
    return [NSError errorWithDomain:LKMBridgeErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: description ?: @"Lookin bridge error."}];
}

#pragma mark - <Lookin_PTChannelDelegate>

- (BOOL)ioFrameChannel:(Lookin_PTChannel *)channel shouldAcceptFrameOfType:(uint32_t)type tag:(uint32_t)tag payloadSize:(uint32_t)payloadSize {
    (void)payloadSize;
    NSString *key = [self _requestKeyForChannelUniqueID:channel.uniqueID type:type tag:tag];
    @synchronized (self) {
        return self.pendingRequests[key] != nil;
    }
}

- (void)ioFrameChannel:(Lookin_PTChannel *)channel didReceiveFrameOfType:(uint32_t)type tag:(uint32_t)tag payload:(Lookin_PTData *)payload {
    NSString *key = [self _requestKeyForChannelUniqueID:channel.uniqueID type:type tag:tag];

    NSData *data = [NSData dataWithContentsOfDispatchData:payload.dispatchData];
    NSError *decodeError = nil;
    LookinConnectionResponseAttachment *attachment = [NSKeyedUnarchiver unarchivedObjectOfClass:[NSObject class] fromData:data error:&decodeError];

    @synchronized (self) {
        LKMBridgePendingRequest *request = self.pendingRequests[key];
        if (request == nil || request.finished) {
            return;
        }

        if (decodeError != nil || ![attachment isKindOfClass:[LookinConnectionResponseAttachment class]]) {
            request.error = decodeError ?: [self _bridgeErrorWithCode:LKMBridgeErrorCodeDisconnected description:@"Failed to decode a response frame from the inspected app."];
            request.finished = YES;
            dispatch_semaphore_signal(request.semaphore);
            return;
        }

        if (attachment.appIsInBackground) {
            request.error = [self _bridgeErrorWithCode:LKMBridgeErrorCodeDisconnected description:@"The inspected app is in the background and cannot respond right now."];
            request.finished = YES;
            dispatch_semaphore_signal(request.semaphore);
            return;
        }

        [request.attachments addObject:attachment];
        LKMBridgeDebugLog(@"frame received type=%u tag=%u channel=%d dataTotal=%@ currentData=%@", type, tag, channel.uniqueID, @(attachment.dataTotalCount), @(attachment.currentDataCount));
        if (attachment.dataTotalCount > 0) {
            request.expectedDataCount = attachment.dataTotalCount;
            request.receivedDataCount += attachment.currentDataCount;
            if (request.receivedDataCount >= request.expectedDataCount) {
                request.finished = YES;
                dispatch_semaphore_signal(request.semaphore);
            }
        } else {
            request.finished = YES;
            dispatch_semaphore_signal(request.semaphore);
        }
    }
}

- (void)ioFrameChannel:(Lookin_PTChannel *)channel didEndWithError:(NSError *)error {
    @synchronized (self) {
        LKMBridgeSession *session = self.sessionsByChannelID[@(channel.uniqueID)];
        session.disconnected = YES;
        if (session != nil && [self.selectedAppID isEqualToString:session.appID]) {
            self.selectedAppID = nil;
        }

        NSArray<NSString *> *pendingKeys = self.pendingRequests.allKeys;
        for (NSString *key in pendingKeys) {
            LKMBridgePendingRequest *request = self.pendingRequests[key];
            if (request.channelUniqueID != channel.uniqueID || request.finished) {
                continue;
            }
            request.error = error ?: [self _bridgeErrorWithCode:LKMBridgeErrorCodeDisconnected description:@"The inspected app disconnected."];
            request.finished = YES;
            dispatch_semaphore_signal(request.semaphore);
        }
    }
    LKMBridgeDebugLog(@"channel ended uniqueID=%d error=%@", channel.uniqueID, error);
}

@end
