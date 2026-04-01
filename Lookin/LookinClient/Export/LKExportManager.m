//
//  LKExportManager.m
//  Lookin
//
//  Created by Li Kai on 2019/5/12.
//  https://lookin.work
//

#import "LKExportManager.h"
#import "LookinHierarchyInfo.h"
#import "LookinHierarchyFile.h"
#import "LookinAppInfo.h"
#import "LookinDisplayItem.h"
#import "LookinDisplayItem+LookinClient.h"
#import "LookinDocument.h"
#import "LKHelper.h"
#import "LKNavigationManager.h"
#import "LKAppsManager.h"
#import "LKStaticHierarchyDataSource.h"
#import "LookinAttribute.h"
#import "LookinAttributesGroup.h"
#import "LookinAttributesSection.h"
#import "LookinAutoLayoutConstraint+LookinClient.h"
#import "LookinAutoLayoutConstraint.h"
#import "LookinAttrIdentifiers.h"
#import "LookinIvarTrace.h"
#import "LookinObject+LookinClient.h"
#import "NSColor+LookinClient.h"

static NSString * const LKMCPSnapshotSchemaVersion = @"lookin-mcp-snapshot-v1";
static NSString * const LKMCPSnapshotExporterVersion = @"0.1.0";
static NSString * const LKMCPSnapshotCurrentDirectoryName = @"current";
static NSString * const LKMCPSnapshotHistoryDirectoryName = @"history";
static NSString * const LKMCPSnapshotJSONFileName = @"snapshot.json";
static NSString * const LKMCPSnapshotScreenshotFileName = @"screenshot.png";
static NSUInteger const LKMCPSnapshotHistoryLimit = 20;

@implementation LKExportManager

+ (instancetype)sharedInstance {
    static dispatch_once_t onceToken;
    static LKExportManager *instance = nil;
    dispatch_once(&onceToken,^{
        instance = [[super allocWithZone:NULL] init];
    });
    return instance;
}

+ (id)allocWithZone:(struct _NSZone *)zone{
    return [self sharedInstance];
}

- (NSData *)dataFromHierarchyInfo:(LookinHierarchyInfo *)info imageCompression:(CGFloat)compression fileName:(NSString **)fileName {
    LookinHierarchyFile *file = [LookinHierarchyFile new];
    file.serverVersion = info.serverVersion;
    file.hierarchyInfo = info;
    
    NSMutableDictionary<NSString *, NSData *> *soloScreenshots = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSData *> *groupScreenshots = [NSMutableDictionary dictionary];
    
    NSArray<LookinDisplayItem *> *allItems = [LookinDisplayItem flatItemsFromHierarchicalItems:info.displayItems];
    [allItems enumerateObjectsUsingBlock:^(LookinDisplayItem * _Nonnull displayItem, NSUInteger idx, BOOL * _Nonnull stop) {
        displayItem.screenshotEncodeType = LookinDisplayItemImageEncodeTypeNone;
        soloScreenshots[@(displayItem.layerObject.oid)] = [self _compressedDataFromImage:displayItem.soloScreenshot compression:compression];
        groupScreenshots[@(displayItem.layerObject.oid)] = [self _compressedDataFromImage:displayItem.groupScreenshot compression:compression];
    }];
    file.soloScreenshots = soloScreenshots.copy;
    file.groupScreenshots = groupScreenshots.copy;
    
    LookinDocument *document = [[LookinDocument alloc] init];
    document.hierarchyFile = file;
    NSError *error;
    NSData *exportedData = [document dataOfType:@"com.lookin.lookin" error:&error];
    if (error) {
        NSAssert(NO, @"");
    }
    
    if (fileName) {
        NSString *timeString = ({
            NSDate *date = [NSDate date];
            NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
            [formatter setDateFormat:@"MMddHHmm"];
            [formatter stringFromDate:date];
        });
        NSString *iOSVersion = ({
            NSString *str = info.appInfo.osDescription;
            NSUInteger dotIdx = [str rangeOfString:@"."].location;
            if (dotIdx != NSNotFound) {
                str = [str substringToIndex:dotIdx];
            }
            str;
        });
        *fileName = [NSString stringWithFormat:@"%@_ios%@_%@.lookin", info.appInfo.appName, iOSVersion, timeString];
        
    }
    
    return exportedData;
}

