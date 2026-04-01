import Foundation

/// Lookin Desktop 首版固定监听 localhost，客户端应长期使用该地址重连。
let lookinMCPDefaultHost = "127.0.0.1"
let lookinMCPDefaultPort: UInt16 = 3846
let lookinMCPProtocolVersion = "2024-11-05"
let lookinMCPServerVersion = "0.3.0"
let lookinMCPRecentRequestWindow: TimeInterval = 30
let lookinMCPSnapshotStaleWindow: TimeInterval = 300

struct JSONRPCMessage: Codable {
    let jsonrpc: String
    let id: RPCID?
    let method: String?
    let params: JSONValue?
    let result: JSONValue?
    let error: RPCError?
}

enum RPCID: Codable, Hashable {
    case string(String)
    case int(Int)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            self = .int(intValue)
            return
        }
        self = .string(try container.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        }
    }
}

struct RPCError: Codable {
    let code: Int
    let message: String
}

struct MCPServerInfo: Encodable {
    let name: String
    let version: String
}

struct MCPSnapshotStatus: Encodable {
    let snapshotID: String
    let capturedAt: String
    let isStale: Bool
}

struct MCPHostStatus: Encodable {
    let state: String
    let address: String
    let port: UInt16
    let startedAt: String?
    let lastRequestAt: String?
    let lastError: String?
    let snapshotRoot: String
    let snapshotAvailable: Bool
    let snapshotID: String?
    let capturedAt: String?
    let snapshotIsStale: Bool
}

enum JSONValue: Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let boolValue = try? container.decode(Bool.self) {
            self = .bool(boolValue)
        } else if let numberValue = try? container.decode(Double.self) {
            self = .number(numberValue)
        } else if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else if let objectValue = try? container.decode([String: JSONValue].self) {
            self = .object(objectValue)
        } else {
            self = .array(try container.decode([JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

enum MCPServerError: LocalizedError {
    case invalidArguments(String)
    case noSnapshotAvailable
    case snapshotNotFound(String)
    case nodeNotFound(String)
    case screenshotUnavailable
    case cropFailed(String)
    case invalidSnapshot(String)
    case io(String)
    case invalidCommandLine(String)
    case portUnavailable(UInt16, String)

    var errorDescription: String? {
        switch self {
        case .invalidArguments(let message), .invalidSnapshot(let message), .io(let message), .cropFailed(let message), .invalidCommandLine(let message):
            return message
        case .portUnavailable(let port, let detail):
            return "PORT_UNAVAILABLE: localhost:\(port) 无法启动。\(detail)"
        case .noSnapshotAvailable:
            return "NO_SNAPSHOT_AVAILABLE: 未找到可读取的 snapshot.json。"
        case .snapshotNotFound(let snapshotID):
            return "SNAPSHOT_NOT_FOUND: 未找到 snapshot_id=\(snapshotID) 对应的本地快照。"
        case .nodeNotFound(let nodeID):
            return "NODE_NOT_FOUND: 未找到 node_id=\(nodeID) 对应的节点。"
        case .screenshotUnavailable:
            return "SCREENSHOT_UNAVAILABLE: 当前 snapshot 不包含可读取的 screenshot.png。"
        }
    }
}

extension JSONValue {
    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    var boolValue: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }

    var intValue: Int? {
        guard case .number(let value) = self else { return nil }
        return Int(value)
    }

    var numberValue: Double? {
        guard case .number(let value) = self else { return nil }
        return value
    }

    var objectValue: [String: JSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    var foundationValue: Any {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            return value
        case .bool(let value):
            return value
        case .object(let value):
            return value.mapValues { $0.foundationValue }
        case .array(let value):
            return value.map { $0.foundationValue }
        case .null:
            return NSNull()
        }
    }
}

extension JSONValue {
    static func stringObject(_ values: [String: String]) -> JSONValue {
        .object(values.mapValues(JSONValue.string))
    }
}

extension Encodable {
    /// 将 Encodable 转成适合 MCP 文本响应的 JSON 字符串。
    func prettyJSONString() throws -> String {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(AnyEncodable(self))
        return String(decoding: data, as: UTF8.self)
    }
}

extension JSONEncoder {
    static func lookinJSONEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}

extension Date {
    var lookinISO8601String: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: self)
    }
}

func parseLookinDate(_ text: String) -> Date? {
    let primary = ISO8601DateFormatter()
    primary.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = primary.date(from: text) {
        return date
    }

    let fallback = ISO8601DateFormatter()
    fallback.formatOptions = [.withInternetDateTime]
    return fallback.date(from: text)
}

private struct AnyEncodable: Encodable {
    private let encodeBlock: (Encoder) throws -> Void

    init(_ wrapped: Encodable) {
        self.encodeBlock = wrapped.encode
    }

    func encode(to encoder: Encoder) throws {
        try encodeBlock(encoder)
    }
}
