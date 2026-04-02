import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct SnapshotDocument: Codable {
    let schemaVersion: String
    let snapshotId: String
    let capturedAt: String
    let source: SnapshotSource?
    let app: SnapshotApp
    let visibleViewControllerNames: [String]
    let tree: SnapshotTree
    let screenshot: SnapshotScreenshot?
}

struct SnapshotSource: Codable {
    let exporter: String
    let exporterVersion: String?
}

struct SnapshotApp: Codable {
    let appName: String
    let bundleId: String
    let deviceDescription: String
    let osDescription: String
    let lookinServerVersion: StringOrNumber?
    let appInfoIdentifier: Int?
    let screen: SnapshotScreen
}

struct SnapshotScreen: Codable {
    let width: Double
    let height: Double
    let scale: Double
}

struct SnapshotScreenshot: Codable {
    let relativePath: String
    let width: Double
    let height: Double
}

struct SnapshotTree: Codable {
    let rootNodeIds: [String]
    let nodeCount: Int?
    let nodes: [SnapshotNode]
}

struct SnapshotNode: Codable {
    let nodeId: String
    let parentId: String?
    let childIds: [String]
    let title: String
    let subtitle: String
    let className: String
    let rawClassName: String
    let classChain: [String]
    let memoryAddress: String
    let hostViewControllerName: String
    let ivarNames: [String]
    let isHidden: Bool
    let alpha: Double
    let displayingInHierarchy: Bool
    let inHiddenHierarchy: Bool
    let indentLevel: Int
    let representedAsKeyWindow: Bool
    let isUserCustom: Bool
    let oid: Int?
    let frameToRoot: SnapshotRect?
    let frame: SnapshotRect?
    let bounds: SnapshotRect?
    let textValues: [String]?
    let layoutEvidence: SnapshotLayoutEvidence?
    let visualEvidence: SnapshotVisualEvidence?
    let searchText: String?
}

struct SnapshotRect: Codable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

struct SnapshotLayoutEvidence: Codable {
    let intrinsicSize: String?
    let huggingHorizontal: String?
    let huggingVertical: String?
    let compressionResistanceHorizontal: String?
    let compressionResistanceVertical: String?
    let constraints: [String]?
}

struct SnapshotVisualEvidence: Codable {
    let hidden: Bool?
    let opacity: Double?
    let userInteractionEnabled: Bool?
    let masksToBounds: Bool?
    let backgroundColor: SnapshotColorEvidence?
    let borderColor: SnapshotColorEvidence?
    let borderWidth: Double?
    let cornerRadius: Double?
    let shadow: SnapshotShadowEvidence?
    let tintColor: SnapshotColorEvidence?
    let tintAdjustmentMode: String?
    let tag: Double?
}

struct SnapshotColorEvidence: Codable {
    let rgbaString: String?
    let hexString: String?
    let components: [Double]?
}

struct SnapshotShadowEvidence: Codable {
    let color: SnapshotColorEvidence?
    let opacity: Double?
    let radius: Double?
    let offset: SnapshotShadowOffset?
}

struct SnapshotShadowOffset: Codable {
    let width: Double?
    let height: Double?
}

enum StringOrNumber: Codable {
    case string(String)
    case number(Int)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
            return
        }
        self = .number(try container.decode(Int.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        }
    }

    var stringValue: String {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            return String(value)
        }
    }
}

struct SnapshotRecord {
    let document: SnapshotDocument
    let snapshotURL: URL
    let directoryURL: URL
    let isCurrent: Bool
}

struct SnapshotSummary: Encodable {
    let snapshotId: String
    let capturedAt: String
    let isCurrent: Bool
    let snapshotDirectory: String
    let snapshotFile: String
    let appName: String
    let bundleId: String
    let deviceDescription: String
    let osDescription: String
}

struct SnapshotQuery {
    let snapshotId: String?
    let vcName: String?
    let ivarName: String?
    let className: String?
    let text: String?
    let maxMatches: Int
    let includeTree: Bool
}

struct QueryResponse: Encodable {
    let snapshotId: String
    let capturedAt: String
    let snapshotDirectory: String
    let snapshotFile: String
    let app: SnapshotApp
    let visibleViewControllerNames: [String]
    let screenshot: SnapshotScreenshot?
    let filtersApplied: QueryFilters
    let matchCount: Int
    let matches: [QueryMatch]
    let treeExcerpt: [String]?
    let diagnosticNotes: [String]
}

struct QueryFilters: Encodable {
    let vcName: String?
    let ivarName: String?
    let className: String?
    let text: String?
}

struct QueryMatch: Encodable {
    let nodeId: String
    let oid: Int?
    let title: String
    let subtitle: String
    let className: String
    let hostViewControllerName: String
    let ivarNames: [String]
    let frame: SnapshotRect?
    let bounds: SnapshotRect?
    let frameToRoot: SnapshotRect?
    let isHidden: Bool
    let alpha: Double
    let textValues: [String]
    let layoutEvidence: SnapshotLayoutEvidence?
    let visualEvidence: SnapshotVisualEvidence?
}