- (BOOL)exportCurrentSnapshotWithError:(NSError **)error {
    LKInspectableApp *app = [LKAppsManager sharedInstance].inspectingApp;
    LookinHierarchyInfo *info = [LKStaticHierarchyDataSource sharedInstance].rawHierarchyInfo;
    if (!app || !info) {
        if (error) {
            *error = [NSError errorWithDomain:LookinErrorDomain
                                         code:LookinErrCode_Inner
                                     userInfo:@{NSLocalizedDescriptionKey:@"当前没有可导出的 Lookin 现场。"}];
        }
        return NO;
    }

    NSDictionary<NSString *, id> *snapshot = [self _snapshotDictionaryWithHierarchyInfo:info app:app error:error];
    if (!snapshot) {
        return NO;
    }

    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:snapshot
                                                       options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                                                         error:error];
    if (!jsonData) {
        return NO;
    }

    LookinImage *screenshotImage = info.appInfo.screenshot ?: app.appInfo.screenshot;
    NSData *screenshotData = [self _pngDataFromImage:screenshotImage];
    NSString *snapshotID = snapshot[@"snapshot_id"];
    NSString *rootDirectoryPath = [self snapshotRootDirectoryPath];
    NSString *currentDirectoryPath = [rootDirectoryPath stringByAppendingPathComponent:LKMCPSnapshotCurrentDirectoryName];
    NSString *historyDirectoryPath = [[rootDirectoryPath stringByAppendingPathComponent:LKMCPSnapshotHistoryDirectoryName] stringByAppendingPathComponent:snapshotID];

    NSFileManager *fileManager = [NSFileManager defaultManager];
    for (NSString *directoryPath in @[currentDirectoryPath, historyDirectoryPath]) {
        if (![fileManager createDirectoryAtPath:directoryPath withIntermediateDirectories:YES attributes:nil error:error]) {
            return NO;
        }
    }

    if (![self _writeData:jsonData toPath:[historyDirectoryPath stringByAppendingPathComponent:LKMCPSnapshotJSONFileName] error:error]) {
        return NO;
    }
    if (![self _writeScreenshotData:screenshotData inDirectory:historyDirectoryPath error:error]) {
        return NO;
    }

    if (![self _writeData:jsonData toPath:[currentDirectoryPath stringByAppendingPathComponent:LKMCPSnapshotJSONFileName] error:error]) {
        return NO;
    }
    if (![self _writeScreenshotData:screenshotData inDirectory:currentDirectoryPath error:error]) {
        return NO;
    }

    [self _trimSnapshotHistoryAtRootPath:rootDirectoryPath];
    return YES;
}

- (NSString *)snapshotRootDirectoryPath {
    NSString *applicationSupportPath = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
    return [applicationSupportPath stringByAppendingPathComponent:@"LookinMCP"];
}

/// compression 范围从 0.01 ~ 1
- (NSData *)_compressedDataFromImage:(LookinImage *)sourceImage compression:(CGFloat)compression {
    if (!sourceImage) {
        return nil;
    }
    
#if TARGET_OS_IPHONE
    return nil;
    
#elif TARGET_OS_MAC
    
    compression = MAX(MIN(compression, 1), 0.01);
    
    NSSize targetSize = NSMakeSize(sourceImage.size.width * compression, sourceImage.size.height * compression);
    NSRect targetFrame = NSMakeRect(0, 0, targetSize.width, targetSize.height);
    NSImageRep *sourceImageRep = [sourceImage bestRepresentationForRect:targetFrame context:nil hints:nil];
    
    NSImage *resizedImage = [[NSImage alloc] initWithSize:targetSize];
    [resizedImage lockFocus];
    [sourceImageRep drawInRect:targetFrame];
    [resizedImage unlockFocus];
    
    NSBitmapImageRep *imageRep = [[NSBitmapImageRep alloc] initWithData:[resizedImage TIFFRepresentation]];
    NSData *compressedData = [imageRep TIFFRepresentationUsingCompression:NSTIFFCompressionLZW factor:1];
    return compressedData;
#endif
}

+ (void)exportScreenshotWithDisplayItem:(LookinDisplayItem *)displayItem {
    NSImage *image = displayItem.groupScreenshot;
    if (!image) {
        AlertError(LookinErr_Inner, CurrentKeyWindow);
        return;
    }
    
    NSData *imageData = [image TIFFRepresentationUsingCompression:NSTIFFCompressionLZW factor:1];
    if (!imageData) {
        AlertError(LookinErr_Inner, CurrentKeyWindow);
        return;
    }
    
    NSString *fileName = [displayItem title] ? : @"LookinImage";

    NSSavePanel *panel = [NSSavePanel savePanel];
    [panel setNameFieldStringValue:fileName];
    [panel setAllowsOtherFileTypes:NO];
    [panel setAllowedFileTypes:@[@"tiff"]];
    [panel setExtensionHidden:YES];
    [panel setCanCreateDirectories:YES];
    [panel beginSheetModalForWindow:CurrentKeyWindow completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK) {
            NSString *path = [[panel URL] path];
            NSError *writeError;
            BOOL writeSucc = [imageData writeToFile:path options:0 error:&writeError];
            if (!writeSucc) {
                AlertError(writeError, CurrentKeyWindow);
                NSAssert(NO, @"");
            }
        }
    }];
}

