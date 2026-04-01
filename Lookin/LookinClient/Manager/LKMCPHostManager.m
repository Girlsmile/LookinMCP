//
//  LKMCPHostManager.m
//  Lookin
//

#import "LKMCPHostManager.h"
#import <AppKit/AppKit.h>

NSNotificationName const LKMCPHostManagerDidUpdateNotification = @"LKMCPHostManagerDidUpdateNotification";

static NSString * const LKMCPHost = @"127.0.0.1";
static NSString * const LKMCPBundledExecutableName = @"lookin-mcp";
static uint16_t const LKMCPPort = 3846;
static NSTimeInterval const LKMCPPollInterval = 2;
static NSInteger const LKMCPMaxConsecutiveStatusFailures = 3;
static NSTimeInterval const LKMCPReconnectBaseDelay = 1;
static NSTimeInterval const LKMCPReconnectMaxDelay = 10;

static void LKMCPHostLog(NSString *message) {
    if (message.length == 0) {
        return;
    }
    NSLog(@"[LookinMCPHost] %@", message);
}

@interface LKMCPHostManager ()

@property(nonatomic, assign) LKMCPHostState state;
@property(nonatomic, copy) NSString *statusText;
@property(nonatomic, copy) NSString *statusSummaryText;
@property(nonatomic, copy) NSString *serverAddress;
@property(nonatomic, copy, nullable) NSString *snapshotID;
@property(nonatomic, copy, nullable) NSString *capturedAtText;
@property(nonatomic, copy, nullable) NSString *lastRequestAtText;
@property(nonatomic, copy, nullable) NSString *lastErrorText;
@property(nonatomic, copy) NSString *snapshotRootPath;
@property(nonatomic, assign) BOOL snapshotAvailable;
@property(nonatomic, assign) BOOL snapshotStale;
@property(nonatomic, assign) BOOL enabled;
@property(nonatomic, strong, nullable) NSTask *task;
@property(nonatomic, strong) NSTimer *pollTimer;
@property(nonatomic, strong) NSURLSession *session;
@property(nonatomic, strong) NSPipe *stderrPipe;
@property(nonatomic, assign) BOOL stopRequestedByUser;
@property(nonatomic, assign) BOOL autoReconnectEnabled;
@property(nonatomic, assign) BOOL restartPending;
@property(nonatomic, assign) NSInteger reconnectAttempt;
@property(nonatomic, assign) NSInteger consecutiveStatusFailures;
@property(nonatomic, strong, nullable) NSTimer *reconnectTimer;

@end

@implementation LKMCPHostManager

+ (instancetype)sharedInstance {
    static dispatch_once_t onceToken;
    static LKMCPHostManager *instance = nil;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        _serverAddress = [NSString stringWithFormat:@"http://%@:%hu/mcp", LKMCPHost, LKMCPPort];
        _snapshotRootPath = @"";
        _statusText = @"未启动";
        _statusSummaryText = @"Lookin 当前未托管 MCP Host";
        _state = LKMCPHostStateOff;
        _autoReconnectEnabled = YES;
        _session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_handleApplicationWillTerminate) name:NSApplicationWillTerminateNotification object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.pollTimer invalidate];
    [self.reconnectTimer invalidate];
    [self.session invalidateAndCancel];
}

