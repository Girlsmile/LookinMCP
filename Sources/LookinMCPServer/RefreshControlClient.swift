import Foundation

enum RefreshWaitPhase: String, Codable {
    case hierarchy
    case details

    static func parse(_ value: String?) -> RefreshWaitPhase {
        guard let value,
              let phase = RefreshWaitPhase(rawValue: value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) else {
            return .details
        }
        return phase
    }
}

enum RefreshMode: String {
    case ids
    case brief

    static func parse(_ value: String?) -> RefreshMode {
        guard let value,
              let mode = RefreshMode(rawValue: value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) else {
            return .ids
        }
        return mode
    }
}

protocol RefreshControlling {
    func refresh(waitUntil: RefreshWaitPhase, timeoutMs: Int) throws -> RefreshControlResponse
}

struct RefreshControlRequest: Codable {
    let requestId: String
    let waitUntil: RefreshWaitPhase
    let timeoutMs: Int
    let createdAt: String
}

struct RefreshControlResponse: Codable {
    let requestId: String
    let ok: Bool
    let sid: String?
    let prevSid: String?
    let phase: String
    let changed: Bool
    let ms: Int
    let capturedAt: String?
    let app: String?
    let error: String?
}

struct RefreshToolResponse: Encodable {
    let ok: Bool
    let sid: String?
    let prevSid: String?
    let phase: String
    let changed: Bool
    let ms: Int
    let capturedAt: String?
    let app: String?
    let error: String?

    init(control: RefreshControlResponse, mode: RefreshMode) {
        ok = control.ok
        sid = control.sid
        prevSid = control.prevSid
        phase = control.phase
        changed = control.changed
        ms = control.ms
        error = control.error
        switch mode {
        case .ids:
            capturedAt = nil
            app = nil
        case .brief:
            capturedAt = control.capturedAt
            app = control.app
        }
    }
}

final class RefreshControlClient: RefreshControlling {
    private let rootURL: URL
    private let fileManager: FileManager

    init(snapshotRootPath: String, fileManager: FileManager = .default) {
        self.rootURL = URL(fileURLWithPath: snapshotRootPath, isDirectory: true)
        self.fileManager = fileManager
    }

    func refresh(waitUntil: RefreshWaitPhase, timeoutMs: Int) throws -> RefreshControlResponse {
        let clampedTimeoutMs = max(500, min(timeoutMs, 120_000))
        let request = RefreshControlRequest(
            requestId: UUID().uuidString,
            waitUntil: waitUntil,
            timeoutMs: clampedTimeoutMs,
            createdAt: Date().lookinISO8601String
        )

        let requestsURL = rootURL
            .appendingPathComponent("control", isDirectory: true)
            .appendingPathComponent("requests", isDirectory: true)
        let responsesURL = rootURL
            .appendingPathComponent("control", isDirectory: true)
            .appendingPathComponent("responses", isDirectory: true)
        try fileManager.createDirectory(at: requestsURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: responsesURL, withIntermediateDirectories: true)

        let requestURL = requestsURL.appendingPathComponent("\(request.requestId).json", isDirectory: false)
        let responseURL = responsesURL.appendingPathComponent("\(request.requestId).json", isDirectory: false)
        let encoder = JSONEncoder.lookinJSONEncoder()
        try encoder.encode(request).write(to: requestURL, options: [.atomic])

        let deadline = Date().addingTimeInterval(TimeInterval(clampedTimeoutMs) / 1000)
        while Date() < deadline {
            if fileManager.fileExists(atPath: responseURL.path) {
                let data = try Data(contentsOf: responseURL)
                let response = try JSONDecoder.lookinJSONDecoder().decode(RefreshControlResponse.self, from: data)
                try? fileManager.removeItem(at: responseURL)
                try? fileManager.removeItem(at: requestURL)
                return response
            }
            Thread.sleep(forTimeInterval: 0.05)
        }

        try? fileManager.removeItem(at: requestURL)
        throw MCPServerError.refreshUnavailable("REFRESH_TIMEOUT: 刷新未在 \(clampedTimeoutMs)ms 内完成。")
    }
}