#pragma mark - Snapshot Helpers

/// 生成供 MCP 读取的标准 snapshot 字典。
- (NSDictionary<NSString *, id> *)_snapshotDictionaryWithHierarchyInfo:(LookinHierarchyInfo *)info
                                                                   app:(LKInspectableApp *)app
                                                                 error:(NSError **)error {
    NSArray<LookinDisplayItem *> *flatItems = [LKStaticHierarchyDataSource sharedInstance].flatItems ?: @[];
    if (flatItems.count == 0) {
        if (error) {
            *error = [NSError errorWithDomain:LookinErrorDomain
                                         code:LookinErrCode_Inner
                                     userInfo:@{NSLocalizedDescriptionKey:@"当前 hierarchy 为空，无法导出 snapshot。"}];
        }
        return nil;
    }

    NSString *snapshotID = [self _snapshotTimestampString];
    NSMutableArray<NSDictionary<NSString *, id> *> *nodes = [NSMutableArray arrayWithCapacity:flatItems.count];
    NSMutableOrderedSet<NSString *> *visibleVCNames = [NSMutableOrderedSet orderedSet];
    NSMutableArray<NSString *> *rootNodeIDs = [NSMutableArray array];

    [flatItems enumerateObjectsUsingBlock:^(LookinDisplayItem * _Nonnull item, NSUInteger idx, BOOL * _Nonnull stop) {
        NSDictionary<NSString *, id> *node = [self _snapshotNodeDictionaryForItem:item];
        [nodes addObject:node];

        if (item.superItem == nil) {
            [rootNodeIDs addObject:node[@"node_id"]];
        }

        NSString *viewControllerName = [self _resolvedHostViewControllerNameForItem:item];
        if (viewControllerName.length > 0) {
            [visibleVCNames addObject:viewControllerName];
        }
    }];

    NSMutableDictionary<NSString *, id> *snapshot = [NSMutableDictionary dictionary];
    snapshot[@"schema_version"] = LKMCPSnapshotSchemaVersion;
    snapshot[@"snapshot_id"] = snapshotID;
    snapshot[@"captured_at"] = [self _iso8601NowString];
    snapshot[@"source"] = @{
        @"exporter": @"lookin-mac",
        @"exporter_version": LKMCPSnapshotExporterVersion
    };
    snapshot[@"app"] = [self _appDictionaryForInfo:(info.appInfo ?: app.appInfo)];
    snapshot[@"visible_view_controller_names"] = visibleVCNames.array ?: @[];
    snapshot[@"tree"] = @{
        @"root_node_ids": rootNodeIDs,
        @"node_count": @(nodes.count),
        @"nodes": nodes
    };

    LookinImage *screenshotImage = info.appInfo.screenshot ?: app.appInfo.screenshot;
    if (screenshotImage) {
        snapshot[@"screenshot"] = @{
            @"relative_path": LKMCPSnapshotScreenshotFileName,
            @"width": @(screenshotImage.size.width),
            @"height": @(screenshotImage.size.height)
        };
    }

    return snapshot.copy;
}

/// 为单个 display item 生成稳定的 snapshot 节点。
- (NSDictionary<NSString *, id> *)_snapshotNodeDictionaryForItem:(LookinDisplayItem *)item {
    LookinObject *displayObject = item.displayingObject;
    NSString *nodeID = [self _nodeIDForItem:item];
    NSMutableDictionary<NSString *, id> *node = [NSMutableDictionary dictionary];
    node[@"node_id"] = nodeID;
    node[@"parent_id"] = item.superItem ? [self _nodeIDForItem:item.superItem] : [NSNull null];
    node[@"child_ids"] = [item.subitems lookin_map:^id(NSUInteger idx, LookinDisplayItem *value) {
        return [self _nodeIDForItem:value];
    }] ?: @[];
    node[@"title"] = item.title ?: @"";
    node[@"subtitle"] = item.subtitle ?: @"";
    node[@"class_name"] = [self _simpleClassNameForObject:displayObject] ?: @"";
    node[@"raw_class_name"] = displayObject.rawClassName ?: @"";
    node[@"class_chain"] = [self _simpleClassChainForObject:displayObject];
    node[@"memory_address"] = displayObject.memoryAddress ?: @"";
    node[@"host_view_controller_name"] = [self _resolvedHostViewControllerNameForItem:item] ?: @"";
    node[@"ivar_names"] = [self _ivarNamesForItem:item];
    node[@"is_hidden"] = @(item.isHidden);
    node[@"alpha"] = @(item.alpha);
    node[@"displaying_in_hierarchy"] = @(item.displayingInHierarchy);
    node[@"in_hidden_hierarchy"] = @(item.inHiddenHierarchy);
    node[@"indent_level"] = @(item.indentLevel);
    node[@"represented_as_key_window"] = @(item.representedAsKeyWindow);
    node[@"is_user_custom"] = @(item.isUserCustom);

    NSNumber *oid = [self _oidNumberForItem:item];
    if (oid) {
        node[@"oid"] = oid;
    }

    if ([item hasValidFrameToRoot]) {
        node[@"frame_to_root"] = [self _dictionaryFromRect:[item calculateFrameToRoot]];
    }
    node[@"frame"] = [self _dictionaryFromRect:item.frame];
    node[@"bounds"] = [self _dictionaryFromRect:item.bounds];

    NSArray<LookinAttributesGroup *> *attrGroups = [item queryAllAttrGroupList] ?: @[];
    NSArray<NSString *> *textValues = [self _textValuesFromAttrGroups:attrGroups];
    if (textValues.count > 0) {
        node[@"text_values"] = textValues;
    }

    NSDictionary<NSString *, id> *layoutEvidence = [self _layoutEvidenceFromAttrGroups:attrGroups];
    if (layoutEvidence.count > 0) {
        node[@"layout_evidence"] = layoutEvidence;
    }

    NSDictionary<NSString *, id> *visualEvidence = [self _visualEvidenceFromItem:item attrGroups:attrGroups];
    if (visualEvidence.count > 0) {
        node[@"visual_evidence"] = visualEvidence;
    }

    NSString *searchText = [self _searchTextForItem:item textValues:textValues];
    if (searchText.length > 0) {
        node[@"search_text"] = searchText;
    }

    return node.copy;
}