struct FoundNode: Encodable {
    let nodeId: String
    let oid: Int?
    let title: String
    let subtitle: String
    let className: String
    let hostViewControllerName: String
    let ivarNames: [String]
    let textValues: [String]
    let frameToRoot: SnapshotRect?
    let isHidden: Bool
    let alpha: Double
    let matchedBy: [String]
}

struct FindNodesResponse: Encodable {
    let snapshotId: String
    let capturedAt: String
    let snapshotDirectory: String
    let snapshotFile: String
    let app: SnapshotApp
    let screenshot: SnapshotScreenshot?
    let filtersApplied: QueryFilters
    let matchCount: Int
    let nodes: [FoundNode]
    let diagnosticNotes: [String]
}

struct NodeReference: Encodable {
    let nodeId: String
    let oid: Int?
    let title: String
    let subtitle: String
    let className: String
    let hostViewControllerName: String
    let ivarNames: [String]
    let textValues: [String]
    let frameToRoot: SnapshotRect?
    let isHidden: Bool
    let alpha: Double
}

struct NodeDetailsResponse: Encodable {
    let snapshotId: String
    let capturedAt: String
    let snapshotDirectory: String
    let snapshotFile: String
    let app: SnapshotApp
    let screenshot: SnapshotScreenshot?
    let node: SnapshotNode
    let parent: NodeReference?
    let children: [NodeReference]
    let diagnosticNotes: [String]
}

struct RelativeLayoutMetrics: Encodable {
    let horizontalGap: Double?
    let verticalGap: Double?
    let centerDeltaX: Double?
    let centerDeltaY: Double?
    let overlapOnX: Bool?
    let overlapOnY: Bool?
    let relativePosition: String?
}

struct RelatedNode: Encodable {
    let node: NodeReference
    let relation: RelativeLayoutMetrics
}

struct ParentInsets: Encodable {
    let left: Double?
    let right: Double?
    let top: Double?
    let bottom: Double?
}

struct NodeRelationsResponse: Encodable {
    let snapshotId: String
    let capturedAt: String
    let snapshotDirectory: String
    let snapshotFile: String
    let app: SnapshotApp
    let screenshot: SnapshotScreenshot?
    let node: NodeReference
    let parent: RelatedNode?
    let ancestors: [NodeReference]
    let siblings: [RelatedNode]
    let children: [RelatedNode]
    let withinParentInsets: ParentInsets?
    let diagnosticNotes: [String]
}

struct SubtreeNodeEntry: Encodable {
    let nodeId: String
    let parentId: String?
    let depth: Int
    let title: String
    let subtitle: String
    let className: String
    let hostViewControllerName: String
    let ivarNames: [String]
    let textValues: [String]
    let frameToRoot: SnapshotRect?
    let isHidden: Bool
    let alpha: Double
    let childCount: Int
}

struct SubtreeResponse: Encodable {
    let snapshotId: String
    let capturedAt: String
    let snapshotDirectory: String
    let snapshotFile: String
    let app: SnapshotApp
    let screenshot: SnapshotScreenshot?
    let rootNodeId: String
    let maxDepth: Int
    let maxNodes: Int
    let returnedNodeCount: Int
    let truncated: Bool
    let nodes: [SubtreeNodeEntry]
    let diagnosticNotes: [String]
}

struct ScreenshotCropResponse: Encodable {
    let snapshotId: String
    let capturedAt: String
    let snapshotDirectory: String
    let snapshotFile: String
    let screenshotFile: String
    let cropFile: String
    let nodeId: String
    let nodeFrameToRoot: SnapshotRect
    let screenshotLogicalSize: SnapshotRect
    let cropRectPixels: SnapshotRect
    let cropRectInScreenshot: SnapshotRect
    let screenshotPixelSize: SnapshotRect
    let outputPixelSize: SnapshotRect
    let padding: Double
    let diagnosticNotes: [String]
}

final class LocalSnapshotStore {
    private let rootURL: URL
    private let decoder: JSONDecoder

