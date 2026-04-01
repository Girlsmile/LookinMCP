import Foundation

final class MCPRequestHandler {
    private let store: LocalSnapshotStore

    init(store: LocalSnapshotStore = LocalSnapshotStore()) {
        self.store = store
    }

    func handle(message: JSONRPCMessage) throws -> JSONRPCMessage? {
        switch message.method {
        case "initialize":
            return JSONRPCMessage(
                jsonrpc: "2.0",
                id: message.id,
                method: nil,
                params: nil,
                result: .object([
                    "protocolVersion": .string(lookinMCPProtocolVersion),
                    "capabilities": .object([
                        "tools": .object([:])
                    ]),
                    "serverInfo": .object([
                        "name": .string("lookin-mcp"),
                        "version": .string(lookinMCPServerVersion)
                    ])
                ]),
                error: nil
            )
        case "notifications/initialized":
            return nil
        case "tools/list":
            return toolListResponse(id: message.id)
        case "tools/call":
            return try handleToolCall(message: message)
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

    private func toolListResponse(id: RPCID?) -> JSONRPCMessage {
        JSONRPCMessage(
            jsonrpc: "2.0",
            id: id,
            method: nil,
            params: nil,
            result: .object([
                "tools": .array([
                    .object([
                        "name": .string("lookin.list_snapshots"),
                        "description": .string("列出本地可读取的 current 与 history snapshot。"),
                        "inputSchema": .object([
                            "type": .string("object"),
                            "properties": .object([:]),
                            "additionalProperties": .bool(false)
                        ])
                    ]),
                    .object([
                        "name": .string("lookin.find_nodes"),
                        "description": .string("按 vc、ivar、class 或 text 在本地 snapshot 中定位候选节点。"),
                        "inputSchema": .object([
                            "type": .string("object"),
                            "properties": .object([
                                "snapshot_id": .object(["type": .string("string")]),
                                "vc_name": .object(["type": .string("string")]),
                                "ivar_name": .object(["type": .string("string")]),
                                "class_name": .object(["type": .string("string")]),
                                "text": .object(["type": .string("string")]),
                                "max_matches": .object(["type": .string("number")])
                            ]),
                            "additionalProperties": .bool(false)
                        ])
                    ]),
                    .object([
                        "name": .string("lookin.get_latest_snapshot"),
                        "description": .string("读取最新的本地 snapshot，返回完整结构化内容。"),
                        "inputSchema": .object([
                            "type": .string("object"),
                            "properties": .object([:]),
                            "additionalProperties": .bool(false)
                        ])
                    ]),
                    .object([
                        "name": .string("lookin.get_node_details"),
                        "description": .string("按 node_id 读取单个节点的完整证据、父节点和直接子节点。"),
                        "inputSchema": .object([
                            "type": .string("object"),
                            "properties": .object([
                                "snapshot_id": .object(["type": .string("string")]),
                                "node_id": .object(["type": .string("string")])
                            ]),
                            "required": .array([.string("node_id")]),
                            "additionalProperties": .bool(false)
                        ])
                    ]),
                    .object([
                        "name": .string("lookin.get_node_relations"),
                        "description": .string("按 node_id 返回父子兄弟关系，以及相对间距和对齐信息。"),
                        "inputSchema": .object([
                            "type": .string("object"),
                            "properties": .object([
                                "snapshot_id": .object(["type": .string("string")]),
                                "node_id": .object(["type": .string("string")])
                            ]),
                            "required": .array([.string("node_id")]),
                            "additionalProperties": .bool(false)
                        ])
                    ]),
                    .object([
                        "name": .string("lookin.get_subtree"),
                        "description": .string("按 node_id 展开局部子树，返回层级化节点列表。"),
                        "inputSchema": .object([
                            "type": .string("object"),
                            "properties": .object([
                                "snapshot_id": .object(["type": .string("string")]),
                                "node_id": .object(["type": .string("string")]),
                                "max_depth": .object(["type": .string("number")]),
                                "max_nodes": .object(["type": .string("number")])
                            ]),
                            "required": .array([.string("node_id")]),
                            "additionalProperties": .bool(false)
                        ])
                    ]),
                    .object([
                        "name": .string("lookin.crop_screenshot"),
                        "description": .string("按 node_id 从 screenshot.png 裁出局部图片并返回输出路径。"),
                        "inputSchema": .object([
                            "type": .string("object"),
                            "properties": .object([
                                "snapshot_id": .object(["type": .string("string")]),
                                "node_id": .object(["type": .string("string")]),
                                "padding": .object(["type": .string("number")])
                            ]),
                            "required": .array([.string("node_id")]),
                            "additionalProperties": .bool(false)
                        ])
                    ]),
                    .object([
                        "name": .string("lookin.query_snapshot"),
                        "description": .string("按 vc、ivar、class 或 text 对本地 snapshot 执行确定性查询。"),
                        "inputSchema": .object([
                            "type": .string("object"),
                            "properties": .object([
                                "snapshot_id": .object(["type": .string("string")]),
                                "vc_name": .object(["type": .string("string")]),
                                "ivar_name": .object(["type": .string("string")]),
                                "class_name": .object(["type": .string("string")]),
                                "text": .object(["type": .string("string")]),
                                "max_matches": .object(["type": .string("number")]),
                                "include_tree": .object(["type": .string("boolean")])
                            ]),
                            "additionalProperties": .bool(false)
                        ])
                    ])
                ])
            ]),
            error: nil
        )
    }

    private func handleToolCall(message: JSONRPCMessage) throws -> JSONRPCMessage {
        guard case .object(let params)? = message.params,
              case .string(let toolName)? = params["name"] else {
            throw MCPServerError.invalidArguments("Invalid tool call")
        }

        let arguments = params["arguments"]?.objectValue ?? [:]

        let payloadText: String
        do {
            switch toolName {
            case "lookin.list_snapshots":
                struct Payload: Encodable {
                    let snapshotRoot: String
                    let snapshots: [SnapshotSummary]
                }
                payloadText = try Payload(
                    snapshotRoot: store.snapshotRootPath(),
                    snapshots: store.listSnapshots()
                ).prettyJSONString()

            case "lookin.find_nodes":
                let query = SnapshotQuery(
                    snapshotId: arguments["snapshot_id"]?.stringValue,
                    vcName: arguments["vc_name"]?.stringValue,
                    ivarName: arguments["ivar_name"]?.stringValue,
                    className: arguments["class_name"]?.stringValue,
                    text: arguments["text"]?.stringValue,
                    maxMatches: max(1, min(arguments["max_matches"]?.intValue ?? 10, 50)),
                    includeTree: false
                )
                payloadText = try store.findNodes(query).prettyJSONString()

            case "lookin.get_latest_snapshot":
                let record = try store.latestSnapshot()
                struct Payload: Encodable {
                    let snapshotRoot: String
                    let snapshotDirectory: String
                    let snapshotFile: String
                    let isCurrent: Bool
                    let snapshot: SnapshotDocument
                }
                payloadText = try Payload(
                    snapshotRoot: store.snapshotRootPath(),
                    snapshotDirectory: record.directoryURL.path,
                    snapshotFile: record.snapshotURL.path,
                    isCurrent: record.isCurrent,
                    snapshot: record.document
                ).prettyJSONString()

            case "lookin.get_node_details":
                guard let nodeId = arguments["node_id"]?.stringValue,
                      !nodeId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw MCPServerError.invalidArguments("INVALID_ARGUMENTS: `node_id` 不能为空。")
                }
                payloadText = try store.nodeDetails(
                    snapshotId: arguments["snapshot_id"]?.stringValue,
                    nodeId: nodeId
                ).prettyJSONString()

            case "lookin.get_node_relations":
                guard let nodeId = arguments["node_id"]?.stringValue,
                      !nodeId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw MCPServerError.invalidArguments("INVALID_ARGUMENTS: `node_id` 不能为空。")
                }
                payloadText = try store.nodeRelations(
                    snapshotId: arguments["snapshot_id"]?.stringValue,
                    nodeId: nodeId
                ).prettyJSONString()

            case "lookin.get_subtree":
                guard let nodeId = arguments["node_id"]?.stringValue,
                      !nodeId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw MCPServerError.invalidArguments("INVALID_ARGUMENTS: `node_id` 不能为空。")
                }
                payloadText = try store.subtree(
                    snapshotId: arguments["snapshot_id"]?.stringValue,
                    nodeId: nodeId,
                    maxDepth: max(0, min(arguments["max_depth"]?.intValue ?? 2, 8)),
                    maxNodes: max(1, min(arguments["max_nodes"]?.intValue ?? 80, 500))
                ).prettyJSONString()

            case "lookin.crop_screenshot":
                guard let nodeId = arguments["node_id"]?.stringValue,
                      !nodeId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw MCPServerError.invalidArguments("INVALID_ARGUMENTS: `node_id` 不能为空。")
                }
                let padding = min(max(arguments["padding"]?.numberValue ?? 0, 0), 200)
                payloadText = try store.cropScreenshot(
                    snapshotId: arguments["snapshot_id"]?.stringValue,
                    nodeId: nodeId,
                    padding: padding
                ).prettyJSONString()

            case "lookin.query_snapshot":
                let query = SnapshotQuery(
                    snapshotId: arguments["snapshot_id"]?.stringValue,
                    vcName: arguments["vc_name"]?.stringValue,
                    ivarName: arguments["ivar_name"]?.stringValue,
                    className: arguments["class_name"]?.stringValue,
                    text: arguments["text"]?.stringValue,
                    maxMatches: max(1, min(arguments["max_matches"]?.intValue ?? 10, 20)),
                    includeTree: arguments["include_tree"]?.boolValue ?? true
                )
                payloadText = try store.query(query).prettyJSONString()

            default:
                throw MCPServerError.invalidArguments("Unknown tool")
            }

            return JSONRPCMessage(
                jsonrpc: "2.0",
                id: message.id,
                method: nil,
                params: nil,
                result: .object([
                    "content": .array([
                        .object([
                            "type": .string("text"),
                            "text": .string(payloadText)
                        ])
                    ])
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
}
