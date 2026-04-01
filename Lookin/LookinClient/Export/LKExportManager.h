//
//  LKExportManager.h
//  Lookin
//
//  Created by Li Kai on 2019/5/12.
//  https://lookin.work
//

#import <Foundation/Foundation.h>

@class LookinHierarchyInfo, LookinDisplayItem;

@interface LKExportManager : NSObject

+ (instancetype)sharedInstance;

- (NSData *)dataFromHierarchyInfo:(LookinHierarchyInfo *)info imageCompression:(CGFloat)compression fileName:(NSString **)fileName;

/// 将 mac 端当前正在查看的 UI 现场导出到 LookinMCP 本地目录，供 MCP 进程只读。
- (BOOL)exportCurrentSnapshotWithError:(NSError **)error;

/// 返回本地 snapshot 根目录，默认位于 `~/Library/Application Support/LookinMCP/`。
- (NSString *)snapshotRootDirectoryPath;

+ (void)exportScreenshotWithDisplayItem:(LookinDisplayItem *)displayItem;

@end
