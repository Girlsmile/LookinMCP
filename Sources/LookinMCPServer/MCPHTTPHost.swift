import Foundation
import Network

private struct HTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data
}

private struct HTTPResponse {
    let statusCode: Int
    let statusText: String
    let contentType: String
    let body: Data

    func serialized() -> Data {
        var header = "HTTP/1.1 \(statusCode) \(statusText)\r\n"
        header += "Content-Type: \(contentType)\r\n"
        header += "Content-Length: \(body.count)\r\n"
        header += "Connection: close\r\n\r\n"
        return Data(header.utf8) + body
    }
}

final class MCPHostRuntime: @unchecked Sendable {
    private let lock = NSLock()

    private(set) var startedAt: Date?
    private(set) var lastRequestAt: Date?
    private(set) var lastError: String?

    func markStarted(at date: Date = Date()) {
        lock.lock()
        startedAt = date
        lastError = nil
        lock.unlock()
    }

    func markRequestSuccess(at date: Date = Date()) {
        lock.lock()
        lastRequestAt = date
        lock.unlock()
    }

    func markError(_ text: String?) {
        lock.lock()
        lastError = text
        lock.unlock()
    }

    func statusSnapshot() -> (startedAt: Date?, lastRequestAt: Date?, lastError: String?) {
        lock.lock()
        defer { lock.unlock() }
        return (startedAt, lastRequestAt, lastError)
    }
}

final class MCPHTTPHost: @unchecked Sendable {
    let host: String
    let port: UInt16

    private let handler: MCPRequestHandler
    private let runtime: MCPHostRuntime
    private let queue: DispatchQueue
    private let encoder = JSONEncoder.lookinJSONEncoder()
    private let decoder = JSONDecoder()
    private var listener: NWListener?
    private let startSemaphore = DispatchSemaphore(value: 0)
    private var startError: Error?
    private var started = false

    init(
        host: String = lookinMCPDefaultHost,
        port: UInt16 = lookinMCPDefaultPort,
        handler: MCPRequestHandler = MCPRequestHandler(),
        runtime: MCPHostRuntime = MCPHostRuntime()
    ) {
        self.host = host
        self.port = port
        self.handler = handler
        self.runtime = runtime
        self.queue = DispatchQueue(label: "lookin.mcp.http.\(port)")
    }

    func start() throws {
        guard !started else { return }

        let tcpPort = NWEndpoint.Port(rawValue: port)
        guard let tcpPort else {
            throw MCPServerError.invalidArguments("INVALID_ARGUMENTS: 非法端口 \(port)。")
        }

        do {
            let listener = try NWListener(using: .tcp, on: tcpPort)
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.runtime.markStarted()
                    self.started = true
                    self.startSemaphore.signal()
                case .failed(let error):
                    self.startError = MCPServerError.portUnavailable(self.port, error.localizedDescription)
                    self.runtime.markError(error.localizedDescription)
                    self.startSemaphore.signal()
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }
            self.listener = listener
            listener.start(queue: queue)
            startSemaphore.wait()

            if let startError {
                throw startError
            }
        } catch let error as MCPServerError {
            throw error
        } catch {
            throw MCPServerError.portUnavailable(port, error.localizedDescription)
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        started = false
    }

    func run() throws {
        try start()
        RunLoop.main.run()
    }