/// 统一导出 app 级别的元数据，供 MCP 列表和快照头信息复用。
- (NSDictionary<NSString *, id> *)_appDictionaryForInfo:(LookinAppInfo *)appInfo {
    NSMutableDictionary<NSString *, id> *app = [NSMutableDictionary dictionary];
    app[@"app_name"] = appInfo.appName ?: @"";
    app[@"bundle_id"] = appInfo.appBundleIdentifier ?: @"";
    app[@"device_description"] = appInfo.deviceDescription ?: @"";
    app[@"os_description"] = appInfo.osDescription ?: @"";
    app[@"lookin_server_version"] = appInfo.serverReadableVersion.length > 0 ? appInfo.serverReadableVersion : @(appInfo.serverVersion);
    app[@"app_info_identifier"] = @(appInfo.appInfoIdentifier);
    app[@"screen"] = @{
        @"width": @(appInfo.screenWidth),
        @"height": @(appInfo.screenHeight),
        @"scale": @(appInfo.screenScale)
    };
    return app.copy;
}

/// 基于 Lookin 的 attr groups 提取布局证据。
- (NSDictionary<NSString *, id> *)_layoutEvidenceFromAttrGroups:(NSArray<LookinAttributesGroup *> *)attrGroups {
    NSMutableDictionary<NSString *, id> *evidence = [NSMutableDictionary dictionary];
    NSMutableArray<NSString *> *constraintSummaries = [NSMutableArray array];

    for (LookinAttributesGroup *group in attrGroups) {
        for (LookinAttributesSection *section in group.attrSections ?: @[]) {
            for (LookinAttribute *attribute in section.attributes ?: @[]) {
                NSString *valueString = [self _stringValueFromAttribute:attribute];
                if (valueString.length == 0) {
                    continue;
                }

                if ([attribute.identifier isEqualToString:LookinAttr_AutoLayout_IntrinsicSize_Size]) {
                    evidence[@"intrinsic_size"] = valueString;
                } else if ([attribute.identifier isEqualToString:LookinAttr_AutoLayout_Hugging_Hor]) {
                    evidence[@"hugging_horizontal"] = valueString;
                } else if ([attribute.identifier isEqualToString:LookinAttr_AutoLayout_Hugging_Ver]) {
                    evidence[@"hugging_vertical"] = valueString;
                } else if ([attribute.identifier isEqualToString:LookinAttr_AutoLayout_Resistance_Hor]) {
                    evidence[@"compression_resistance_horizontal"] = valueString;
                } else if ([attribute.identifier isEqualToString:LookinAttr_AutoLayout_Resistance_Ver]) {
                    evidence[@"compression_resistance_vertical"] = valueString;
                } else if ([attribute.identifier isEqualToString:LookinAttr_AutoLayout_Constraints_Constraints]) {
                    if ([attribute.value isKindOfClass:[NSArray class]]) {
                        [(NSArray *)attribute.value enumerateObjectsUsingBlock:^(LookinAutoLayoutConstraint * _Nonnull constraint, NSUInteger idx, BOOL * _Nonnull stop) {
                            NSString *summary = [self _constraintSummaryFromConstraint:constraint];
                            if (summary.length > 0) {
                                [constraintSummaries addObject:summary];
                            }
                        }];
                    }
                }
            }
        }
    }

    if (constraintSummaries.count > 0) {
        evidence[@"constraints"] = constraintSummaries.copy;
    }
    return evidence.copy;
}