- (void)startHost {
    [self.reconnectTimer invalidate];
    self.reconnectTimer = nil;

    if (self.task && self.task.isRunning) {
        [self _pollStatus];
        return;
    }

    NSString *resolutionMessage = nil;
    NSString *executablePath = [self _resolveExecutablePathWithErrorMessage:&resolutionMessage];
    if (!executablePath) {
        [self _applyLocalError:resolutionMessage ?: @"未找到 lookin-mcp 可执行文件。发布版请确认 Lookin.app 已内嵌 helper；开发态请先执行 `swift build`，或设置环境变量 LOOKIN_MCP_EXECUTABLE。"];
        return;
    }
    LKMCPHostLog([NSString stringWithFormat:@"使用 helper: %@", executablePath]);

    self.stopRequestedByUser = NO;
    self.restartPending = NO;
    self.autoReconnectEnabled = YES;
    self.consecutiveStatusFailures = 0;
    self.lastErrorText = nil;
    [self _applyState:LKMCPHostStateStarting summary:@"正在启动本地 MCP Host"];

    NSTask *task = [[NSTask alloc] init];
    task.launchPath = executablePath;
    task.arguments = @[@"--transport", @"http", @"--host", LKMCPHost, @"--port", [NSString stringWithFormat:@"%hu", LKMCPPort]];
    task.currentDirectoryPath = NSFileManager.defaultManager.currentDirectoryPath;

    NSMutableDictionary *environment = [NSMutableDictionary dictionaryWithDictionary:NSProcessInfo.processInfo.environment];
    environment[@"LOOKIN_SNAPSHOT_ROOT"] = environment[@"LOOKIN_SNAPSHOT_ROOT"] ?: @"";
    task.environment = environment;

    NSPipe *stderrPipe = [NSPipe pipe];
    task.standardError = stderrPipe;
    self.stderrPipe = stderrPipe;
    __weak typeof(self) weakSelf = self;
    stderrPipe.fileHandleForReading.readabilityHandler = ^(NSFileHandle * _Nonnull handle) {
        NSData *data = [handle availableData];
        if (data.length == 0) {
            return;
        }
        NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (text.length > 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf _recordErrorText:text];
            });
        }
    };

    task.terminationHandler = ^(NSTask * _Nonnull exitedTask) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf _handleTaskDidTerminate:exitedTask];
        });
    };

    @try {
        [task launch];
    } @catch (NSException *exception) {
        NSString *message = [NSString stringWithFormat:@"MCP helper 启动失败：%@", exception.reason ?: @"未知异常"];
        LKMCPHostLog(message);
        [self _applyLocalError:message];
        return;
    }

    self.task = task;
    [self _ensurePolling];
    [self _pollStatus];
}

- (void)stopHost {
    self.stopRequestedByUser = YES;
    self.autoReconnectEnabled = NO;
    self.restartPending = NO;
    self.reconnectAttempt = 0;
    self.consecutiveStatusFailures = 0;
    [self.pollTimer invalidate];
    self.pollTimer = nil;
    [self.reconnectTimer invalidate];
    self.reconnectTimer = nil;
    self.stderrPipe.fileHandleForReading.readabilityHandler = nil;
    [self.task terminate];
    self.task = nil;
    self.stderrPipe = nil;
    self.snapshotID = nil;
    self.capturedAtText = nil;
    self.lastRequestAtText = nil;
    self.snapshotAvailable = NO;
    self.snapshotStale = YES;
    self.snapshotRootPath = @"";
    self.lastErrorText = nil;
    self.enabled = NO;
    [self _applyState:LKMCPHostStateOff summary:@"Lookin 当前未托管 MCP Host"];
}

- (void)toggleHost {
    if (self.enabled || self.state == LKMCPHostStateStarting) {
        [self stopHost];
    } else {
        [self startHost];
    }
}

- (void)copyAddressToPasteboard {
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];
    [pasteboard setString:self.serverAddress forType:NSPasteboardTypeString];
}

- (void)refreshStatus {
    self.autoReconnectEnabled = YES;
    self.consecutiveStatusFailures = 0;
    if (self.task.isRunning) {
        [self _applyState:LKMCPHostStateStarting summary:@"正在刷新 MCP 状态"];
        [self _pollStatus];
        return;
    }
    [self startHost];
}

- (void)reconnectHost {
    self.autoReconnectEnabled = YES;
    self.reconnectAttempt = 0;
    self.consecutiveStatusFailures = 0;
    [self.reconnectTimer invalidate];
    self.reconnectTimer = nil;

    if (self.task.isRunning) {
        self.stopRequestedByUser = NO;
        self.restartPending = YES;
        [self _applyState:LKMCPHostStateStarting summary:@"正在重连 MCP Host"];
        [self.task terminate];
        return;
    }
    [self startHost];
}

- (NSColor *)statusColor {
    switch (self.state) {
        case LKMCPHostStateStarting:
            return [NSColor systemBlueColor];
        case LKMCPHostStateReady:
            return [NSColor systemGreenColor];
        case LKMCPHostStateConnected:
            return [NSColor systemTealColor];
        case LKMCPHostStateStale:
            return [NSColor systemOrangeColor];
        case LKMCPHostStateError:
            return [NSColor systemRedColor];
        case LKMCPHostStateOff:
        default:
            return [NSColor secondaryLabelColor];
    }
}

#pragma mark - Private

