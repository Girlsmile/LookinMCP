import Foundation

final class MCPRequestHandler {
    private let store: LocalSnapshotStore

    init(store: LocalSnapshotStore = LocalSnapshotStore()) {
        self.store = store
    }

    func handle(message: JSONRPCMessage) throws -> JSONRPCMessage? {
        switch message.method {
        case "initialize":
            return initializeResponse(id: message.id)
        case "notifications/initialized":
            return nil
        case "tools/list":
            return toolListResponse(id: message.id)
        case "tools/call":
            return try handleToolCall(message: message)
        case "resources/list":
            return resourceListResponse(id: message.id)
        case "resources/read":
            return handleResourceRead(message: message)
        case "prompts/list":
            return promptListResponse(id: message.id)
        case "prompts/get":
            return handlePromptGet(message: message)
        default:
            return JSONRPCMessage(
                jsonrpc: "2.0",
                id: message.id,
                method: nil,
                params: nil,
                result: nil,
                error: RPCError(code: -32601, message: "Method not found")
            )
        }
    }

    func snapshotStatus(now: Date = Date()) -> MCPSnapshotStatus? {
        store.latestSnapshotStatus(now: now)
    }

    func snapshotRootPath() -> String {
        store.snapshotRootPath()
    }

    private func initializeResponse(id: RPCID?) -> JSONRPCMessage {
        JSONRPCMessage(
            jsonrpc: "2.0",
            id: id,
            method: nil,
            params: nil,
            result: .object([
                "protocolVersion": .string(lookinMCPProtocolVersion),
                "capabilities": .object([
                    "tools": .object([:]),
                    "resources": .object([:]),
                    "prompts": .object([:]),
                ]),
                "serverInfo": .object([
                    "name": .string("lookin-mcp"),
                    "version": .string(lookinMCPServerVersion),
                ]),
            ]),
            error: nil
        )
    }

    private func toolListResponse(id: RPCID?) -> JSONRPCMessage {
        JSONRPCMessage(
            jsonrpc: "2.0",
            id: id,
            method: nil,
            params: nil,
            result: .object([
                "tools": .array([
                    toolDescriptor(
                        name: "lookin.screen",
                        description: "先看页面全局时用这个工具。返回当前或指定 snapshot 的紧凑摘要、可见 VC、根节点概览，以及 raw/screenshot 等按需展开入口。",
                        properties: [
                            "snapshot_id": stringSchema(description: "可选，指定 snapshot_id。默认读取当前快照。"),
                            "detail": enumSchema(values: ["compact", "standard", "full"], description: "控制返回信息密度，默认 compact。"),
                        ]
                    ),
                    toolDescriptor(
                        name: "lookin.find",
                        description: "已知 ivar、VC、class 或文案时优先用这个工具。它会定位候选节点，并返回适合继续 inspect 的紧凑命中结果。",
                        properties: [
                            "snapshot_id": stringSchema(description: "可选，指定 snapshot_id。默认读取当前快照。"),
                            "vc_name": stringSchema(description: "可选，按 host view controller 名称精确匹配。"),
                            "ivar_name": stringSchema(description: "可选，按 ivar 名称精确匹配。"),
                            "class_name": stringSchema(description: "可选，按类名或 class chain 匹配。"),
                            "text": stringSchema(description: "可选，按文本模糊匹配。"),
                            "max_matches": numberSchema(description: "可选，结果上限，默认 10。"),
                            "detail": enumSchema(values: ["compact", "standard", "full"], description: "控制返回信息密度，默认 compact。"),
                            "include": includeSchema(),
                        ]
                    ),
                    toolDescriptor(
                        name: "lookin.inspect",
                        description: "围绕单个节点取证时用这个工具。它统一返回布局、样式、父子兄弟关系和子节点摘要，避免再分别调用 details/relations/subtree。",
                        properties: [
                            "snapshot_id": stringSchema(description: "可选，指定 snapshot_id。默认读取当前快照。"),
                            "node_id": stringSchema(description: "必填，要分析的节点。"),
                            "detail": enumSchema(values: ["compact", "standard", "full"], description: "控制返回信息密度，默认 compact。"),
                            "include": includeSchema(),
                        ],
                        required: ["node_id"]
                    ),
                    toolDescriptor(
                        name: "lookin.capture",
                        description: "需要视觉证据时用这个工具。它会按 node_id 生成局部裁图，并返回裁图文件、截图范围和可复读的 capture resource。",
                        properties: [
                            "snapshot_id": stringSchema(description: "可选，指定 snapshot_id。默认读取当前快照。"),
                            "node_id": stringSchema(description: "必填，要裁图的节点。"),
                            "padding": numberSchema(description: "可选，裁图外扩像素，默认 0。"),
                        ],
                        required: ["node_id"]
                    ),
                    toolDescriptor(
                        name: "lookin.raw",
                        description: "只有在 screen/find/inspect 证据仍不够时再用。它是完整 snapshot 原文的兜底入口，默认只返回摘要和 raw resource 链接。",
                        properties: [
                            "snapshot_id": stringSchema(description: "可选，指定 snapshot_id。默认读取当前快照。"),
                            "detail": enumSchema(values: ["compact", "standard", "full"], description: "full 时内联完整 snapshot。"),
                        ]
                    ),
                ]),
            ]),
            error: nil
        )
    }

