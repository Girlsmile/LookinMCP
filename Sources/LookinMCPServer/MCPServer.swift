import Foundation

final class MCPServer {
    private let handler: MCPRequestHandler
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(handler: MCPRequestHandler = MCPRequestHandler()) {
        self.handler = handler
    }

    /// 按 MCP stdio framing 持续读取请求并写回响应。
    func run() throws {
        let stdin = FileHandle.standardInput
        while let data = try readMessage(from: stdin) {
            let message = try decoder.decode(JSONRPCMessage.self, from: data)
            if let response = try handler.handle(message: message) {
                try writeMessage(response)
            }
        }
    }

    private func readMessage(from handle: FileHandle) throws -> Data? {
        var headerData = Data()
        while true {
            let chunk = try handle.read(upToCount: 1) ?? Data()
            if chunk.isEmpty {
                return nil
            }
            headerData.append(chunk)
            if headerData.suffix(4) == Data("\r\n\r\n".utf8) {
                break
            }
        }

        guard let headerString = String(data: headerData, encoding: .utf8) else {
            throw MCPServerError.invalidArguments("Invalid header encoding")
        }

        let contentLength = headerString
            .split(separator: "\r\n")
            .compactMap { line -> Int? in
                let parts = line
                    .split(separator: ":", maxSplits: 1)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                guard parts.count == 2, parts[0].lowercased() == "content-length" else {
                    return nil
                }
                return Int(parts[1])
            }
            .first

        guard let contentLength else {
            throw MCPServerError.invalidArguments("Missing Content-Length header")
        }

        var body = Data()
        while body.count < contentLength {
            let chunk = try handle.read(upToCount: contentLength - body.count) ?? Data()
            if chunk.isEmpty {
                throw MCPServerError.invalidArguments("Unexpected EOF")
            }
            body.append(chunk)
        }
        return body
    }

    private func writeMessage(_ message: JSONRPCMessage) throws {
        let data = try encoder.encode(message)
        var output = Data("Content-Length: \(data.count)\r\n\r\n".utf8)
        output.append(data)
        try FileHandle.standardOutput.write(contentsOf: output)
    }
}