/// 提取与面板一致的视觉证据，便于分析颜色、边框、阴影和交互状态。
- (NSDictionary<NSString *, id> *)_visualEvidenceFromItem:(LookinDisplayItem *)item
                                               attrGroups:(NSArray<LookinAttributesGroup *> *)attrGroups {
    NSMutableDictionary<NSString *, id> *evidence = [NSMutableDictionary dictionary];
    evidence[@"hidden"] = @(item.isHidden);
    evidence[@"opacity"] = @(item.alpha);

    for (LookinAttributesGroup *group in attrGroups) {
        for (LookinAttributesSection *section in group.attrSections ?: @[]) {
            for (LookinAttribute *attribute in section.attributes ?: @[]) {
                if ([attribute.identifier isEqualToString:LookinAttr_ViewLayer_InterationAndMasks_Interaction]) {
                    evidence[@"user_interaction_enabled"] = @([self _boolValueFromAttribute:attribute defaultValue:NO]);
                } else if ([attribute.identifier isEqualToString:LookinAttr_ViewLayer_InterationAndMasks_MasksToBounds]) {
                    evidence[@"masks_to_bounds"] = @([self _boolValueFromAttribute:attribute defaultValue:NO]);
                } else if ([attribute.identifier isEqualToString:LookinAttr_ViewLayer_BgColor_BgColor]) {
                    NSDictionary<NSString *, id> *color = [self _colorEvidenceFromAttribute:attribute];
                    if (color) {
                        evidence[@"background_color"] = color;
                    }
                } else if ([attribute.identifier isEqualToString:LookinAttr_ViewLayer_Border_Color]) {
                    NSDictionary<NSString *, id> *color = [self _colorEvidenceFromAttribute:attribute];
                    if (color) {
                        evidence[@"border_color"] = color;
                    }
                } else if ([attribute.identifier isEqualToString:LookinAttr_ViewLayer_Border_Width]) {
                    NSNumber *value = [self _numberValueFromAttribute:attribute];
                    if (value) {
                        evidence[@"border_width"] = value;
                    }
                } else if ([attribute.identifier isEqualToString:LookinAttr_ViewLayer_Corner_Radius]) {
                    NSNumber *value = [self _numberValueFromAttribute:attribute];
                    if (value) {
                        evidence[@"corner_radius"] = value;
                    }
                } else if ([attribute.identifier isEqualToString:LookinAttr_ViewLayer_Shadow_Color]) {
                    NSDictionary<NSString *, id> *color = [self _colorEvidenceFromAttribute:attribute];
                    if (color) {
                        NSDictionary<NSString *, id> *existingShadow = [evidence[@"shadow"] isKindOfClass:[NSDictionary class]] ? evidence[@"shadow"] : nil;
                        NSMutableDictionary<NSString *, id> *shadow = existingShadow ? existingShadow.mutableCopy : [NSMutableDictionary dictionary];
                        shadow[@"color"] = color;
                        evidence[@"shadow"] = shadow.copy;
                    }
                } else if ([attribute.identifier isEqualToString:LookinAttr_ViewLayer_Shadow_Opacity]) {
                    NSNumber *value = [self _numberValueFromAttribute:attribute];
                    if (value) {
                        NSDictionary<NSString *, id> *existingShadow = [evidence[@"shadow"] isKindOfClass:[NSDictionary class]] ? evidence[@"shadow"] : nil;
                        NSMutableDictionary<NSString *, id> *shadow = existingShadow ? existingShadow.mutableCopy : [NSMutableDictionary dictionary];
                        shadow[@"opacity"] = value;
                        evidence[@"shadow"] = shadow.copy;
                    }
                } else if ([attribute.identifier isEqualToString:LookinAttr_ViewLayer_Shadow_Radius]) {
                    NSNumber *value = [self _numberValueFromAttribute:attribute];
                    if (value) {
                        NSDictionary<NSString *, id> *existingShadow = [evidence[@"shadow"] isKindOfClass:[NSDictionary class]] ? evidence[@"shadow"] : nil;
                        NSMutableDictionary<NSString *, id> *shadow = existingShadow ? existingShadow.mutableCopy : [NSMutableDictionary dictionary];
                        shadow[@"radius"] = value;
                        evidence[@"shadow"] = shadow.copy;
                    }
                } else if ([attribute.identifier isEqualToString:LookinAttr_ViewLayer_Shadow_OffsetW]) {
                    NSNumber *value = [self _numberValueFromAttribute:attribute];
                    if (value) {
                        NSDictionary<NSString *, id> *existingShadow = [evidence[@"shadow"] isKindOfClass:[NSDictionary class]] ? evidence[@"shadow"] : nil;
                        NSMutableDictionary<NSString *, id> *shadow = existingShadow ? existingShadow.mutableCopy : [NSMutableDictionary dictionary];
                        NSDictionary<NSString *, id> *existingOffset = [shadow[@"offset"] isKindOfClass:[NSDictionary class]] ? shadow[@"offset"] : nil;
                        NSMutableDictionary<NSString *, id> *offset = existingOffset ? existingOffset.mutableCopy : [NSMutableDictionary dictionary];
                        offset[@"width"] = value;
                        shadow[@"offset"] = offset.copy;
                        evidence[@"shadow"] = shadow.copy;
                    }
                } else if ([attribute.identifier isEqualToString:LookinAttr_ViewLayer_Shadow_OffsetH]) {
                    NSNumber *value = [self _numberValueFromAttribute:attribute];
                    if (value) {
                        NSDictionary<NSString *, id> *existingShadow = [evidence[@"shadow"] isKindOfClass:[NSDictionary class]] ? evidence[@"shadow"] : nil;
                        NSMutableDictionary<NSString *, id> *shadow = existingShadow ? existingShadow.mutableCopy : [NSMutableDictionary dictionary];
                        NSDictionary<NSString *, id> *existingOffset = [shadow[@"offset"] isKindOfClass:[NSDictionary class]] ? shadow[@"offset"] : nil;
                        NSMutableDictionary<NSString *, id> *offset = existingOffset ? existingOffset.mutableCopy : [NSMutableDictionary dictionary];
                        offset[@"height"] = value;
                        shadow[@"offset"] = offset.copy;
                        evidence[@"shadow"] = shadow.copy;
                    }
                } else if ([attribute.identifier isEqualToString:LookinAttr_ViewLayer_TintColor_Color]) {
                    NSDictionary<NSString *, id> *color = [self _colorEvidenceFromAttribute:attribute];
                    if (color) {
                        evidence[@"tint_color"] = color;
                    }
                } else if ([attribute.identifier isEqualToString:LookinAttr_ViewLayer_TintColor_Mode]) {
                    NSString *value = [self _stringValueFromAttribute:attribute];
                    if (value.length > 0) {
                        evidence[@"tint_adjustment_mode"] = value;
                    }
                } else if ([attribute.identifier isEqualToString:LookinAttr_ViewLayer_Tag_Tag]) {
                    NSNumber *value = [self _numberValueFromAttribute:attribute];
                    if (value) {
                        evidence[@"tag"] = value;
                    }
                }
            }
        }
    }

    return evidence.copy;
}