    private func resourceListResponse(id: RPCID?) -> JSONRPCMessage {
        let resources: [JSONValue]
        if let record = try? store.latestSnapshot() {
            resources = [
                resourceDescriptor(
                    uri: LookinResourceURI.currentSummary(),
                    name: "当前快照摘要",
                    description: "当前 snapshot 的紧凑页面摘要，适合给 LLM 先建立全局上下文。",
                    mimeType: "application/json"
                ),
                resourceDescriptor(
                    uri: LookinResourceURI.currentRaw(),
                    name: "当前快照原文",
                    description: "当前 snapshot 的完整 JSON，仅在需要大上下文时再读取。",
                    mimeType: "application/json"
                ),
                resourceDescriptor(
                    uri: LookinResourceURI.currentScreenshot(),
                    name: "当前快照截图",
                    description: "当前 snapshot 的截图元数据与本地文件路径，适合与 capture 配合使用。",
                    mimeType: "application/json"
                ),
                resourceDescriptor(
                    uri: LookinResourceURI.summary(snapshotId: record.document.snapshotId),
                    name: "指定快照摘要",
                    description: "具名 snapshot 的紧凑摘要资源，便于客户端缓存和复读。",
                    mimeType: "application/json"
                ),
                resourceDescriptor(
                    uri: LookinResourceURI.raw(snapshotId: record.document.snapshotId),
                    name: "指定快照原文",
                    description: "具名 snapshot 的完整原文资源，便于客户端缓存和按需深读。",
                    mimeType: "application/json"
                ),
            ]
        } else {
            resources = []
        }

        return JSONRPCMessage(
            jsonrpc: "2.0",
            id: id,
            method: nil,
            params: nil,
            result: .object([
                "resources": .array(resources),
            ]),
            error: nil
        )
    }

    private func promptListResponse(id: RPCID?) -> JSONRPCMessage {
        let prompts = MCPPromptCatalog.prompts.map { prompt in
            JSONValue.object([
                "name": .string(prompt.name),
                "title": .string(prompt.title),
                "description": .string(prompt.description),
                "arguments": (try? prompt.arguments.jsonValue()) ?? .array([]),
            ])
        }

        return JSONRPCMessage(
            jsonrpc: "2.0",
            id: id,
            method: nil,
            params: nil,
            result: .object([
                "prompts": .array(prompts),
            ]),
            error: nil
        )
    }