- (void)_ensurePolling {
    if (self.pollTimer) {
        return;
    }
    self.pollTimer = [NSTimer scheduledTimerWithTimeInterval:LKMCPPollInterval target:self selector:@selector(_pollStatus) userInfo:nil repeats:YES];
}

- (void)_pollStatus {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://%@:%hu/status", LKMCPHost, LKMCPPort]];
    if (!url) {
        return;
    }

    NSURLSessionDataTask *task = [self.session dataTaskWithURL:url completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                if (self.task.isRunning) {
                    NSString *message = error.localizedDescription ?: @"状态接口不可达";
                    self.consecutiveStatusFailures += 1;
                    if (self.state == LKMCPHostStateStarting) {
                        [self _applyState:LKMCPHostStateStarting summary:@"正在等待 MCP Host 就绪"];
                    } else if (self.consecutiveStatusFailures >= LKMCPMaxConsecutiveStatusFailures) {
                        [self _applyLocalError:[NSString stringWithFormat:@"状态检查连续失败 %ld 次，准备自动重连。%@", (long)self.consecutiveStatusFailures, message]];
                        [self _scheduleReconnectWithReason:@"状态检查连续失败" immediate:NO];
                    } else {
                        [self _applyState:self.state summary:[NSString stringWithFormat:@"状态检查失败，正在重试（%ld/%ld）", (long)self.consecutiveStatusFailures, (long)LKMCPMaxConsecutiveStatusFailures]];
                    }
                }
                return;
            }

            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
            if (![httpResponse isKindOfClass:[NSHTTPURLResponse class]] || httpResponse.statusCode != 200 || data.length == 0) {
                self.consecutiveStatusFailures += 1;
                if (self.consecutiveStatusFailures >= LKMCPMaxConsecutiveStatusFailures) {
                    [self _applyLocalError:@"MCP 状态接口连续返回无效响应，准备自动重连。"];
                    [self _scheduleReconnectWithReason:@"状态接口无效" immediate:NO];
                }
                return;
            }

            NSError *jsonError = nil;
            NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:&jsonError];
            if (![dict isKindOfClass:[NSDictionary class]] || jsonError) {
                self.consecutiveStatusFailures += 1;
                if (self.consecutiveStatusFailures >= LKMCPMaxConsecutiveStatusFailures) {
                    [self _applyLocalError:@"MCP 状态接口连续返回无法解析的 JSON，准备自动重连。"];
                    [self _scheduleReconnectWithReason:@"状态 JSON 非法" immediate:NO];
                }
                return;
            }
            [self _applyRemoteStatus:dict];
        });
    }];
    [task resume];
}

- (void)_applyRemoteStatus:(NSDictionary *)dict {
    self.enabled = YES;
    self.restartPending = NO;
    self.consecutiveStatusFailures = 0;
    self.reconnectAttempt = 0;
    [self.reconnectTimer invalidate];
    self.reconnectTimer = nil;
    self.snapshotID = [dict[@"snapshot_id"] isKindOfClass:[NSString class]] ? dict[@"snapshot_id"] : nil;
    self.capturedAtText = [dict[@"captured_at"] isKindOfClass:[NSString class]] ? dict[@"captured_at"] : nil;
    self.lastRequestAtText = [dict[@"last_request_at"] isKindOfClass:[NSString class]] ? dict[@"last_request_at"] : nil;
    self.lastErrorText = [dict[@"last_error"] isKindOfClass:[NSString class]] ? dict[@"last_error"] : nil;
    self.snapshotRootPath = [dict[@"snapshot_root"] isKindOfClass:[NSString class]] ? dict[@"snapshot_root"] : @"";
    self.snapshotAvailable = [dict[@"snapshot_available"] boolValue];
    self.snapshotStale = [dict[@"snapshot_is_stale"] boolValue];

    NSString *remoteState = [dict[@"state"] isKindOfClass:[NSString class]] ? dict[@"state"] : @"stale";
    if ([remoteState isEqualToString:@"connected"]) {
        [self _applyState:LKMCPHostStateConnected summary:@"最近有 MCP 请求，服务与快照均可用"];
    } else if ([remoteState isEqualToString:@"ready"]) {
        [self _applyState:LKMCPHostStateReady summary:@"服务可用，等待 MCP 客户端连接"];
    } else if ([remoteState isEqualToString:@"stale"]) {
        NSString *summary = self.snapshotAvailable ? @"服务在线，但 snapshot 已过期" : @"服务在线，但当前没有可读 snapshot";
        [self _applyState:LKMCPHostStateStale summary:summary];
    } else {
        [self _applyState:LKMCPHostStateReady summary:@"服务可用，等待 MCP 客户端连接"];
    }
}

