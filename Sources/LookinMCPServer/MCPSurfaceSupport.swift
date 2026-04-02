import Foundation

/// 控制工具默认返回的信息密度，避免 LLM 无意间拿到过重上下文。
enum SurfaceDetail: String {
    case compact
    case standard
    case full

    static func parse(_ value: String?) -> SurfaceDetail {
        guard let value,
              let parsed = SurfaceDetail(rawValue: value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) else {
            return .compact
        }
        return parsed
    }
}

enum SurfaceInclude: String, CaseIterable {
    case layout
    case style
    case relations
    case children
}

struct MCPResourceLink: Encodable {
    let uri: String
    let title: String
    let mimeType: String
    let description: String
}

struct SurfaceNodeSummary: Encodable {
    let nodeId: String
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

struct SurfaceScreenResponse: Encodable {
    let snapshotId: String
    let capturedAt: String
    let app: SnapshotApp
    let visibleViewControllerNames: [String]
    let rootNodeCount: Int
    let totalNodeCount: Int
    let roots: [SurfaceNodeSummary]
    let detail: String
    let resourceLinks: [MCPResourceLink]
    let diagnosticNotes: [String]
}

struct SurfaceFoundNode: Encodable {
    let nodeId: String
    let title: String
    let className: String
    let hostViewControllerName: String
    let ivarNames: [String]
    let textValues: [String]
    let frameToRoot: SnapshotRect?
    let isHidden: Bool
    let alpha: Double
    let matchedBy: [String]
    let layoutEvidence: SnapshotLayoutEvidence?
    let visualEvidence: SnapshotVisualEvidence?
    let relations: FindNodeRelations?
}

struct FindNodeRelations: Encodable {
    let parentNodeId: String?
    let childCount: Int
}

struct SurfaceFindResponse: Encodable {
    let snapshotId: String
    let capturedAt: String
    let filtersApplied: QueryFilters
    let matchCount: Int
    let detail: String
    let include: [String]
    let nodes: [SurfaceFoundNode]
    let resourceLinks: [MCPResourceLink]
    let diagnosticNotes: [String]
}

struct SurfaceInspectResponse: Encodable {
    let snapshotId: String
    let capturedAt: String
    let detail: String
    let include: [String]
    let node: SurfaceNodeSummary
    let layoutEvidence: SnapshotLayoutEvidence?
    let visualEvidence: SnapshotVisualEvidence?
    let relations: SurfaceInspectRelations?
    let children: [NodeReference]?
    let resourceLinks: [MCPResourceLink]
    let diagnosticNotes: [String]
}

struct SurfaceInspectRelations: Encodable {
    let parent: RelatedNode?
    let ancestors: [NodeReference]
    let siblings: [RelatedNode]
    let withinParentInsets: ParentInsets?
}

struct SurfaceCaptureResponse: Encodable {
    let snapshotId: String
    let capturedAt: String
    let nodeId: String
    let padding: Double
    let cropFile: String
    let screenshotFile: String
    let cropRectInScreenshot: SnapshotRect
    let resourceLinks: [MCPResourceLink]
    let diagnosticNotes: [String]
}

struct SurfaceRawResponse: Encodable {
    let snapshotId: String
    let capturedAt: String
    let detail: String
    let snapshotDirectory: String
    let snapshotFile: String
    let app: SnapshotApp
    let resourceLinks: [MCPResourceLink]
    let snapshot: SnapshotDocument?
}

struct MCPPromptArgument: Encodable {
    let name: String
    let description: String
    let required: Bool
}

struct MCPPromptDefinition: Encodable {
    let name: String
    let title: String
    let description: String
    let arguments: [MCPPromptArgument]
}

enum MCPPromptCatalog {
    static let prompts: [MCPPromptDefinition] = [
        MCPPromptDefinition(
            name: "analyze-node-layout",
            title: "分析节点布局",
            description: "面向布局问题的标准工作流。适合检查 frame、约束、父子关系和局部截图是否一致。",
            arguments: [
                MCPPromptArgument(name: "snapshot_id", description: "可选，指定要读取的 snapshot。默认当前快照。", required: false),
                MCPPromptArgument(name: "node_id", description: "必填，要分析的目标节点。", required: true),
                MCPPromptArgument(name: "focus", description: "可选，补充本次重点，例如间距、约束或换行。", required: false),
            ]
        ),
        MCPPromptDefinition(
            name: "analyze-node-visual-style",
            title: "分析节点视觉样式",
            description: "面向视觉风格问题的标准工作流。适合检查颜色、透明度、圆角、边框和阴影。",
            arguments: [
                MCPPromptArgument(name: "snapshot_id", description: "可选，指定要读取的 snapshot。默认当前快照。", required: false),
                MCPPromptArgument(name: "node_id", description: "必填，要分析的目标节点。", required: true),
                MCPPromptArgument(name: "focus", description: "可选，补充本次重点，例如颜色、圆角或阴影。", required: false),
            ]
        ),
        MCPPromptDefinition(
            name: "diagnose-spacing-and-alignment",
            title: "诊断间距与对齐",
            description: "面向间距与对齐问题的标准工作流。适合分析 sibling gap、parent inset 和中心偏移。",
            arguments: [
                MCPPromptArgument(name: "snapshot_id", description: "可选，指定要读取的 snapshot。默认当前快照。", required: false),
                MCPPromptArgument(name: "node_id", description: "必填，要分析的目标节点。", required: true),
                MCPPromptArgument(name: "focus", description: "可选，补充本次重点，例如左右边距、中心对齐或 sibling 间距。", required: false),
            ]
        ),
    ]