    private func handleToolCall(message: JSONRPCMessage) throws -> JSONRPCMessage {
        guard case .object(let params)? = message.params,
              case .string(let toolName)? = params["name"] else {
            throw MCPServerError.invalidArguments("INVALID_ARGUMENTS: 缺少 tool name。")
        }

        let arguments = params["arguments"]?.objectValue ?? [:]

        let payloadText: String
        do {
            switch toolName {
            case "lookin.screen":
                payloadText = try screenPayload(arguments: arguments).prettyJSONString()
            case "lookin.find":
                payloadText = try findPayload(arguments: arguments).prettyJSONString()
            case "lookin.inspect":
                payloadText = try inspectPayload(arguments: arguments).prettyJSONString()
            case "lookin.capture":
                payloadText = try capturePayload(arguments: arguments).prettyJSONString()
            case "lookin.raw":
                payloadText = try rawPayload(arguments: arguments).prettyJSONString()
            default:
                throw MCPServerError.invalidArguments("UNKNOWN_TOOL: 未知工具 `\(toolName)`。请迁移到 `lookin.screen/find/inspect/capture/raw`。")
            }

            return textToolResponse(id: message.id, text: payloadText)
        } catch let error as MCPServerError {
            return JSONRPCMessage(
                jsonrpc: "2.0",
                id: message.id,
                method: nil,
                params: nil,
                result: nil,
                error: RPCError(code: -32000, message: error.localizedDescription)
            )
        } catch {
            return JSONRPCMessage(
                jsonrpc: "2.0",
                id: message.id,
                method: nil,
                params: nil,
                result: nil,
                error: RPCError(code: -32000, message: error.localizedDescription)
            )
        }
    }

    private func handleResourceRead(message: JSONRPCMessage) -> JSONRPCMessage {
        do {
            guard case .object(let params)? = message.params,
                  let uri = params["uri"]?.stringValue,
                  let request = ResourceURIParser.parse(uri) else {
                throw MCPServerError.invalidArguments("INVALID_ARGUMENTS: `uri` 无效，必须是 `lookin://snapshots/...`。")
            }

            let payloadText: String
            let mimeType = "application/json"
            switch request.kind {
            case "summary":
                payloadText = try screenPayload(
                    arguments: [
                        "snapshot_id": optionalStringValue(request.snapshotId),
                        "detail": .string("compact"),
                    ].compactMapValues { $0 }
                ).prettyJSONString()
            case "raw":
                payloadText = try rawPayload(
                    arguments: [
                        "snapshot_id": optionalStringValue(request.snapshotId),
                        "detail": .string("full"),
                    ].compactMapValues { $0 }
                ).prettyJSONString()
            case "screenshot":
                payloadText = try screenshotResourcePayload(snapshotId: request.snapshotId).prettyJSONString()
            case "subtree":
                guard let nodeId = request.nodeId else {
                    throw MCPServerError.invalidArguments("INVALID_ARGUMENTS: subtree resource 缺少 node_id。")
                }
                payloadText = try store.subtree(
                    snapshotId: request.snapshotId,
                    nodeId: nodeId,
                    maxDepth: request.maxDepth,
                    maxNodes: request.maxNodes
                ).prettyJSONString()
            case "capture":
                guard let nodeId = request.nodeId else {
                    throw MCPServerError.invalidArguments("INVALID_ARGUMENTS: capture resource 缺少 node_id。")
                }
                payloadText = try capturePayload(
                    arguments: [
                        "snapshot_id": optionalStringValue(request.snapshotId),
                        "node_id": .string(nodeId),
                        "padding": .number(request.padding),
                    ].compactMapValues { $0 }
                ).prettyJSONString()
            default:
                throw MCPServerError.invalidArguments("INVALID_ARGUMENTS: 不支持的 resource kind=\(request.kind)。")
            }

            return JSONRPCMessage(
                jsonrpc: "2.0",
                id: message.id,
                method: nil,
                params: nil,
                result: .object([
                    "contents": .array([
                        .object([
                            "uri": .string(uri),
                            "mimeType": .string(mimeType),
                            "text": .string(payloadText),
                        ]),
                    ]),
                ]),
                error: nil
            )
        } catch let error as MCPServerError {
            return JSONRPCMessage(
                jsonrpc: "2.0",
                id: message.id,
                method: nil,
                params: nil,
                result: nil,
                error: RPCError(code: -32000, message: error.localizedDescription)
            )
        } catch {
            return JSONRPCMessage(
                jsonrpc: "2.0",
                id: message.id,
                method: nil,
                params: nil,
                result: nil,
                error: RPCError(code: -32000, message: error.localizedDescription)
            )
        }
    }