    init(rootURL: URL = LocalSnapshotStore.defaultRootURL()) {
        self.rootURL = rootURL
        self.decoder = JSONDecoder()
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    /// 默认读取 `LOOKIN_SNAPSHOT_ROOT`，否则回落到用户目录下的 LookinMCP。
    static func defaultRootURL() -> URL {
        if let overridden = ProcessInfo.processInfo.environment["LOOKIN_SNAPSHOT_ROOT"], !overridden.isEmpty {
            return URL(fileURLWithPath: overridden, isDirectory: true)
        }

        let appSupport = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
        return appSupport.appendingPathComponent("LookinMCP", isDirectory: true)
    }

    func snapshotRootPath() -> String {
        rootURL.path
    }

    func latestSnapshotStatus(now: Date = Date()) -> MCPSnapshotStatus? {
        guard let record = try? latestSnapshot(),
              let capturedDate = parseLookinDate(record.document.capturedAt) else {
            return nil
        }
        return MCPSnapshotStatus(
            snapshotID: record.document.snapshotId,
            capturedAt: record.document.capturedAt,
            isStale: now.timeIntervalSince(capturedDate) > lookinMCPSnapshotStaleWindow
        )
    }

    /// 列出 current 与 history 中可读取的全部 snapshot。
    func listSnapshots() throws -> [SnapshotSummary] {
        var recordsByID: [String: SnapshotRecord] = [:]
        if let current = try loadCurrentSnapshotIfExists() {
            recordsByID[current.document.snapshotId] = current
        }

        let historyRoot = rootURL.appendingPathComponent("history", isDirectory: true)
        if let directoryNames = try? FileManager.default.contentsOfDirectory(atPath: historyRoot.path) {
            for directoryName in directoryNames {
                let directoryURL = historyRoot.appendingPathComponent(directoryName, isDirectory: true)
                let snapshotURL = directoryURL.appendingPathComponent("snapshot.json", isDirectory: false)
                guard FileManager.default.fileExists(atPath: snapshotURL.path) else { continue }
                if let record = try? loadSnapshot(at: snapshotURL, isCurrent: false) {
                    if recordsByID[record.document.snapshotId]?.isCurrent == true {
                        continue
                    }
                    recordsByID[record.document.snapshotId] = record
                }
            }
        }

        return recordsByID.values
            .map { record in
                SnapshotSummary(
                    snapshotId: record.document.snapshotId,
                    capturedAt: record.document.capturedAt,
                    isCurrent: record.isCurrent,
                    snapshotDirectory: record.directoryURL.path,
                    snapshotFile: record.snapshotURL.path,
                    appName: record.document.app.appName,
                    bundleId: record.document.app.bundleId,
                    deviceDescription: record.document.app.deviceDescription,
                    osDescription: record.document.app.osDescription
                )
            }
            .sorted { lhs, rhs in
                if lhs.capturedAt == rhs.capturedAt {
                    return lhs.snapshotId > rhs.snapshotId
                }
                return lhs.capturedAt > rhs.capturedAt
            }
    }

    func latestSnapshot() throws -> SnapshotRecord {
        guard let record = try loadCurrentSnapshotIfExists() ?? loadNewestHistorySnapshotIfExists() else {
            throw MCPServerError.noSnapshotAvailable
        }
        return record
    }

    func snapshot(snapshotId: String?) throws -> SnapshotRecord {
        guard let snapshotId else {
            return try latestSnapshot()
        }

        for summary in try listSnapshots() where summary.snapshotId == snapshotId {
            return try loadSnapshot(at: URL(fileURLWithPath: summary.snapshotFile), isCurrent: summary.isCurrent)
        }
        throw MCPServerError.snapshotNotFound(snapshotId)
    }

    /// 按照固定过滤语义在本地 snapshot 上执行查询。
    func query(_ query: SnapshotQuery) throws -> QueryResponse {
        let record = try snapshot(snapshotId: query.snapshotId)
        let index = SnapshotTreeIndex(nodes: record.document.tree.nodes)
        let matchedNodes = record.document.tree.nodes.filter { node in
            matches(node: node, query: query)
        }
        let limitedMatches = Array(matchedNodes.prefix(query.maxMatches))
        let excerpt = query.includeTree ? buildExcerpt(index: index, roots: record.document.tree.rootNodeIds, matches: limitedMatches) : nil

        var notes: [String] = []
        if isQueryEmpty(query) {
            notes.append("未提供过滤条件，因此 `matches` 为空，只返回当前页面的层级摘录。")
        }
        if matchedNodes.count > query.maxMatches {
            notes.append("命中数量超过上限，结果已截断为前 \(query.maxMatches) 条。")
        }

        return QueryResponse(
            snapshotId: record.document.snapshotId,
            capturedAt: record.document.capturedAt,
            snapshotDirectory: record.directoryURL.path,
            snapshotFile: record.snapshotURL.path,
            app: record.document.app,
            visibleViewControllerNames: record.document.visibleViewControllerNames,
            screenshot: record.document.screenshot,
            filtersApplied: QueryFilters(
                vcName: query.vcName,
                ivarName: query.ivarName,
                className: query.className,
                text: query.text
            ),
            matchCount: limitedMatches.count,
            matches: limitedMatches.map { node in
                QueryMatch(
                    nodeId: node.nodeId,
                    oid: node.oid,
                    title: node.title,
                    subtitle: node.subtitle,
                    className: node.className,
                    hostViewControllerName: node.hostViewControllerName,
                    ivarNames: node.ivarNames,
                    frame: node.frame,
                    bounds: node.bounds,
                    frameToRoot: node.frameToRoot,
                    isHidden: node.isHidden,
                    alpha: node.alpha,
                    textValues: node.textValues ?? [],
                    layoutEvidence: node.layoutEvidence,
                    visualEvidence: node.visualEvidence
                )
            },
            treeExcerpt: excerpt,
            diagnosticNotes: notes
        )
    }

    func findNodes(_ query: SnapshotQuery) throws -> FindNodesResponse {
        let record = try snapshot(snapshotId: query.snapshotId)
        let matchedNodes = record.document.tree.nodes.compactMap { node -> (SnapshotNode, [String])? in
            guard let reasons = matchReasons(node: node, query: query) else { return nil }
            return (node, reasons)
        }
        let limitedMatches = Array(matchedNodes.prefix(query.maxMatches))

        var notes: [String] = []
        if isQueryEmpty(query) {
            notes.append("未提供过滤条件，因此 `nodes` 为空。")
        }
        if matchedNodes.count > query.maxMatches {
            notes.append("命中数量超过上限，结果已截断为前 \(query.maxMatches) 条。")
        }

        return FindNodesResponse(
            snapshotId: record.document.snapshotId,
            capturedAt: record.document.capturedAt,
            snapshotDirectory: record.directoryURL.path,
            snapshotFile: record.snapshotURL.path,
            app: record.document.app,
            screenshot: record.document.screenshot,
            filtersApplied: QueryFilters(
                vcName: query.vcName,
                ivarName: query.ivarName,
                className: query.className,
                text: query.text
            ),
            matchCount: limitedMatches.count,
            nodes: limitedMatches.map { node, reasons in
                FoundNode(
                    nodeId: node.nodeId,
                    oid: node.oid,
                    title: node.title,
                    subtitle: node.subtitle,
                    className: node.className,
                    hostViewControllerName: node.hostViewControllerName,
                    ivarNames: node.ivarNames,
                    textValues: node.textValues ?? [],
                    frameToRoot: node.frameToRoot ?? node.frame,
                    isHidden: node.isHidden,
                    alpha: node.alpha,
                    matchedBy: reasons
                )
            },
            diagnosticNotes: notes
        )
    }

    func nodeDetails(snapshotId: String?, nodeId: String) throws -> NodeDetailsResponse {
        let record = try snapshot(snapshotId: snapshotId)
        let index = SnapshotTreeIndex(nodes: record.document.tree.nodes)
        let node = try requireNode(nodeId: nodeId, in: index)
        let parent = node.parentId.flatMap { index.byID[$0] }.map(nodeReference)
        let children = node.childIds.compactMap { index.byID[$0] }.map(nodeReference)

        return NodeDetailsResponse(
            snapshotId: record.document.snapshotId,
            capturedAt: record.document.capturedAt,
            snapshotDirectory: record.directoryURL.path,
            snapshotFile: record.snapshotURL.path,
            app: record.document.app,
            screenshot: record.document.screenshot,
            node: node,
            parent: parent,
            children: children,
            diagnosticNotes: []
        )
    }

    func nodeRelations(snapshotId: String?, nodeId: String) throws -> NodeRelationsResponse {
        let record = try snapshot(snapshotId: snapshotId)
        let index = SnapshotTreeIndex(nodes: record.document.tree.nodes)
        let node = try requireNode(nodeId: nodeId, in: index)

        let parentNode = node.parentId.flatMap { index.byID[$0] }
        let parentRelated = parentNode.map {
            RelatedNode(node: nodeReference($0), relation: relativeMetrics(from: node, to: $0))
        }
        let ancestors = index.ancestors(of: node.nodeId).map(nodeReference)
        let siblings = index.siblings(of: node.nodeId).map {
            RelatedNode(node: nodeReference($0), relation: relativeMetrics(from: node, to: $0))
        }
        let children = node.childIds.compactMap { index.byID[$0] }.map {
            RelatedNode(node: nodeReference($0), relation: relativeMetrics(from: node, to: $0))
        }

        return NodeRelationsResponse(
            snapshotId: record.document.snapshotId,
            capturedAt: record.document.capturedAt,
            snapshotDirectory: record.directoryURL.path,
            snapshotFile: record.snapshotURL.path,
            app: record.document.app,
            screenshot: record.document.screenshot,
            node: nodeReference(node),
            parent: parentRelated,
            ancestors: ancestors,
            siblings: siblings,
            children: children,
            withinParentInsets: parentNode.flatMap { parentInsets(of: node, in: $0) },
            diagnosticNotes: []
        )
    }

    func subtree(snapshotId: String?, nodeId: String, maxDepth: Int, maxNodes: Int) throws -> SubtreeResponse {
        let record = try snapshot(snapshotId: snapshotId)
        let index = SnapshotTreeIndex(nodes: record.document.tree.nodes)
        let rootNode = try requireNode(nodeId: nodeId, in: index)
        let clampedDepth = max(0, min(maxDepth, 8))
        let clampedMaxNodes = max(1, min(maxNodes, 500))

        let descendants = index.descendants(of: rootNode.nodeId, maxDepth: clampedDepth, maxNodes: clampedMaxNodes)
        let truncated = descendants.count >= clampedMaxNodes && index.totalDescendantCount(of: rootNode.nodeId, maxDepth: clampedDepth) > descendants.count

        return SubtreeResponse(
            snapshotId: record.document.snapshotId,
            capturedAt: record.document.capturedAt,
            snapshotDirectory: record.directoryURL.path,
            snapshotFile: record.snapshotURL.path,
            app: record.document.app,
            screenshot: record.document.screenshot,
            rootNodeId: rootNode.nodeId,
            maxDepth: clampedDepth,
            maxNodes: clampedMaxNodes,
            returnedNodeCount: descendants.count,
            truncated: truncated,
            nodes: descendants.map { item in
                SubtreeNodeEntry(
                    nodeId: item.node.nodeId,
                    parentId: item.node.parentId,
                    depth: item.depth,
                    title: item.node.title,
                    subtitle: item.node.subtitle,
                    className: item.node.className,
                    hostViewControllerName: item.node.hostViewControllerName,
                    ivarNames: item.node.ivarNames,
                    textValues: item.node.textValues ?? [],
                    frameToRoot: item.node.frameToRoot ?? item.node.frame,
                    isHidden: item.node.isHidden,
                    alpha: item.node.alpha,
                    childCount: item.node.childIds.count
                )
            },
            diagnosticNotes: truncated ? ["命中子树节点超过上限，结果已截断。"] : []
        )
    }

    func cropScreenshot(snapshotId: String?, nodeId: String, padding: Double) throws -> ScreenshotCropResponse {
        let record = try snapshot(snapshotId: snapshotId)
        let index = SnapshotTreeIndex(nodes: record.document.tree.nodes)
        let node = try requireNode(nodeId: nodeId, in: index)

        guard let screenshot = record.document.screenshot else {
            throw MCPServerError.screenshotUnavailable
        }
        guard let nodeRect = geometryRect(for: node) else {
            throw MCPServerError.invalidArguments("INVALID_ARGUMENTS: 节点缺少可用于裁图的 frame 信息。")
        }

        let screenshotURL = record.directoryURL.appendingPathComponent(screenshot.relativePath, isDirectory: false)
        guard FileManager.default.fileExists(atPath: screenshotURL.path) else {
            throw MCPServerError.screenshotUnavailable
        }

        guard let source = CGImageSourceCreateWithURL(screenshotURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw MCPServerError.cropFailed("SCREENSHOT_DECODE_FAILED: 无法读取 screenshot 图像。")
        }

        let pixelWidth = Double(image.width)
        let pixelHeight = Double(image.height)
        guard screenshot.width > 0, screenshot.height > 0 else {
            throw MCPServerError.cropFailed("SCREENSHOT_METADATA_INVALID: screenshot 宽高无效。")
        }

        let scaleX = pixelWidth / screenshot.width
        let scaleY = pixelHeight / screenshot.height
        let clampedPadding = max(0, min(padding, 200))

        let cropX = max(0, floor((nodeRect.x - clampedPadding) * scaleX))
        let cropY = max(0, floor((nodeRect.y - clampedPadding) * scaleY))
        let cropMaxX = min(pixelWidth, ceil((nodeRect.x + nodeRect.width + clampedPadding) * scaleX))
        let cropMaxY = min(pixelHeight, ceil((nodeRect.y + nodeRect.height + clampedPadding) * scaleY))
        let cropWidth = max(1, cropMaxX - cropX)
        let cropHeight = max(1, cropMaxY - cropY)

        let cgCropRect = CGRect(
            x: cropX,
            y: pixelHeight - cropY - cropHeight,
            width: cropWidth,
            height: cropHeight
        )

        guard let croppedImage = image.cropping(to: cgCropRect) else {
            throw MCPServerError.cropFailed("SCREENSHOT_CROP_FAILED: 无法按节点区域裁图。")
        }

        let logicalUpscaleX = screenshot.width / max(pixelWidth, 1)
        let logicalUpscaleY = screenshot.height / max(pixelHeight, 1)
        let outputScale = min(max(max(logicalUpscaleX, logicalUpscaleY), 1), 4)
        let finalImage = try upscaleImageIfNeeded(croppedImage, scale: outputScale)

        let cropsDirectory = record.directoryURL.appendingPathComponent("mcp-crops", isDirectory: true)
        try FileManager.default.createDirectory(at: cropsDirectory, withIntermediateDirectories: true)
        let sanitizedNodeId = node.nodeId.replacingOccurrences(of: ":", with: "_")
        let cropURL = cropsDirectory.appendingPathComponent("\(record.document.snapshotId)-\(sanitizedNodeId)-p\(Int(clampedPadding)).png", isDirectory: false)

        guard let destination = CGImageDestinationCreateWithURL(cropURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw MCPServerError.cropFailed("SCREENSHOT_WRITE_FAILED: 无法创建裁图输出。")
        }
        CGImageDestinationAddImage(destination, finalImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw MCPServerError.cropFailed("SCREENSHOT_WRITE_FAILED: 无法写出裁图 PNG。")
        }

        var notes: [String] = []
        if abs(pixelWidth - screenshot.width) > 0.001 || abs(pixelHeight - screenshot.height) > 0.001 {
            notes.append("截图像素尺寸与 snapshot 逻辑尺寸不一致，已按比例换算裁图。")
        }
        if outputScale > 1.01 {
            notes.append("源 screenshot 分辨率偏低，裁图已按约 \(String(format: "%.2f", outputScale))x 自动放大。")
        }

        return ScreenshotCropResponse(
            snapshotId: record.document.snapshotId,
            capturedAt: record.document.capturedAt,
            snapshotDirectory: record.directoryURL.path,
            snapshotFile: record.snapshotURL.path,
            screenshotFile: screenshotURL.path,
            cropFile: cropURL.path,
            nodeId: node.nodeId,
            nodeFrameToRoot: nodeRect,
            screenshotLogicalSize: SnapshotRect(x: 0, y: 0, width: screenshot.width, height: screenshot.height),
            cropRectPixels: SnapshotRect(
                x: cropX,
                y: pixelHeight - cropY - cropHeight,
                width: cropWidth,
                height: cropHeight
            ),
            cropRectInScreenshot: SnapshotRect(
                x: cropX / scaleX,
                y: cropY / scaleY,
                width: cropWidth / scaleX,
                height: cropHeight / scaleY
            ),
            screenshotPixelSize: SnapshotRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight),
            outputPixelSize: SnapshotRect(x: 0, y: 0, width: Double(finalImage.width), height: Double(finalImage.height)),
            padding: clampedPadding,
            diagnosticNotes: notes
        )
    }

