import Foundation

enum MCPTransportMode {
    case stdio
    case http(host: String, port: UInt16)
}

private func resolveTransport(arguments: [String]) throws -> MCPTransportMode {
    var transport = "stdio"
    var host = lookinMCPDefaultHost
    var port = lookinMCPDefaultPort

    var index = 0
    while index < arguments.count {
        let arg = arguments[index]
        switch arg {
        case "--transport":
            index += 1
            guard index < arguments.count else {
                throw MCPServerError.invalidCommandLine("INVALID_ARGUMENTS: `--transport` 缺少参数。")
            }
            transport = arguments[index]
        case "--host":
            index += 1
            guard index < arguments.count else {
                throw MCPServerError.invalidCommandLine("INVALID_ARGUMENTS: `--host` 缺少参数。")
            }
            host = arguments[index]
        case "--port":
            index += 1
            guard index < arguments.count, let value = UInt16(arguments[index]) else {
                throw MCPServerError.invalidCommandLine("INVALID_ARGUMENTS: `--port` 需要合法端口。")
            }
            port = value
        default:
            throw MCPServerError.invalidCommandLine("INVALID_ARGUMENTS: 不支持的参数 `\(arg)`。")
        }
        index += 1
    }

    switch transport {
    case "stdio":
        return .stdio
    case "http":
        return .http(host: host, port: port)
    default:
        throw MCPServerError.invalidCommandLine("INVALID_ARGUMENTS: `--transport` 仅支持 `stdio` 或 `http`。")
    }
}

do {
    switch try resolveTransport(arguments: Array(CommandLine.arguments.dropFirst())) {
    case .stdio:
        try MCPServer().run()
    case .http(let host, let port):
        try MCPHTTPHost(host: host, port: port).run()
    }
} catch {
    fputs("lookin-mcp fatal error: \(error.localizedDescription)\n", stderr)
    exit(EXIT_FAILURE)
}