    private func handlePromptGet(message: JSONRPCMessage) -> JSONRPCMessage {
        do {
            guard case .object(let params)? = message.params,
                  let name = params["name"]?.stringValue,
                  let prompt = MCPPromptCatalog.definition(named: name) else {
                throw MCPServerError.invalidArguments("INVALID_ARGUMENTS: 未知 prompt。")
            }

            let arguments = params["arguments"]?.objectValue ?? [:]
            let snapshotID = arguments["snapshot_id"]?.stringValue ?? "current"
            let nodeID = arguments["node_id"]?.stringValue ?? "<node_id>"
            let focus = arguments["focus"]?.stringValue ?? "未额外指定"

            let promptText = promptText(for: prompt.name, snapshotID: snapshotID, nodeID: nodeID, focus: focus)

            return JSONRPCMessage(
                jsonrpc: "2.0",
                id: message.id,
                method: nil,
                params: nil,
                result: .object([
                    "description": .string(prompt.description),
                    "messages": .array([
                        .object([
                            "role": .string("user"),
                            "content": .object([
                                "type": .string("text"),
                                "text": .string(promptText),
                            ]),
                        ]),
                    ]),
                ]),
                error: nil
            )
        } catch let error as MCPServerError {
            return JSONRPCMessage(
                jsonrpc: "2.0",
                id: message.id,
                method: nil,
                params: nil,
                result: nil,
                error: RPCError(code: -32000, message: error.localizedDescription)
            )
        } catch {
            return JSONRPCMessage(
                jsonrpc: "2.0",
                id: message.id,
                method: nil,
                params: nil,
                result: nil,
                error: RPCError(code: -32000, message: error.localizedDescription)
            )
        }
    }

    private func textToolResponse(id: RPCID?, text: String) -> JSONRPCMessage {
        JSONRPCMessage(
            jsonrpc: "2.0",
            id: id,
            method: nil,
            params: nil,
            result: .object([
                "content": .array([
                    .object([
                        "type": .string("text"),
                        "text": .string(text),
                    ]),
                ]),
            ]),
            error: nil
        )
    }

    /// 返回页面级紧凑摘要，作为所有分析流程的起点。
    private func screenPayload(arguments: [String: JSONValue]) throws -> SurfaceScreenResponse {
        let detail = SurfaceDetail.parse(arguments["detail"]?.stringValue)
        let record = try store.snapshot(snapshotId: arguments["snapshot_id"]?.stringValue)
        let rootIDs = Set(record.document.tree.rootNodeIds)
        let roots = record.document.tree.nodes
            .filter { rootIDs.contains($0.nodeId) }
            .map { surfaceNodeSummary(from: $0) }

        let notes = detail == .compact ? ["默认只返回页面摘要与 resource_links，完整 snapshot 请改读 raw resource。"] : []

        return SurfaceScreenResponse(
            snapshotId: record.document.snapshotId,
            capturedAt: record.document.capturedAt,
            app: record.document.app,
            visibleViewControllerNames: record.document.visibleViewControllerNames,
            rootNodeCount: record.document.tree.rootNodeIds.count,
            totalNodeCount: record.document.tree.nodeCount ?? record.document.tree.nodes.count,
            roots: detail == .compact ? Array(roots.prefix(6)) : roots,
            detail: detail.rawValue,
            resourceLinks: snapshotResourceLinks(for: record),
            diagnosticNotes: notes
        )
    }