    /// 当 screenshot 的实际像素明显低于逻辑尺寸时，放大裁图输出以改善可读性。
    private func upscaleImageIfNeeded(_ image: CGImage, scale: Double) throws -> CGImage {
        guard scale > 1.01 else {
            return image
        }

        let outputWidth = max(1, Int((Double(image.width) * scale).rounded()))
        let outputHeight = max(1, Int((Double(image.height) * scale).rounded()))
        let outputSize = NSSize(width: outputWidth, height: outputHeight)
        let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        let resizedImage = NSImage(size: outputSize)

        resizedImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        nsImage.draw(in: NSRect(origin: .zero, size: outputSize))
        resizedImage.unlockFocus()

        guard let tiffData = resizedImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let cgImage = bitmap.cgImage else {
            throw MCPServerError.cropFailed("SCREENSHOT_RESIZE_FAILED: 无法放大裁图输出。")
        }
        return cgImage
    }

    private func loadCurrentSnapshotIfExists() throws -> SnapshotRecord? {
        let snapshotURL = rootURL
            .appendingPathComponent("current", isDirectory: true)
            .appendingPathComponent("snapshot.json", isDirectory: false)
        guard FileManager.default.fileExists(atPath: snapshotURL.path) else {
            return nil
        }
        return try loadSnapshot(at: snapshotURL, isCurrent: true)
    }