/// 从 attr groups 中提取适合 text 查询的文本值。
- (NSArray<NSString *> *)_textValuesFromAttrGroups:(NSArray<LookinAttributesGroup *> *)attrGroups {
    NSMutableOrderedSet<NSString *> *texts = [NSMutableOrderedSet orderedSet];
    NSSet<NSString *> *targetIdentifiers = [NSSet setWithArray:@[
        LookinAttr_UILabel_Text_Text,
        LookinAttr_UITextView_Text_Text,
        LookinAttr_UITextField_Text_Text,
        LookinAttr_UITextField_Placeholder_Placeholder,
        LookinAttr_UIImageView_Name_Name
    ]];

    for (LookinAttributesGroup *group in attrGroups) {
        for (LookinAttributesSection *section in group.attrSections ?: @[]) {
            for (LookinAttribute *attribute in section.attributes ?: @[]) {
                if (![targetIdentifiers containsObject:attribute.identifier]) {
                    continue;
                }
                NSString *valueString = [self _stringValueFromAttribute:attribute];
                if (valueString.length > 0) {
                    [texts addObject:valueString];
                }
            }
        }
    }

    return texts.array ?: @[];
}

/// 拼出节点的统一搜索文本，便于 MCP 做确定性筛选。
- (NSString *)_searchTextForItem:(LookinDisplayItem *)item textValues:(NSArray<NSString *> *)textValues {
    NSMutableOrderedSet<NSString *> *parts = [NSMutableOrderedSet orderedSet];
    for (NSString *candidate in @[
        item.title ?: @"",
        item.subtitle ?: @"",
        [self _simpleClassNameForObject:item.displayingObject] ?: @"",
        item.displayingObject.rawClassName ?: @"",
        [self _resolvedHostViewControllerNameForItem:item] ?: @""
    ]) {
        if (candidate.length > 0) {
            [parts addObject:candidate];
        }
    }

    [[self _ivarNamesForItem:item] enumerateObjectsUsingBlock:^(NSString * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        if (obj.length > 0) {
            [parts addObject:obj];
        }
    }];
    [textValues enumerateObjectsUsingBlock:^(NSString * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        if (obj.length > 0) {
            [parts addObject:obj];
        }
    }];
    return [parts.array componentsJoinedByString:@" | "];
}