    /// 查找节点时默认只返回紧凑命中，必要时再通过 inspect 或 subtree 资源展开。
    private func findPayload(arguments: [String: JSONValue]) throws -> SurfaceFindResponse {
        let detail = SurfaceDetail.parse(arguments["detail"]?.stringValue)
        let include = parseIncludes(arguments["include"])
        let query = SnapshotQuery(
            snapshotId: arguments["snapshot_id"]?.stringValue,
            vcName: arguments["vc_name"]?.stringValue,
            ivarName: arguments["ivar_name"]?.stringValue,
            className: arguments["class_name"]?.stringValue,
            text: arguments["text"]?.stringValue,
            maxMatches: max(1, min(arguments["max_matches"]?.intValue ?? 10, 50)),
            includeTree: false
        )
        let record = try store.snapshot(snapshotId: query.snapshotId)
        let response = try store.findNodes(query)
        let nodesByID = Dictionary(uniqueKeysWithValues: record.document.tree.nodes.map { ($0.nodeId, $0) })

        let nodes = response.nodes.map { found -> SurfaceFoundNode in
            let node = nodesByID[found.nodeId]
            return SurfaceFoundNode(
                nodeId: found.nodeId,
                title: found.title,
                className: found.className,
                hostViewControllerName: found.hostViewControllerName,
                ivarNames: found.ivarNames,
                textValues: found.textValues,
                frameToRoot: found.frameToRoot,
                isHidden: found.isHidden,
                alpha: found.alpha,
                matchedBy: found.matchedBy,
                layoutEvidence: shouldInclude(.layout, in: include, detail: detail) ? node?.layoutEvidence : nil,
                visualEvidence: shouldInclude(.style, in: include, detail: detail) ? node?.visualEvidence : nil,
                relations: shouldInclude(.relations, in: include, detail: detail) ? FindNodeRelations(
                    parentNodeId: node?.parentId,
                    childCount: node?.childIds.count ?? 0
                ) : nil
            )
        }

        return SurfaceFindResponse(
            snapshotId: response.snapshotId,
            capturedAt: response.capturedAt,
            filtersApplied: response.filtersApplied,
            matchCount: response.matchCount,
            detail: detail.rawValue,
            include: include.map(\.rawValue),
            nodes: nodes,
            resourceLinks: snapshotResourceLinks(for: record),
            diagnosticNotes: response.diagnosticNotes
        )
    }

    /// inspect 汇总节点核心证据，避免让客户端同时调用 details + relations + subtree。
    private func inspectPayload(arguments: [String: JSONValue]) throws -> SurfaceInspectResponse {
        guard let nodeID = arguments["node_id"]?.stringValue,
              !nodeID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MCPServerError.invalidArguments("INVALID_ARGUMENTS: `node_id` 不能为空。")
        }

        let detail = SurfaceDetail.parse(arguments["detail"]?.stringValue)
        let include = parseIncludes(arguments["include"])
        let snapshotID = arguments["snapshot_id"]?.stringValue

        let details = try store.nodeDetails(snapshotId: snapshotID, nodeId: nodeID)
        let relations = try store.nodeRelations(snapshotId: snapshotID, nodeId: nodeID)
        let record = try store.snapshot(snapshotId: snapshotID)