- (void)_applyLocalError:(NSString *)message {
    self.enabled = NO;
    self.lastErrorText = message;
    [self _applyState:LKMCPHostStateError summary:message];
}

- (void)_recordErrorText:(NSString *)text {
    NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) {
        return;
    }
    LKMCPHostLog([NSString stringWithFormat:@"helper stderr: %@", trimmed]);
    self.lastErrorText = trimmed;
    if (self.state != LKMCPHostStateStarting) {
        [self _notify];
    }
}

- (void)_handleTaskDidTerminate:(NSTask *)task {
    self.stderrPipe.fileHandleForReading.readabilityHandler = nil;
    self.stderrPipe = nil;
    self.task = nil;
    [self.pollTimer invalidate];
    self.pollTimer = nil;
    self.enabled = NO;
    if (self.stopRequestedByUser) {
        self.stopRequestedByUser = NO;
        [self _applyState:LKMCPHostStateOff summary:@"Lookin 当前未托管 MCP Host"];
        return;
    }

    if (self.restartPending) {
        self.restartPending = NO;
        [self _scheduleReconnectWithReason:@"手动重连" immediate:YES];
        return;
    }

    NSString *message = self.lastErrorText.length > 0 ? self.lastErrorText : [NSString stringWithFormat:@"MCP Host 已退出，退出码 %d", task.terminationStatus];
    [self _applyLocalError:message];
    [self _scheduleReconnectWithReason:@"进程意外退出" immediate:NO];
}

- (void)_handleApplicationWillTerminate {
    if (self.task.isRunning) {
        [self stopHost];
    }
}

- (void)_applyState:(LKMCPHostState)state summary:(NSString *)summary {
    self.state = state;
    self.statusText = [self.class _textForState:state];
    self.statusSummaryText = summary;
    [self _notify];
}

- (void)_scheduleReconnectWithReason:(NSString *)reason immediate:(BOOL)immediate {
    if (!self.autoReconnectEnabled) {
        return;
    }

    [self.reconnectTimer invalidate];
    self.reconnectTimer = nil;

    NSTimeInterval delay = immediate ? 0.15 : MIN(LKMCPReconnectBaseDelay * pow(2, self.reconnectAttempt), LKMCPReconnectMaxDelay);
    if (!immediate) {
        self.reconnectAttempt += 1;
    }
    [self _applyState:LKMCPHostStateStarting summary:[NSString stringWithFormat:@"%@，%.1f 秒后自动重连", reason, delay]];

    self.reconnectTimer = [NSTimer scheduledTimerWithTimeInterval:delay target:self selector:@selector(_handleReconnectTimer) userInfo:nil repeats:NO];
}

- (void)_handleReconnectTimer {
    [self.reconnectTimer invalidate];
    self.reconnectTimer = nil;
    if (!self.autoReconnectEnabled || self.task.isRunning) {
        return;
    }
    [self startHost];
}

- (void)_notify {
    [[NSNotificationCenter defaultCenter] postNotificationName:LKMCPHostManagerDidUpdateNotification object:self];
}