    static func definition(named name: String) -> MCPPromptDefinition? {
        prompts.first { $0.name == name }
    }
}

enum LookinResourceURI {
    static func currentSummary() -> String {
        "lookin://snapshots/current/summary"
    }

    static func currentRaw() -> String {
        "lookin://snapshots/current/raw"
    }

    static func currentScreenshot() -> String {
        "lookin://snapshots/current/screenshot"
    }

    static func summary(snapshotId: String) -> String {
        "lookin://snapshots/\(snapshotId)/summary"
    }

    static func raw(snapshotId: String) -> String {
        "lookin://snapshots/\(snapshotId)/raw"
    }

    static func screenshot(snapshotId: String) -> String {
        "lookin://snapshots/\(snapshotId)/screenshot"
    }

    static func subtree(snapshotId: String, nodeId: String, maxDepth: Int = 2, maxNodes: Int = 80) -> String {
        "lookin://snapshots/\(snapshotId)/nodes/\(nodeId)/subtree?max_depth=\(maxDepth)&max_nodes=\(maxNodes)"
    }

    static func capture(snapshotId: String, nodeId: String, padding: Double = 0) -> String {
        "lookin://snapshots/\(snapshotId)/nodes/\(nodeId)/capture?padding=\(Int(padding))"
    }
}

struct ParsedResourceRequest {
    let snapshotId: String?
    let kind: String
    let nodeId: String?
    let maxDepth: Int
    let maxNodes: Int
    let padding: Double
}

enum ResourceURIParser {
    /// 解析 `lookin://snapshots/...` 风格 URI，供 resources/read 复用。
    static func parse(_ uriText: String) -> ParsedResourceRequest? {
        guard let components = URLComponents(string: uriText),
              components.scheme == "lookin",
              components.host == "snapshots" else {
            return nil
        }

        let pathSegments = components.path
            .split(separator: "/")
            .map(String.init)
        guard pathSegments.count >= 2 else {
            return nil
        }

        let snapshotId = pathSegments[0] == "current" ? nil : pathSegments[0]
        let params = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        if pathSegments.count == 2 {
            let kind = pathSegments[1]
            guard ["summary", "raw", "screenshot"].contains(kind) else { return nil }
            return ParsedResourceRequest(
                snapshotId: snapshotId,
                kind: kind,
                nodeId: nil,
                maxDepth: max(0, min(Int(params["max_depth"] ?? "") ?? 2, 8)),
                maxNodes: max(1, min(Int(params["max_nodes"] ?? "") ?? 80, 500)),
                padding: min(max(Double(params["padding"] ?? "") ?? 0, 0), 200)
            )
        }

        guard pathSegments.count == 4,
              pathSegments[1] == "nodes" else {
            return nil
        }

        let nodeId = pathSegments[2]
        let kind = pathSegments[3]
        guard ["subtree", "capture"].contains(kind) else {
            return nil
        }

        return ParsedResourceRequest(
            snapshotId: snapshotId,
            kind: kind,
            nodeId: nodeId,
            maxDepth: max(0, min(Int(params["max_depth"] ?? "") ?? 2, 8)),
            maxNodes: max(1, min(Int(params["max_nodes"] ?? "") ?? 80, 500)),
            padding: min(max(Double(params["padding"] ?? "") ?? 0, 0), 200)
        )
    }
}

extension JSONValue {
    static func arrayOfStrings(_ values: [String]) -> JSONValue {
        .array(values.map(JSONValue.string))
    }
}