    func currentStatus(now: Date = Date()) -> MCPHostStatus {
        let runtimeStatus = runtime.statusSnapshot()
        let snapshot = handler.snapshotStatus(now: now)
        let connectedRecently = runtimeStatus.lastRequestAt.map { now.timeIntervalSince($0) <= lookinMCPRecentRequestWindow } ?? false

        let state: String
        if let snapshot, !snapshot.isStale, connectedRecently {
            state = "connected"
        } else if let snapshot {
            state = snapshot.isStale ? "stale" : "ready"
        } else {
            state = "stale"
        }

        return MCPHostStatus(
            state: state,
            address: "http://\(host):\(port)/mcp",
            port: port,
            startedAt: runtimeStatus.startedAt?.lookinISO8601String,
            lastRequestAt: runtimeStatus.lastRequestAt?.lookinISO8601String,
            lastError: runtimeStatus.lastError,
            snapshotRoot: handler.snapshotRootPath(),
            snapshotAvailable: snapshot != nil,
            snapshotID: snapshot?.snapshotID,
            capturedAt: snapshot?.capturedAt,
            snapshotIsStale: snapshot?.isStale ?? true
        )
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            var nextBuffer = buffer
            if let data, !data.isEmpty {
                nextBuffer.append(data)
            }

            if let request = self.parseRequest(from: nextBuffer) {
                let response = self.handleRequest(request)
                connection.send(content: response.serialized(), completion: .contentProcessed { _ in
                    connection.cancel()
                })
                return
            }

            if let error {
                self.runtime.markError(error.localizedDescription)
                connection.cancel()
                return
            }

            if isComplete {
                let response = self.makeTextResponse(statusCode: 400, statusText: "Bad Request", text: "invalid request")
                connection.send(content: response.serialized(), completion: .contentProcessed { _ in
                    connection.cancel()
                })
                return
            }

            self.receive(on: connection, buffer: nextBuffer)
        }
    }

    private func parseRequest(from data: Data) -> HTTPRequest? {
        let separator = Data("\r\n\r\n".utf8)
        guard let range = data.range(of: separator),
              let headerText = String(data: data.subdata(in: data.startIndex..<range.lowerBound), encoding: .utf8) else {
            return nil
        }

        let bodyStart = range.upperBound
        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let requestParts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard requestParts.count >= 2 else { return nil }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            headers[String(parts[0]).lowercased()] = String(parts[1]).trimmingCharacters(in: .whitespaces)
        }

        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        let remaining = data.distance(from: bodyStart, to: data.endIndex)
        guard remaining >= contentLength else { return nil }

        let body = data.subdata(in: bodyStart..<(bodyStart + contentLength))
        return HTTPRequest(
            method: String(requestParts[0]),
            path: String(requestParts[1]),
            headers: headers,
            body: body
        )
    }

    private func handleRequest(_ request: HTTPRequest) -> HTTPResponse {
        switch (request.method, request.path) {
        case ("GET", "/status"):
            return makeJSONResponse(statusCode: 200, statusText: "OK", value: currentStatus())
        case ("POST", "/mcp"):
            do {
                let message = try decoder.decode(JSONRPCMessage.self, from: request.body)
                guard let responseMessage = try handler.handle(message: message) else {
                    return HTTPResponse(statusCode: 202, statusText: "Accepted", contentType: "application/json", body: Data("{}".utf8))
                }
                runtime.markRequestSuccess()
                return makeJSONResponse(statusCode: 200, statusText: "OK", value: responseMessage)
            } catch {
                runtime.markError(error.localizedDescription)
                let payload = JSONRPCMessage(
                    jsonrpc: "2.0",
                    id: nil,
                    method: nil,
                    params: nil,
                    result: nil,
                    error: RPCError(code: -32000, message: error.localizedDescription)
                )
                return makeJSONResponse(statusCode: 200, statusText: "OK", value: payload)
            }
        case ("GET", "/healthz"):
            return makeTextResponse(statusCode: 200, statusText: "OK", text: "ok")
        case ("POST", _):
            return makeTextResponse(statusCode: 404, statusText: "Not Found", text: "not found")
        default:
            return makeTextResponse(statusCode: 405, statusText: "Method Not Allowed", text: "method not allowed")
        }
    }

    private func makeJSONResponse<T: Encodable>(statusCode: Int, statusText: String, value: T) -> HTTPResponse {
        do {
            return HTTPResponse(
                statusCode: statusCode,
                statusText: statusText,
                contentType: "application/json",
                body: try encoder.encode(value)
            )
        } catch {
            return makeTextResponse(statusCode: 500, statusText: "Internal Server Error", text: error.localizedDescription)
        }
    }

    private func makeTextResponse(statusCode: Int, statusText: String, text: String) -> HTTPResponse {
        HTTPResponse(
            statusCode: statusCode,
            statusText: statusText,
            contentType: "text/plain; charset=utf-8",
            body: Data(text.utf8)
        )
    }
}