- (NSString *)_resolveExecutablePathWithErrorMessage:(NSString * _Nullable __autoreleasing *)errorMessage {
    NSFileManager *fileManager = NSFileManager.defaultManager;
    NSString *fromEnv = NSProcessInfo.processInfo.environment[@"LOOKIN_MCP_EXECUTABLE"];
    if (fromEnv.length > 0) {
        NSString *candidate = [fromEnv stringByStandardizingPath];
        BOOL isDirectory = NO;
        if ([fileManager fileExistsAtPath:candidate isDirectory:&isDirectory]) {
            if (!isDirectory && [fileManager isExecutableFileAtPath:candidate]) {
                return candidate;
            }
            if (errorMessage) {
                *errorMessage = [NSString stringWithFormat:@"`LOOKIN_MCP_EXECUTABLE` 指向的文件不可执行：%@", candidate];
            }
        } else if (errorMessage) {
            *errorMessage = [NSString stringWithFormat:@"`LOOKIN_MCP_EXECUTABLE` 指向的文件不存在：%@", candidate];
        }
        return nil;
    }

    NSString *bundledPath = [self.class _bundledExecutablePath];
    NSString *bundledError = nil;
    if (bundledPath.length > 0) {
        BOOL isDirectory = NO;
        if ([fileManager fileExistsAtPath:bundledPath isDirectory:&isDirectory]) {
            if (!isDirectory && [fileManager isExecutableFileAtPath:bundledPath]) {
                return bundledPath;
            }
            bundledError = [NSString stringWithFormat:@"Lookin.app 内嵌 MCP helper 不可执行：%@", bundledPath];
        } else if ([self.class _mainBundleLooksLikeApp]) {
            bundledError = [NSString stringWithFormat:@"Lookin.app 缺少内嵌 MCP helper：%@", bundledPath];
        }
    }

    NSMutableOrderedSet<NSString *> *searchRoots = [NSMutableOrderedSet orderedSet];
    [searchRoots addObject:NSFileManager.defaultManager.currentDirectoryPath ?: @""];
    [searchRoots addObject:[[NSBundle mainBundle] bundlePath] ?: @""];
    [searchRoots addObject:[[NSBundle mainBundle] executablePath] ?: @""];

    // 开发态下优先使用编译时源码路径反推仓库根目录，避免 app 的 cwd 漂移导致找不到 `.build/debug/lookin-mcp`。
    NSString *compiledSourcePath = [NSString stringWithUTF8String:__FILE__];
    if (compiledSourcePath.length > 0) {
        [searchRoots addObject:[compiledSourcePath stringByDeletingLastPathComponent]];
    }

    for (NSString *root in searchRoots) {
        for (NSString *candidate in [self.class _candidateExecutablePathsFromSeedPath:root]) {
            if ([self.class _isExecutableFile:candidate]) {
                return candidate;
            }
        }
    }

    if (errorMessage) {
        *errorMessage = bundledError ?: @"未找到 lookin-mcp 可执行文件。发布版请确认 Lookin.app 已内嵌 helper；开发态请先执行 `swift build`，或设置环境变量 LOOKIN_MCP_EXECUTABLE。";
    }
    return nil;
}

+ (BOOL)_isExecutableFile:(NSString *)path {
    if (path.length == 0) {
        return NO;
    }
    return [[NSFileManager defaultManager] isExecutableFileAtPath:path];
}

+ (BOOL)_mainBundleLooksLikeApp {
    NSString *bundlePath = [NSBundle mainBundle].bundlePath;
    return [[bundlePath pathExtension].lowercaseString isEqualToString:@"app"];
}

+ (NSString *)_bundledExecutablePath {
    NSString *pluginsPath = [[NSBundle mainBundle] builtInPlugInsPath];
    if (pluginsPath.length == 0) {
        return nil;
    }
    return [pluginsPath stringByAppendingPathComponent:LKMCPBundledExecutableName];
}

+ (NSArray<NSString *> *)_candidateExecutablePathsFromSeedPath:(NSString *)seedPath {
    if (seedPath.length == 0) {
        return @[];
    }

    NSMutableOrderedSet<NSString *> *ret = [NSMutableOrderedSet orderedSet];
    NSString *cursor = [seedPath stringByStandardizingPath];
    BOOL isDirectory = NO;
    if ([[NSFileManager defaultManager] fileExistsAtPath:cursor isDirectory:&isDirectory] && !isDirectory) {
        cursor = [cursor stringByDeletingLastPathComponent];
    }

    for (NSInteger depth = 0; depth < 8 && cursor.length > 1; depth++) {
        [ret addObject:[cursor stringByAppendingPathComponent:@".build/debug/lookin-mcp"]];
        [ret addObject:[cursor stringByAppendingPathComponent:@"LookinMCP/.build/debug/lookin-mcp"]];
        [ret addObject:[cursor stringByAppendingPathComponent:@"../.build/debug/lookin-mcp"]];
        cursor = [cursor stringByDeletingLastPathComponent];
    }

    return ret.array;
}

+ (NSString *)_textForState:(LKMCPHostState)state {
    switch (state) {
        case LKMCPHostStateStarting:
            return @"启动中";
        case LKMCPHostStateReady:
            return @"就绪";
        case LKMCPHostStateConnected:
            return @"活跃";
        case LKMCPHostStateStale:
            return @"过期";
        case LKMCPHostStateError:
            return @"错误";
        case LKMCPHostStateOff:
        default:
            return @"未启动";
    }
}

@end