        return SurfaceInspectResponse(
            snapshotId: details.snapshotId,
            capturedAt: details.capturedAt,
            detail: detail.rawValue,
            include: include.map(\.rawValue),
            node: surfaceNodeSummary(from: details.node),
            layoutEvidence: shouldInclude(.layout, in: include, detail: detail) ? details.node.layoutEvidence : nil,
            visualEvidence: shouldInclude(.style, in: include, detail: detail) ? details.node.visualEvidence : nil,
            relations: shouldInclude(.relations, in: include, detail: detail) ? SurfaceInspectRelations(
                parent: relations.parent,
                ancestors: detail == .compact ? Array(relations.ancestors.prefix(2)) : relations.ancestors,
                siblings: detail == .compact ? Array(relations.siblings.prefix(4)) : relations.siblings,
                withinParentInsets: relations.withinParentInsets
            ) : nil,
            children: shouldInclude(.children, in: include, detail: detail) ? details.children : nil,
            resourceLinks: [
                MCPResourceLink(
                    uri: LookinResourceURI.subtree(snapshotId: details.snapshotId, nodeId: nodeID, maxDepth: detail == .full ? 4 : 2, maxNodes: detail == .full ? 200 : 80),
                    title: "节点子树",
                    mimeType: "application/json",
                    description: "读取该节点的局部子树。"
                ),
                MCPResourceLink(
                    uri: LookinResourceURI.capture(snapshotId: details.snapshotId, nodeId: nodeID, padding: 8),
                    title: "节点裁图",
                    mimeType: "application/json",
                    description: "读取该节点的局部截图裁图。"
                ),
                snapshotResourceLinks(for: record)[1],
            ],
            diagnosticNotes: detail == .compact ? ["默认不内联完整子树，请按需读取 subtree resource。"] : []
        )
    }

    private func capturePayload(arguments: [String: JSONValue]) throws -> SurfaceCaptureResponse {
        guard let nodeID = arguments["node_id"]?.stringValue,
              !nodeID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MCPServerError.invalidArguments("INVALID_ARGUMENTS: `node_id` 不能为空。")
        }

        let padding = min(max(arguments["padding"]?.numberValue ?? 0, 0), 200)
        let response = try store.cropScreenshot(
            snapshotId: arguments["snapshot_id"]?.stringValue,
            nodeId: nodeID,
            padding: padding
        )

        return SurfaceCaptureResponse(
            snapshotId: response.snapshotId,
            capturedAt: response.capturedAt,
            nodeId: response.nodeId,
            padding: response.padding,
            cropFile: response.cropFile,
            screenshotFile: response.screenshotFile,
            cropRectInScreenshot: response.cropRectInScreenshot,
            resourceLinks: [
                MCPResourceLink(
                    uri: LookinResourceURI.capture(snapshotId: response.snapshotId, nodeId: response.nodeId, padding: response.padding),
                    title: "裁图资源",
                    mimeType: "application/json",
                    description: "可再次读取同一节点裁图结果。"
                ),
                MCPResourceLink(
                    uri: LookinResourceURI.screenshot(snapshotId: response.snapshotId),
                    title: "原始截图资源",
                    mimeType: "application/json",
                    description: "查看完整 screenshot 元数据与本地文件路径。"
                ),
            ],
            diagnosticNotes: response.diagnosticNotes
        )
    }

    private func rawPayload(arguments: [String: JSONValue]) throws -> SurfaceRawResponse {
        let detail = SurfaceDetail.parse(arguments["detail"]?.stringValue)
        let record = try store.snapshot(snapshotId: arguments["snapshot_id"]?.stringValue)
        return SurfaceRawResponse(
            snapshotId: record.document.snapshotId,
            capturedAt: record.document.capturedAt,
            detail: detail.rawValue,
            snapshotDirectory: record.directoryURL.path,
            snapshotFile: record.snapshotURL.path,
            app: record.document.app,
            resourceLinks: snapshotResourceLinks(for: record),
            snapshot: detail == .full ? record.document : nil
        )
    }

    private func screenshotResourcePayload(snapshotId: String?) throws -> [String: String] {
        let record = try store.snapshot(snapshotId: snapshotId)
        let screenshot = record.document.screenshot
        let screenshotPath = screenshot.map { record.directoryURL.appendingPathComponent($0.relativePath, isDirectory: false).path } ?? ""
        return [
            "snapshot_id": record.document.snapshotId,
            "captured_at": record.document.capturedAt,
            "screenshot_file": screenshotPath,
            "relative_path": screenshot?.relativePath ?? "",
            "note": screenshot == nil ? "当前 snapshot 不包含 screenshot。" : "返回 screenshot 元数据与本地文件路径。",
        ]
    }

    private func snapshotResourceLinks(for record: SnapshotRecord) -> [MCPResourceLink] {
        [
            MCPResourceLink(
                uri: LookinResourceURI.summary(snapshotId: record.document.snapshotId),
                title: "快照摘要",
                mimeType: "application/json",
                description: "读取当前 snapshot 的紧凑摘要。"
            ),
            MCPResourceLink(
                uri: LookinResourceURI.raw(snapshotId: record.document.snapshotId),
                title: "快照原文",
                mimeType: "application/json",
                description: "读取当前 snapshot 的完整 JSON。"
            ),
            MCPResourceLink(
                uri: LookinResourceURI.screenshot(snapshotId: record.document.snapshotId),
                title: "快照截图",
                mimeType: "application/json",
                description: "读取当前 snapshot 的截图元数据与本地文件路径。"
            ),
        ]
    }

    private func surfaceNodeSummary(from node: SnapshotNode) -> SurfaceNodeSummary {
        SurfaceNodeSummary(
            nodeId: node.nodeId,
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

    private func parseIncludes(_ value: JSONValue?) -> [SurfaceInclude] {
        guard case .array(let items)? = value else {
            return []
        }
        var includes: [SurfaceInclude] = []
        for item in items {
            guard let raw = item.stringValue,
                  let include = SurfaceInclude(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()),
                  !includes.contains(include) else {
                continue
            }
            includes.append(include)
        }
        return includes
    }

    private func shouldInclude(_ include: SurfaceInclude, in includes: [SurfaceInclude], detail: SurfaceDetail) -> Bool {
        if includes.contains(include) {
            return true
        }

        switch detail {
        case .compact:
            return include == .layout
        case .standard:
            return include == .layout || include == .relations
        case .full:
            return true
        }
    }

    private func toolDescriptor(
        name: String,
        description: String,
        properties: [String: JSONValue],
        required: [String] = []
    ) -> JSONValue {
        var schema: [String: JSONValue] = [
            "type": .string("object"),
            "properties": .object(properties),
            "additionalProperties": .bool(false),
        ]
        if !required.isEmpty {
            schema["required"] = .arrayOfStrings(required)
        }

        return .object([
            "name": .string(name),
            "description": .string(description),
            "inputSchema": .object(schema),
        ])
    }

    private func resourceDescriptor(uri: String, name: String, description: String, mimeType: String) -> JSONValue {
        .object([
            "uri": .string(uri),
            "name": .string(name),
            "description": .string(description),
            "mimeType": .string(mimeType),
        ])
    }

    private func stringSchema(description: String) -> JSONValue {
        .object([
            "type": .string("string"),
            "description": .string(description),
        ])
    }

    private func numberSchema(description: String) -> JSONValue {
        .object([
            "type": .string("number"),
            "description": .string(description),
        ])
    }

    private func enumSchema(values: [String], description: String) -> JSONValue {
        .object([
            "type": .string("string"),
            "enum": .arrayOfStrings(values),
            "description": .string(description),
        ])
    }

    private func includeSchema() -> JSONValue {
        .object([
            "type": .string("array"),
            "description": .string("可选，显式要求返回 layout/style/relations/children 这些附加字段。"),
            "items": .object([
                "type": .string("string"),
                "enum": .arrayOfStrings(SurfaceInclude.allCases.map(\.rawValue)),
            ]),
        ])
    }

    private func promptText(for name: String, snapshotID: String, nodeID: String, focus: String) -> String {
        switch name {
        case "analyze-node-layout":
            return """
            你正在分析 Lookin 导出的 iOS UI 布局。
            目标 snapshot: \(snapshotID)
            目标 node_id: \(nodeID)
            关注点: \(focus)

            请按以下步骤执行：
            1. 调用 `lookin.inspect`，传入 `node_id=\(nodeID)`、`detail=standard`、`include=[\"layout\",\"relations\",\"children\"]`
            2. 读取 inspect 返回的 subtree resource 与 capture resource
            3. 结合 frame、constraints、parent insets、siblings gap 判断布局是否异常
            4. 输出结论时明确列出证据、可能原因和建议修复方向
            """
        case "analyze-node-visual-style":
            return """
            你正在分析 Lookin 导出的 iOS UI 视觉样式。
            目标 snapshot: \(snapshotID)
            目标 node_id: \(nodeID)
            关注点: \(focus)

            请按以下步骤执行：
            1. 调用 `lookin.inspect`，传入 `node_id=\(nodeID)`、`detail=standard`、`include=[\"style\"]`
            2. 调用 `lookin.capture` 获取局部裁图
            3. 对照 visual evidence 与截图，检查颜色、圆角、边框、阴影、透明度是否一致
            4. 输出时区分“证据确认的问题”和“需要人工复核的猜测”
            """
        case "diagnose-spacing-and-alignment":
            return """
            你正在诊断 Lookin 导出的 iOS UI 间距与对齐问题。
            目标 snapshot: \(snapshotID)
            目标 node_id: \(nodeID)
            关注点: \(focus)

            请按以下步骤执行：
            1. 调用 `lookin.inspect`，传入 `node_id=\(nodeID)`、`detail=full`、`include=[\"relations\",\"children\"]`
            2. 读取 inspect 返回的 subtree resource，必要时调用 `lookin.find` 查找同一 VC 中的相关节点
            3. 基于 siblings gap、center delta、parent inset 与 subtree 层级判断是否存在对齐或间距异常
            4. 输出时给出异常位置、证据值和优先级排序
            """
        default:
            return ""
        }
    }

    private func optionalStringValue(_ value: String?) -> JSONValue? {
        guard let value, !value.isEmpty else {
            return nil
        }
        return .string(value)
    }
}