/// 序列化 LookinAttribute 的值，避免把 Objective-C 对象直接塞进 JSON。
- (NSString *)_stringValueFromAttribute:(LookinAttribute *)attribute {
    if (!attribute) {
        return nil;
    }

    if ([attribute.value isKindOfClass:[NSString class]]) {
        return attribute.value;
    }
    if ([attribute.value isKindOfClass:[NSNumber class]]) {
        return [(NSNumber *)attribute.value stringValue];
    }
    if ([attribute.value isKindOfClass:[NSValue class]]) {
        return [(NSValue *)attribute.value description];
    }
    if ([attribute.value isKindOfClass:[NSArray class]]) {
        NSMutableArray<NSString *> *parts = [NSMutableArray array];
        [(NSArray *)attribute.value enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            if ([obj isKindOfClass:[NSString class]]) {
                [parts addObject:obj];
            } else if ([obj respondsToSelector:@selector(description)]) {
                [parts addObject:[obj description]];
            }
        }];
        return [parts componentsJoinedByString:@" | "];
    }
    if ([attribute.value respondsToSelector:@selector(description)]) {
        return [attribute.value description];
    }
    return nil;
}

/// 从数值型 attribute 中提取 NSNumber。
- (NSNumber *)_numberValueFromAttribute:(LookinAttribute *)attribute {
    if ([attribute.value isKindOfClass:[NSNumber class]]) {
        return attribute.value;
    }
    return nil;
}

/// 从布尔型 attribute 中提取布尔值。
- (BOOL)_boolValueFromAttribute:(LookinAttribute *)attribute defaultValue:(BOOL)defaultValue {
    NSNumber *number = [self _numberValueFromAttribute:attribute];
    return number ? number.boolValue : defaultValue;
}

/// 把 Lookin 的 RGBA 数组转成结构化颜色证据。
- (NSDictionary<NSString *, id> *)_colorEvidenceFromAttribute:(LookinAttribute *)attribute {
    if (![attribute.value isKindOfClass:[NSArray class]]) {
        return nil;
    }
    NSColor *color = [NSColor lk_colorFromRGBAComponents:attribute.value];
    if (!color) {
        return nil;
    }
    return @{
        @"rgba_string": color.rgbaString ?: @"",
        @"hex_string": color.hexString ?: @"",
        @"components": color.lk_rgbaComponents ?: @[]
    };
}

/// 生成约束摘要，便于 LLM 直接阅读。
- (NSString *)_constraintSummaryFromConstraint:(LookinAutoLayoutConstraint *)constraint {
    if (!constraint) {
        return nil;
    }

    NSString *firstItem = [LookinAutoLayoutConstraint descriptionWithItemObject:constraint.firstItem type:constraint.firstItemType detailed:NO];
    NSString *firstAttribute = [LookinAutoLayoutConstraint descriptionWithAttributeInt:constraint.firstAttribute];
    NSString *relation = [LookinAutoLayoutConstraint symbolWithRelation:constraint.relation];
    NSString *secondItem = [LookinAutoLayoutConstraint descriptionWithItemObject:constraint.secondItem type:constraint.secondItemType detailed:NO];
    NSString *secondAttribute = [LookinAutoLayoutConstraint descriptionWithAttributeInt:constraint.secondAttribute];

    NSMutableString *summary = [NSMutableString stringWithFormat:@"%@.%@ %@ ", firstItem ?: @"self", firstAttribute ?: @"notAnAttribute", relation ?: @"="];
    if (secondItem.length > 0) {
        [summary appendFormat:@"%@.%@", secondItem, secondAttribute ?: @"notAnAttribute"];
    } else {
        [summary appendString:@"nil"];
    }
    if (constraint.multiplier != 0 && constraint.multiplier != 1) {
        [summary appendFormat:@" * %@", @(constraint.multiplier)];
    }
    if (constraint.constant != 0) {
        [summary appendFormat:@" + %@", @(constraint.constant)];
    }
    [summary appendFormat:@" @%@", @(constraint.priority)];
    return summary.copy;
}

/// 输出稳定的节点 ID，优先使用 Lookin 原生 oid。
- (NSString *)_nodeIDForItem:(LookinDisplayItem *)item {
    NSNumber *oid = [self _oidNumberForItem:item];
    if (oid != nil) {
        return [NSString stringWithFormat:@"oid:%@", oid];
    }
    return [NSString stringWithFormat:@"custom:%p", item];
}

/// 获取节点 oid，没有 oid 的自定义节点返回 nil。
- (NSNumber *)_oidNumberForItem:(LookinDisplayItem *)item {
    unsigned long oid = item.layerObject.oid ?: item.viewObject.oid;
    if (oid == 0) {
        return nil;
    }
    return @(oid);
}