    private func loadNewestHistorySnapshotIfExists() throws -> SnapshotRecord? {
        try listSnapshots()
            .first(where: { !$0.isCurrent })
            .flatMap { try? loadSnapshot(at: URL(fileURLWithPath: $0.snapshotFile), isCurrent: false) }
    }

    private func loadSnapshot(at snapshotURL: URL, isCurrent: Bool) throws -> SnapshotRecord {
        do {
            let data = try Data(contentsOf: snapshotURL)
            let document = try decoder.decode(SnapshotDocument.self, from: data)
            return SnapshotRecord(
                document: document,
                snapshotURL: snapshotURL,
                directoryURL: snapshotURL.deletingLastPathComponent(),
                isCurrent: isCurrent
            )
        } catch let error as DecodingError {
            throw MCPServerError.invalidSnapshot("SNAPSHOT_DECODE_FAILED: \(error.localizedDescription)")
        } catch {
            throw MCPServerError.io("SNAPSHOT_READ_FAILED: \(error.localizedDescription)")
        }
    }

    private func matches(node: SnapshotNode, query: SnapshotQuery) -> Bool {
        matchReasons(node: node, query: query) != nil
    }

    private func matchReasons(node: SnapshotNode, query: SnapshotQuery) -> [String]? {
        if isQueryEmpty(query) {
            return nil
        }

        var reasons: [String] = []

        if let vcName = normalizedOptional(query.vcName) {
            let vcMatched = normalized(node.hostViewControllerName) == vcName
            if !vcMatched {
                return nil
            }
            reasons.append("vc_name")
        }

        if let ivarName = normalizedOptional(query.ivarName) {
            let ivarMatched = node.ivarNames.contains { normalized($0) == ivarName }
            if !ivarMatched {
                return nil
            }
            reasons.append("ivar_name")
        }

        if let className = normalizedOptional(query.className) {
            let classMatched =
                normalized(node.className) == className ||
                normalized(node.rawClassName) == className ||
                node.classChain.contains(where: { normalized($0) == className })
            if !classMatched {
                return nil
            }
            reasons.append("class_name")
        }

        if let text = normalizedOptional(query.text) {
            let searchable = normalized(node.searchText ?? "")
            if !searchable.contains(text) {
                return nil
            }
            reasons.append("text")
        }

        return reasons
    }