/// 提取 item 的 ivar 名称列表。
- (NSArray<NSString *> *)_ivarNamesForItem:(LookinDisplayItem *)item {
    NSMutableOrderedSet<NSString *> *names = [NSMutableOrderedSet orderedSet];
    NSArray<LookinIvarTrace *> *traces = item.displayingObject.ivarTraces ?: @[];
    [traces enumerateObjectsUsingBlock:^(LookinIvarTrace * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        if (obj.ivarName.length > 0) {
            [names addObject:obj.ivarName];
        }
    }];
    return names.array ?: @[];
}

/// 将 rect 转成 JSON 友好的字典。
- (NSDictionary<NSString *, id> *)_dictionaryFromRect:(CGRect)rect {
    return @{
        @"x": @(rect.origin.x),
        @"y": @(rect.origin.y),
        @"width": @(rect.size.width),
        @"height": @(rect.size.height)
    };
}

/// 统一获取对象的简化类名。
- (NSString *)_simpleClassNameForObject:(LookinObject *)object {
    if (!object) {
        return nil;
    }
    return object.lk_simpleDemangledClassName ?: object.rawClassName;
}

/// 某些子节点不会直接携带 hostViewController，这里向上回溯到最近的 VC 名。
- (NSString *)_resolvedHostViewControllerNameForItem:(LookinDisplayItem *)item {
    LookinDisplayItem *cursor = item;
    while (cursor) {
        NSString *className = [self _simpleClassNameForObject:cursor.hostViewControllerObject];
        if (className.length > 0) {
            return className;
        }
        cursor = cursor.superItem;
    }
    return nil;
}

/// 把 classChain 里的模块前缀剥掉，避免 MCP 侧再做一遍清洗。
- (NSArray<NSString *> *)_simpleClassChainForObject:(LookinObject *)object {
    NSMutableArray<NSString *> *result = [NSMutableArray array];
    [object.classChainList enumerateObjectsUsingBlock:^(NSString * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        NSString *simpleName = [obj componentsSeparatedByString:@"."].lastObject ?: obj;
        if (simpleName.length > 0) {
            [result addObject:simpleName];
        }
    }];
    return result.copy;
}

/// 生成历史目录与 snapshot_id 共用的 UTC 时间串。
- (NSString *)_snapshotTimestampString {
    static NSDateFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
        formatter.dateFormat = @"yyyyMMdd'T'HHmmss'Z'";
    });
    return [formatter stringFromDate:[NSDate date]];
}

/// 写入 snapshot 的标准时间戳。
- (NSString *)_iso8601NowString {
    static NSISO8601DateFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSISO8601DateFormatter alloc] init];
        formatter.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
        formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime;
    });
    return [formatter stringFromDate:[NSDate date]];
}

/// 将图片转为 PNG，作为 current/history 目录中的截图文件。
- (NSData *)_pngDataFromImage:(LookinImage *)image {
    if (!image) {
        return nil;
    }

    NSBitmapImageRep *imageRep = [[NSBitmapImageRep alloc] initWithData:[image TIFFRepresentation]];
    return [imageRep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
}

/// 统一做原子写盘。
- (BOOL)_writeData:(NSData *)data toPath:(NSString *)path error:(NSError **)error {
    if (!data || path.length == 0) {
        return YES;
    }
    return [data writeToFile:path options:NSDataWritingAtomic error:error];
}

/// 写入或清理截图文件，避免 current 目录残留旧截图。
- (BOOL)_writeScreenshotData:(NSData *)screenshotData inDirectory:(NSString *)directoryPath error:(NSError **)error {
    NSString *screenshotPath = [directoryPath stringByAppendingPathComponent:LKMCPSnapshotScreenshotFileName];
    if (screenshotData.length > 0) {
        return [self _writeData:screenshotData toPath:screenshotPath error:error];
    }

    [[NSFileManager defaultManager] removeItemAtPath:screenshotPath error:nil];
    return YES;
}

/// 控制历史目录数量，避免长期运行后无限膨胀。
- (void)_trimSnapshotHistoryAtRootPath:(NSString *)rootPath {
    NSString *historyRoot = [rootPath stringByAppendingPathComponent:LKMCPSnapshotHistoryDirectoryName];
    NSArray<NSString *> *directoryNames = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:historyRoot error:nil] sortedArrayUsingSelector:@selector(compare:)];
    if (directoryNames.count <= LKMCPSnapshotHistoryLimit) {
        return;
    }

    NSRange deleteRange = NSMakeRange(0, directoryNames.count - LKMCPSnapshotHistoryLimit);
    [[directoryNames subarrayWithRange:deleteRange] enumerateObjectsUsingBlock:^(NSString * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        NSString *path = [historyRoot stringByAppendingPathComponent:obj];
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    }];
}

@end