    private func isQueryEmpty(_ query: SnapshotQuery) -> Bool {
        [query.vcName, query.ivarName, query.className, query.text]
            .allSatisfy { ($0 ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func normalized(_ text: String?) -> String {
        (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func normalizedOptional(_ text: String?) -> String? {
        let normalizedText = normalized(text)
        return normalizedText.isEmpty ? nil : normalizedText
    }

    private func buildExcerpt(index: SnapshotTreeIndex, roots: [String], matches: [SnapshotNode]) -> [String] {
        let includedIDs: Set<String>
        let matchedIDs = Set(matches.map(\.nodeId))

        if matchedIDs.isEmpty {
            includedIDs = index.topLevelExcerpt(rootIDs: roots, maxDepth: 2, maxNodes: 80)
        } else {
            includedIDs = index.focusedExcerpt(matchIDs: matchedIDs, childDepth: 2, maxNodes: 120)
        }

        return index.nodesInOriginalOrder
            .filter { includedIDs.contains($0.nodeId) }
            .map { node in
                let indent = String(repeating: "  ", count: max(node.indentLevel, 0))
                let marker = matchedIDs.contains(node.nodeId) ? "* " : "- "
                var line = "\(marker)\(indent)\(node.title)"
                if !node.hostViewControllerName.isEmpty {
                    line += " [vc: \(node.hostViewControllerName)]"
                }
                if !node.ivarNames.isEmpty {
                    line += " [ivar: \(node.ivarNames.joined(separator: ", "))]"
                }
                if let rect = node.frameToRoot ?? node.frame {
                    line += " frame=(\(format(rect.x)), \(format(rect.y)), \(format(rect.width)), \(format(rect.height)))"
                }
                return line
            }
    }

    private func format(_ value: Double) -> String {
        let rounded = value.rounded()
        if abs(value - rounded) < 0.0001 {
            return String(Int(rounded))
        }
        return String(format: "%.2f", value)
    }

    private func requireNode(nodeId: String, in index: SnapshotTreeIndex) throws -> SnapshotNode {
        guard let node = index.byID[nodeId] else {
            throw MCPServerError.nodeNotFound(nodeId)
        }
        return node
    }

    private func nodeReference(_ node: SnapshotNode) -> NodeReference {
        NodeReference(
            nodeId: node.nodeId,
            oid: node.oid,
            title: node.title,
            subtitle: node.subtitle,
            className: node.className,
            hostViewControllerName: node.hostViewControllerName,
            ivarNames: node.ivarNames,
            textValues: node.textValues ?? [],
            frameToRoot: node.frameToRoot ?? node.frame,
            isHidden: node.isHidden,
            alpha: node.alpha
        )
    }

    private func parentInsets(of node: SnapshotNode, in parent: SnapshotNode) -> ParentInsets? {
        guard let nodeRect = geometryRect(for: node),
              let parentRect = geometryRect(for: parent) else {
            return nil
        }
        return ParentInsets(
            left: minX(nodeRect) - minX(parentRect),
            right: maxX(parentRect) - maxX(nodeRect),
            top: minY(nodeRect) - minY(parentRect),
            bottom: maxY(parentRect) - maxY(nodeRect)
        )
    }

    private func relativeMetrics(from source: SnapshotNode, to target: SnapshotNode) -> RelativeLayoutMetrics {
        guard let sourceRect = geometryRect(for: source),
              let targetRect = geometryRect(for: target) else {
            return RelativeLayoutMetrics(
                horizontalGap: nil,
                verticalGap: nil,
                centerDeltaX: nil,
                centerDeltaY: nil,
                overlapOnX: nil,
                overlapOnY: nil,
                relativePosition: nil
            )
        }

        let overlapOnX = minX(targetRect) < maxX(sourceRect) && maxX(targetRect) > minX(sourceRect)
        let overlapOnY = minY(targetRect) < maxY(sourceRect) && maxY(targetRect) > minY(sourceRect)

        let horizontalGap: Double
        if maxX(targetRect) <= minX(sourceRect) {
            horizontalGap = minX(sourceRect) - maxX(targetRect)
        } else if minX(targetRect) >= maxX(sourceRect) {
            horizontalGap = minX(targetRect) - maxX(sourceRect)
        } else {
            horizontalGap = 0
        }

        let verticalGap: Double
        if maxY(targetRect) <= minY(sourceRect) {
            verticalGap = minY(sourceRect) - maxY(targetRect)
        } else if minY(targetRect) >= maxY(sourceRect) {
            verticalGap = minY(targetRect) - maxY(sourceRect)
        } else {
            verticalGap = 0
        }

        var positionParts: [String] = []
        if maxX(targetRect) <= minX(sourceRect) {
            positionParts.append("left")
        } else if minX(targetRect) >= maxX(sourceRect) {
            positionParts.append("right")
        }
        if maxY(targetRect) <= minY(sourceRect) {
            positionParts.append("above")
        } else if minY(targetRect) >= maxY(sourceRect) {
            positionParts.append("below")
        }

        let relativePosition: String
        if overlapOnX && overlapOnY {
            relativePosition = "overlapping"
        } else if positionParts.isEmpty {
            relativePosition = "intersecting"
        } else {
            relativePosition = positionParts.joined(separator: "-")
        }

        return RelativeLayoutMetrics(
            horizontalGap: horizontalGap,
            verticalGap: verticalGap,
            centerDeltaX: midX(targetRect) - midX(sourceRect),
            centerDeltaY: midY(targetRect) - midY(sourceRect),
            overlapOnX: overlapOnX,
            overlapOnY: overlapOnY,
            relativePosition: relativePosition
        )
    }

    private func geometryRect(for node: SnapshotNode) -> SnapshotRect? {
        node.frameToRoot ?? node.frame
    }

    private func minX(_ rect: SnapshotRect) -> Double {
        rect.x
    }

    private func maxX(_ rect: SnapshotRect) -> Double {
        rect.x + rect.width
    }

    private func minY(_ rect: SnapshotRect) -> Double {
        rect.y
    }

    private func maxY(_ rect: SnapshotRect) -> Double {
        rect.y + rect.height
    }

    private func midX(_ rect: SnapshotRect) -> Double {
        rect.x + rect.width / 2
    }

    private func midY(_ rect: SnapshotRect) -> Double {
        rect.y + rect.height / 2
    }
}

private struct SnapshotTreeIndex {
    let nodesInOriginalOrder: [SnapshotNode]
    let byID: [String: SnapshotNode]
    let order: [String: Int]

    init(nodes: [SnapshotNode]) {
        self.nodesInOriginalOrder = nodes
        self.byID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.nodeId, $0) })
        self.order = Dictionary(uniqueKeysWithValues: nodes.enumerated().map { ($0.element.nodeId, $0.offset) })
    }

    func focusedExcerpt(matchIDs: Set<String>, childDepth: Int, maxNodes: Int) -> Set<String> {
        var included = Set<String>()
        for matchID in matchIDs {
            includeAncestors(of: matchID, into: &included)
            includeDescendants(of: matchID, depth: childDepth, into: &included)
        }
        return trim(included, maxNodes: maxNodes)
    }

    func topLevelExcerpt(rootIDs: [String], maxDepth: Int, maxNodes: Int) -> Set<String> {
        var included = Set<String>()
        for rootID in rootIDs {
            includeDescendants(of: rootID, depth: maxDepth, into: &included)
        }
        return trim(included, maxNodes: maxNodes)
    }

    private func includeAncestors(of nodeID: String, into included: inout Set<String>) {
        var cursor = nodeID
        while let node = byID[cursor] {
            included.insert(node.nodeId)
            guard let parentID = node.parentId else { break }
            cursor = parentID
        }
    }

    private func includeDescendants(of nodeID: String, depth: Int, into included: inout Set<String>) {
        guard let node = byID[nodeID] else { return }
        included.insert(node.nodeId)
        guard depth > 0 else { return }
        for childID in node.childIds {
            includeDescendants(of: childID, depth: depth - 1, into: &included)
        }
    }

    private func trim(_ included: Set<String>, maxNodes: Int) -> Set<String> {
        guard included.count > maxNodes else { return included }
        let ordered = included.sorted { (order[$0] ?? .max) < (order[$1] ?? .max) }
        return Set(ordered.prefix(maxNodes))
    }

    func ancestors(of nodeID: String) -> [SnapshotNode] {
        guard let node = byID[nodeID] else { return [] }
        var ancestors: [SnapshotNode] = []
        var cursor = node.parentId
        while let currentID = cursor, let currentNode = byID[currentID] {
            ancestors.append(currentNode)
            cursor = currentNode.parentId
        }
        return ancestors
    }

    func siblings(of nodeID: String) -> [SnapshotNode] {
        guard let node = byID[nodeID], let parentID = node.parentId, let parent = byID[parentID] else {
            return []
        }
        return parent.childIds.compactMap { childID in
            guard childID != nodeID else { return nil }
            return byID[childID]
        }
    }

    func descendants(of nodeID: String, maxDepth: Int, maxNodes: Int) -> [(node: SnapshotNode, depth: Int)] {
        guard let root = byID[nodeID] else { return [] }
        var result: [(node: SnapshotNode, depth: Int)] = [(root, 0)]
        guard maxNodes > 1 else { return Array(result.prefix(maxNodes)) }

        var queue: [(SnapshotNode, Int)] = [(root, 0)]
        var cursor = 0
        while cursor < queue.count, result.count < maxNodes {
            let (current, depth) = queue[cursor]
            cursor += 1
            guard depth < maxDepth else { continue }
            for childID in current.childIds {
                guard let child = byID[childID] else { continue }
                let nextDepth = depth + 1
                queue.append((child, nextDepth))
                result.append((child, nextDepth))
                if result.count >= maxNodes {
                    break
                }
            }
        }
        return result
    }

    func totalDescendantCount(of nodeID: String, maxDepth: Int) -> Int {
        descendants(of: nodeID, maxDepth: maxDepth, maxNodes: Int.max).count
    }
}
