import Foundation
import AppKit
import XCTest
import Darwin

private final class HTTPResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Result<[String: Any], Error>?

    func set(_ value: Result<[String: Any], Error>) {
        lock.lock()
        storage = value
        lock.unlock()
    }

    func get() -> Result<[String: Any], Error>? {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

final class LookinMCPServerTests: XCTestCase {
    func testInitializeReturnsServerInfo() throws {
        let response = try invokeServer(
            with: [
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
            ],
            snapshotRoot: makeTemporaryDirectory()
        )

        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let serverInfo = try XCTUnwrap(result["serverInfo"] as? [String: Any])
        XCTAssertEqual(serverInfo["name"] as? String, "lookin-mcp")
        XCTAssertEqual(serverInfo["version"] as? String, "0.3.0")
    }

    func testToolsListContainsLocalSnapshotTools() throws {
        let response = try invokeServer(
            with: [
                "jsonrpc": "2.0",
                "id": 1,
                "method": "tools/list",
            ],
            snapshotRoot: makeTemporaryDirectory()
        )

        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let tools = try XCTUnwrap(result["tools"] as? [[String: Any]])
        let toolNames = Set(tools.compactMap { $0["name"] as? String })

        XCTAssertEqual(toolNames, [
            "lookin.find_nodes",
            "lookin.list_snapshots",
            "lookin.get_latest_snapshot",
            "lookin.get_node_details",
            "lookin.get_node_relations",
            "lookin.get_subtree",
            "lookin.crop_screenshot",
            "lookin.query_snapshot",
        ])
    }

    func testGetLatestSnapshotReturnsNoSnapshotErrorWhenEmpty() throws {
        let response = try invokeServer(
            with: [
                "jsonrpc": "2.0",
                "id": 1,
                "method": "tools/call",
                "params": [
                    "name": "lookin.get_latest_snapshot",
                    "arguments": [:],
                ],
            ],
            snapshotRoot: makeTemporaryDirectory()
        )

        let error = try XCTUnwrap(response["error"] as? [String: Any])
        XCTAssertEqual(error["message"] as? String, "NO_SNAPSHOT_AVAILABLE: 未找到可读取的 snapshot.json。")
    }

    func testListSnapshotsReturnsCurrentAndHistoryEntries() throws {
        let root = try makeSnapshotRoot()
        try writeSnapshot(
            at: root.appendingPathComponent("current/snapshot.json"),
            snapshotID: "20260401T100000Z",
            capturedAt: "2026-04-01T10:00:00Z",
            appName: "Demo",
            bundleID: "com.demo.app",
            nodes: [sampleNode(nodeID: "oid:1", title: "UIWindow", className: "UIWindow")]
        )
        try writeSnapshot(
            at: root.appendingPathComponent("history/20260331T120000Z/snapshot.json"),
            snapshotID: "20260331T120000Z",
            capturedAt: "2026-03-31T12:00:00Z",
            appName: "OldDemo",
            bundleID: "com.demo.old",
            nodes: [sampleNode(nodeID: "oid:2", title: "UIView", className: "UIView")]
        )

        let response = try invokeServer(
            with: [
                "jsonrpc": "2.0",
                "id": 1,
                "method": "tools/call",
                "params": [
                    "name": "lookin.list_snapshots",
                    "arguments": [:],
                ],
            ],
            snapshotRoot: root
        )

        let payload = try parseToolPayload(response)
        let snapshots = try XCTUnwrap(payload["snapshots"] as? [[String: Any]])
        XCTAssertEqual(snapshots.count, 2)
        XCTAssertEqual(snapshots.first?["snapshot_id"] as? String, "20260401T100000Z")
        XCTAssertEqual(snapshots.first?["is_current"] as? Bool, true)
    }

    func testQuerySnapshotFiltersByVCAndIvar() throws {
        let root = try makeSnapshotRoot()
        try writeSnapshot(
            at: root.appendingPathComponent("current/snapshot.json"),
            snapshotID: "20260401T110000Z",
            capturedAt: "2026-04-01T11:00:00Z",
            appName: "Demo",
            bundleID: "com.demo.app",
            nodes: [
                sampleNode(nodeID: "oid:1", title: "UIWindow", className: "UIWindow", hostViewControllerName: "HomeViewController", childIDs: ["oid:2"], indentLevel: 0),
                sampleNode(nodeID: "oid:2", title: "UILabel", className: "UILabel", hostViewControllerName: "HomeViewController", ivarNames: ["titleLabel"], textValues: ["Hello Lookin"], childIDs: [], parentID: "oid:1", indentLevel: 1)
            ]
        )

        let response = try invokeServer(
            with: [
                "jsonrpc": "2.0",
                "id": 1,
                "method": "tools/call",
                "params": [
                    "name": "lookin.query_snapshot",
                    "arguments": [
                        "vc_name": "HomeViewController",
                        "ivar_name": "titleLabel",
                        "include_tree": true,
                    ],
                ],
            ],
            snapshotRoot: root
        )

        let payload = try parseToolPayload(response)
        XCTAssertEqual(payload["match_count"] as? Int, 1)

        let matches = try XCTUnwrap(payload["matches"] as? [[String: Any]])
        XCTAssertEqual(matches.first?["class_name"] as? String, "UILabel")
        XCTAssertEqual(matches.first?["host_view_controller_name"] as? String, "HomeViewController")
        let visualEvidence = try XCTUnwrap(matches.first?["visual_evidence"] as? [String: Any])
        XCTAssertEqual(visualEvidence["masks_to_bounds"] as? Bool, false)
        let backgroundColor = try XCTUnwrap(visualEvidence["background_color"] as? [String: Any])
        XCTAssertEqual(backgroundColor["hex_string"] as? String, "#ff0000")

        let treeExcerpt = try XCTUnwrap(payload["tree_excerpt"] as? [String])
        XCTAssertTrue(treeExcerpt.contains(where: { $0.contains("UILabel") }))
    }

    func testFindNodesReturnsMatchedByReasons() throws {
        let root = try makeSnapshotRoot()
        try writeSnapshot(
            at: root.appendingPathComponent("current/snapshot.json"),
            snapshotID: "20260401T120000Z",
            capturedAt: "2026-04-01T12:00:00Z",
            appName: "Demo",
            bundleID: "com.demo.app",
            nodes: [
                sampleNode(
                    nodeID: "oid:1",
                    title: "UIView",
                    className: "UIView",
                    hostViewControllerName: "HomeViewController",
                    ivarNames: ["topBar"],
                    childIDs: ["oid:2"],
                    indentLevel: 0,
                    frame: rect(x: 10, y: 20, width: 180, height: 40)
                ),
                sampleNode(
                    nodeID: "oid:2",
                    title: "UIButton",
                    className: "UIButton",
                    hostViewControllerName: "HomeViewController",
                    ivarNames: ["backButton"],
                    parentID: "oid:1",
                    indentLevel: 1,
                    frame: rect(x: 26, y: 24, width: 32, height: 32)
                )
            ]
        )

        let response = try invokeServer(
            with: [
                "jsonrpc": "2.0",
                "id": 1,
                "method": "tools/call",
                "params": [
                    "name": "lookin.find_nodes",
                    "arguments": [
                        "vc_name": "HomeViewController",
                        "ivar_name": "topBar",
                    ],
                ],
            ],
            snapshotRoot: root
        )

        let payload = try parseToolPayload(response)
        XCTAssertEqual(payload["match_count"] as? Int, 1)
        let nodes = try XCTUnwrap(payload["nodes"] as? [[String: Any]])
        XCTAssertEqual(nodes.first?["node_id"] as? String, "oid:1")
        XCTAssertEqual(nodes.first?["class_name"] as? String, "UIView")
        XCTAssertEqual(Set(try XCTUnwrap(nodes.first?["matched_by"] as? [String])), ["vc_name", "ivar_name"])
    }

    func testGetNodeDetailsReturnsParentAndChildren() throws {
        let root = try makeSnapshotRoot()
        try writeSnapshot(
            at: root.appendingPathComponent("current/snapshot.json"),
            snapshotID: "20260401T121000Z",
            capturedAt: "2026-04-01T12:10:00Z",
            appName: "Demo",
            bundleID: "com.demo.app",
            nodes: makeRelationFixtureNodes()
        )

        let response = try invokeServer(
            with: [
                "jsonrpc": "2.0",
                "id": 1,
                "method": "tools/call",
                "params": [
                    "name": "lookin.get_node_details",
                    "arguments": [
                        "node_id": "oid:2",
                    ],
                ],
            ],
            snapshotRoot: root
        )

        let payload = try parseToolPayload(response)
        let node = try XCTUnwrap(payload["node"] as? [String: Any])
        XCTAssertEqual(node["node_id"] as? String, "oid:2")
        XCTAssertEqual(node["class_name"] as? String, "UIView")

        let parent = try XCTUnwrap(payload["parent"] as? [String: Any])
        XCTAssertEqual(parent["node_id"] as? String, "oid:1")

        let children = try XCTUnwrap(payload["children"] as? [[String: Any]])
        XCTAssertEqual(children.count, 2)
        XCTAssertEqual(Set(children.compactMap { $0["node_id"] as? String }), ["oid:3", "oid:4"])
    }

    func testGetNodeRelationsReturnsInsetsAndSiblingMetrics() throws {
        let root = try makeSnapshotRoot()
        try writeSnapshot(
            at: root.appendingPathComponent("current/snapshot.json"),
            snapshotID: "20260401T122000Z",
            capturedAt: "2026-04-01T12:20:00Z",
            appName: "Demo",
            bundleID: "com.demo.app",
            nodes: makeRelationFixtureNodes()
        )

        let response = try invokeServer(
            with: [
                "jsonrpc": "2.0",
                "id": 1,
                "method": "tools/call",
                "params": [
                    "name": "lookin.get_node_relations",
                    "arguments": [
                        "node_id": "oid:3",
                    ],
                ],
            ],
            snapshotRoot: root
        )

        let payload = try parseToolPayload(response)
        let withinParentInsets = try XCTUnwrap(payload["within_parent_insets"] as? [String: Any])
        XCTAssertEqual(withinParentInsets["left"] as? Double, 16)
        XCTAssertEqual(withinParentInsets["top"] as? Double, 4)

        let parent = try XCTUnwrap(payload["parent"] as? [String: Any])
        let parentRelation = try XCTUnwrap(parent["relation"] as? [String: Any])
        XCTAssertEqual(parentRelation["relative_position"] as? String, "overlapping")

        let siblings = try XCTUnwrap(payload["siblings"] as? [[String: Any]])
        XCTAssertEqual(siblings.count, 1)
        let siblingNode = try XCTUnwrap(siblings.first?["node"] as? [String: Any])
        XCTAssertEqual(siblingNode["node_id"] as? String, "oid:4")
        let siblingRelation = try XCTUnwrap(siblings.first?["relation"] as? [String: Any])
        XCTAssertEqual(siblingRelation["relative_position"] as? String, "right")
        XCTAssertEqual(siblingRelation["horizontal_gap"] as? Double, 84)

        let children = try XCTUnwrap(payload["children"] as? [[String: Any]])
        XCTAssertEqual(children.count, 1)
        let childRelation = try XCTUnwrap(children.first?["relation"] as? [String: Any])
        XCTAssertEqual(childRelation["relative_position"] as? String, "overlapping")
    }

    func testGetSubtreeReturnsFlatHierarchy() throws {
        let root = try makeSnapshotRoot()
        try writeSnapshot(
            at: root.appendingPathComponent("current/snapshot.json"),
            snapshotID: "20260401T123000Z",
            capturedAt: "2026-04-01T12:30:00Z",
            appName: "Demo",
            bundleID: "com.demo.app",
            nodes: makeRelationFixtureNodes()
        )

        let response = try invokeServer(
            with: [
                "jsonrpc": "2.0",
                "id": 1,
                "method": "tools/call",
                "params": [
                    "name": "lookin.get_subtree",
                    "arguments": [
                        "node_id": "oid:2",
                        "max_depth": 2,
                    ],
                ],
            ],
            snapshotRoot: root
        )

        let payload = try parseToolPayload(response)
        XCTAssertEqual(payload["root_node_id"] as? String, "oid:2")
        XCTAssertEqual(payload["returned_node_count"] as? Int, 4)
        let nodes = try XCTUnwrap(payload["nodes"] as? [[String: Any]])
        XCTAssertEqual(nodes.first?["node_id"] as? String, "oid:2")
        XCTAssertEqual(nodes.first?["depth"] as? Int, 0)
        XCTAssertEqual(nodes.last?["node_id"] as? String, "oid:5")
        XCTAssertEqual(nodes.last?["depth"] as? Int, 2)
    }

    func testCropScreenshotWritesPNG() throws {
        let root = try makeSnapshotRoot()
        try writeSnapshot(
            at: root.appendingPathComponent("current/snapshot.json"),
            snapshotID: "20260401T124000Z",
            capturedAt: "2026-04-01T12:40:00Z",
            appName: "Demo",
            bundleID: "com.demo.app",
            nodes: makeRelationFixtureNodes(),
            screenshot: (width: 200, height: 200)
        )

        let response = try invokeServer(
            with: [
                "jsonrpc": "2.0",
                "id": 1,
                "method": "tools/call",
                "params": [
                    "name": "lookin.crop_screenshot",
                    "arguments": [
                        "node_id": "oid:3",
                        "padding": 4,
                    ],
                ],
            ],
            snapshotRoot: root
        )

        let payload = try parseToolPayload(response)
        let cropFile = try XCTUnwrap(payload["crop_file"] as? String)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cropFile))
        let cropRect = try XCTUnwrap(payload["crop_rect_in_screenshot"] as? [String: Any])
        XCTAssertEqual(cropRect["x"] as? Double, 22)
        XCTAssertEqual(cropRect["y"] as? Double, 20)
        XCTAssertEqual(cropRect["width"] as? Double, 40)
        XCTAssertEqual(cropRect["height"] as? Double, 40)
    }

    func testHTTPHostStatusAndToolCall() throws {
        let root = try makeSnapshotRoot()
        try writeSnapshot(
            at: root.appendingPathComponent("current/snapshot.json"),
            snapshotID: "20260401T130000Z",
            capturedAt: makeISODateString(offset: 0),
            appName: "Demo",
            bundleID: "com.demo.app",
            nodes: makeRelationFixtureNodes()
        )

        let port = try findFreePort()
        let processHandle = try launchHTTPServer(snapshotRoot: root, port: port)
        defer { stopHTTPServer(processHandle.process) }

        let status = try waitForStatus(port: port)
        XCTAssertEqual(status["state"] as? String, "ready")
        XCTAssertEqual(status["snapshot_available"] as? Bool, true)
        XCTAssertEqual(status["snapshot_id"] as? String, "20260401T130000Z")

        let response = try sendHTTPRPC(
            port: port,
            payload: [
                "jsonrpc": "2.0",
                "id": 1,
                "method": "tools/call",
                "params": [
                    "name": "lookin.find_nodes",
                    "arguments": [
                        "ivar_name": "topBar",
                    ],
                ],
            ]
        )
        let payload = try parseToolPayload(response)
        XCTAssertEqual(payload["match_count"] as? Int, 1)

        let connectedStatus = try waitForStatus(port: port, predicate: {
            ($0["state"] as? String) == "connected"
        })
        XCTAssertEqual(connectedStatus["state"] as? String, "connected")
        XCTAssertNotNil(connectedStatus["last_request_at"] as? String)
    }

    func testHTTPHostWithoutSnapshotReportsStaleAndToolError() throws {
        let root = try makeSnapshotRoot()
        let port = try findFreePort()
        let processHandle = try launchHTTPServer(snapshotRoot: root, port: port)
        defer { stopHTTPServer(processHandle.process) }

        let status = try waitForStatus(port: port)
        XCTAssertEqual(status["state"] as? String, "stale")
        XCTAssertEqual(status["snapshot_available"] as? Bool, false)

        let response = try sendHTTPRPC(
            port: port,
            payload: [
                "jsonrpc": "2.0",
                "id": 2,
                "method": "tools/call",
                "params": [
                    "name": "lookin.get_latest_snapshot",
                    "arguments": [:],
                ],
            ]
        )
        let error = try XCTUnwrap(response["error"] as? [String: Any])
        XCTAssertEqual(error["message"] as? String, "NO_SNAPSHOT_AVAILABLE: 未找到可读取的 snapshot.json。")
    }

    func testHTTPHostPortConflictReturnsFailure() throws {
        let root = try makeSnapshotRoot()
        let port = try findFreePort()
        let firstHandle = try launchHTTPServer(snapshotRoot: root, port: port)
        defer { stopHTTPServer(firstHandle.process) }
        _ = try waitForStatus(port: port)

        let secondHandle = try launchHTTPServer(snapshotRoot: root, port: port)
        secondHandle.process.waitUntilExit()
        let stderrData = secondHandle.stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrText = String(decoding: stderrData, as: UTF8.self)

        XCTAssertNotEqual(secondHandle.process.terminationStatus, 0)
        XCTAssertTrue(stderrText.contains("PORT_UNAVAILABLE"))
    }

    func testHTTPHostStopsServingAfterProcessTermination() throws {
        let root = try makeSnapshotRoot()
        let port = try findFreePort()
        let processHandle = try launchHTTPServer(snapshotRoot: root, port: port)
        _ = try waitForStatus(port: port)

        stopHTTPServer(processHandle.process)
        XCTAssertThrowsError(try fetchStatus(port: port))
    }

    func testHTTPHostMarksOldSnapshotAsStale() throws {
        let root = try makeSnapshotRoot()
        try writeSnapshot(
            at: root.appendingPathComponent("current/snapshot.json"),
            snapshotID: "20260401T080000Z",
            capturedAt: makeISODateString(offset: -3600),
            appName: "Demo",
            bundleID: "com.demo.app",
            nodes: makeRelationFixtureNodes()
        )

        let port = try findFreePort()
        let processHandle = try launchHTTPServer(snapshotRoot: root, port: port)
        defer { stopHTTPServer(processHandle.process) }

        let status = try waitForStatus(port: port)
        XCTAssertEqual(status["state"] as? String, "stale")
        XCTAssertEqual(status["snapshot_is_stale"] as? Bool, true)
    }

    func testAssembleReleaseAppEmbedsHelperAndVerifyPasses() throws {
        let root = makeTemporaryDirectory()
        let appURL = try makeFakeLookinApp(in: root)
        let helperURL = try makeExecutableScript(
            at: root.appendingPathComponent("lookin-mcp"),
            body: "#!/bin/bash\necho embedded helper\n"
        )

        let assembleScript = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("scripts/release/assemble-lookin-app.sh")
        let verifyScript = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("scripts/release/verify-lookin-release.sh")

        try runProcess(
            executableURL: assembleScript,
            arguments: ["--app", appURL.path, "--helper", helperURL.path]
        )

        let embeddedHelper = appURL.appendingPathComponent("Contents/PlugIns/lookin-mcp")
        XCTAssertTrue(FileManager.default.fileExists(atPath: embeddedHelper.path))
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: embeddedHelper.path))

        try runProcess(
            executableURL: verifyScript,
            arguments: ["--app", appURL.path]
        )
    }

    func testVerifyReleaseFailsWhenHelperMissing() throws {
        let root = makeTemporaryDirectory()
        let appURL = try makeFakeLookinApp(in: root)
        let verifyScript = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("scripts/release/verify-lookin-release.sh")

        XCTAssertThrowsError(
            try runProcess(
                executableURL: verifyScript,
                arguments: ["--app", appURL.path]
            )
        ) { error in
            let message = String(describing: error)
            XCTAssertTrue(message.contains("Embedded helper missing"))
        }
    }

    private func invokeServer(with request: [String: Any], snapshotRoot: URL) throws -> [String: Any] {
        let executableURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/debug/lookin-mcp")

        let requestData = try JSONSerialization.data(withJSONObject: request, options: [])
        let framedRequest = Data("Content-Length: \(requestData.count)\r\n\r\n".utf8) + requestData

        let process = Process()
        process.executableURL = executableURL
        process.environment = [
            "LOOKIN_SNAPSHOT_ROOT": snapshotRoot.path
        ]

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe

        try process.run()
        inputPipe.fileHandleForWriting.write(framedRequest)
        try inputPipe.fileHandleForWriting.close()

        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0)

        let separator = Data("\r\n\r\n".utf8)
        guard let range = output.range(of: separator) else {
            XCTFail("Server did not emit an MCP header")
            return [:]
        }

        let body = output.subdata(in: range.upperBound..<output.endIndex)
        let json = try JSONSerialization.jsonObject(with: body, options: [])
        return try XCTUnwrap(json as? [String: Any])
    }

    private func parseToolPayload(_ response: [String: Any]) throws -> [String: Any] {
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let content = try XCTUnwrap(result["content"] as? [[String: Any]])
        let text = try XCTUnwrap(content.first?["text"] as? String)
        let data = Data(text.utf8)
        let json = try JSONSerialization.jsonObject(with: data, options: [])
        return try XCTUnwrap(json as? [String: Any])
    }

    private func launchHTTPServer(snapshotRoot: URL, port: UInt16) throws -> (process: Process, stderrPipe: Pipe) {
        let executableURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/debug/lookin-mcp")

        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["--transport", "http", "--port", "\(port)"]
        process.environment = [
            "LOOKIN_SNAPSHOT_ROOT": snapshotRoot.path
        ]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        try process.run()
        return (process, stderrPipe)
    }

    private func stopHTTPServer(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        process.waitUntilExit()
    }

    private func waitForStatus(
        port: UInt16,
        timeout: TimeInterval = 6,
        predicate: (([String: Any]) -> Bool)? = nil
    ) throws -> [String: Any] {
        let deadline = Date().addingTimeInterval(timeout)
        var lastError: Error?
        while Date() < deadline {
            do {
                let status = try fetchStatus(port: port)
                if predicate?(status) ?? true {
                    return status
                }
            } catch {
                lastError = error
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        throw lastError ?? NSError(domain: "LookinMCPServerTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "等待 /status 超时"])
    }

    private func fetchStatus(port: UInt16) throws -> [String: Any] {
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/status"))
        let semaphore = DispatchSemaphore(value: 0)
        let resultBox = HTTPResultBox()

        URLSession.shared.dataTask(with: url) { data, response, error in
            defer { semaphore.signal() }
            if let error {
                resultBox.set(.failure(error))
                return
            }
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
                  let data else {
                resultBox.set(.failure(NSError(domain: "LookinMCPServerTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "状态接口返回非 200"])))
                return
            }
            do {
                let json = try JSONSerialization.jsonObject(with: data, options: [])
                resultBox.set(.success(try XCTUnwrap(json as? [String: Any])))
            } catch {
                resultBox.set(.failure(error))
            }
        }.resume()

        semaphore.wait()
        return try XCTUnwrap(resultBox.get()).get()
    }

    private func sendHTTPRPC(port: UInt16, payload: [String: Any]) throws -> [String: Any] {
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/mcp"))
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let semaphore = DispatchSemaphore(value: 0)
        let resultBox = HTTPResultBox()

        URLSession.shared.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            if let error {
                resultBox.set(.failure(error))
                return
            }
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
                  let data else {
                resultBox.set(.failure(NSError(domain: "LookinMCPServerTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "MCP 接口返回非 200"])))
                return
            }
            do {
                let json = try JSONSerialization.jsonObject(with: data, options: [])
                resultBox.set(.success(try XCTUnwrap(json as? [String: Any])))
            } catch {
                resultBox.set(.failure(error))
            }
        }.resume()

        semaphore.wait()
        return try XCTUnwrap(resultBox.get()).get()
    }

    private func findFreePort() throws -> UInt16 {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(fd, 0)
        defer { close(fd) }

        var value: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &value, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(0).bigEndian
        addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        XCTAssertEqual(bindResult, 0)

        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let getsocknameResult = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &len)
            }
        }
        XCTAssertEqual(getsocknameResult, 0)
        return UInt16(bigEndian: addr.sin_port)
    }

    private func makeISODateString(offset: TimeInterval) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: Date().addingTimeInterval(offset))
    }

    private func makeTemporaryDirectory() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    private func makeSnapshotRoot() throws -> URL {
        let root = makeTemporaryDirectory()
        try FileManager.default.createDirectory(at: root.appendingPathComponent("current", isDirectory: true), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("history", isDirectory: true), withIntermediateDirectories: true)
        return root
    }

    private func writeSnapshot(
        at url: URL,
        snapshotID: String,
        capturedAt: String,
        appName: String,
        bundleID: String,
        nodes: [[String: Any]],
        screenshot: (width: Double, height: Double)? = nil
    ) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let screenshot {
            try writeTestScreenshot(
                to: url.deletingLastPathComponent().appendingPathComponent("screenshot.png"),
                width: Int(screenshot.width),
                height: Int(screenshot.height)
            )
        }

        var payload: [String: Any] = [
            "schema_version": "lookin-mcp-snapshot-v1",
            "snapshot_id": snapshotID,
            "captured_at": capturedAt,
            "source": [
                "exporter": "lookin-mac",
                "exporter_version": "0.1.0",
            ],
            "app": [
                "app_name": appName,
                "bundle_id": bundleID,
                "device_description": "iPhone",
                "os_description": "iOS 18.0",
                "lookin_server_version": "1.0.0",
                "screen": [
                    "width": 393,
                    "height": 852,
                    "scale": 3,
                ],
            ],
            "visible_view_controller_names": ["HomeViewController"],
            "tree": [
                "root_node_ids": ["oid:1"],
                "node_count": nodes.count,
                "nodes": nodes,
            ],
        ]
        if let screenshot {
            payload["screenshot"] = [
                "relative_path": "screenshot.png",
                "width": screenshot.width,
                "height": screenshot.height,
            ]
        }
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url)
    }

    private func sampleNode(
        nodeID: String,
        title: String,
        className: String,
        hostViewControllerName: String = "",
        ivarNames: [String] = [],
        textValues: [String] = [],
        childIDs: [String] = [],
        parentID: String? = nil,
        indentLevel: Int = 0,
        frame: [String: Any]? = nil,
        bounds: [String: Any]? = nil,
        frameToRoot: [String: Any]? = nil
    ) -> [String: Any] {
        [
            "node_id": nodeID,
            "parent_id": parentID as Any,
            "child_ids": childIDs,
            "title": title,
            "subtitle": "",
            "class_name": className,
            "raw_class_name": className,
            "class_chain": [className, "UIView", "NSObject"],
            "memory_address": "0x123",
            "host_view_controller_name": hostViewControllerName,
            "ivar_names": ivarNames,
            "is_hidden": false,
            "alpha": 1.0,
            "displaying_in_hierarchy": true,
            "in_hidden_hierarchy": false,
            "indent_level": indentLevel,
            "represented_as_key_window": false,
            "is_user_custom": false,
            "oid": Int(nodeID.replacingOccurrences(of: "oid:", with: "")) ?? 0,
            "frame": frame ?? [
                "x": 0,
                "y": 0,
                "width": 100,
                "height": 40,
            ],
            "bounds": bounds ?? [
                "x": 0,
                "y": 0,
                "width": 100,
                "height": 40,
            ],
            "frame_to_root": frameToRoot ?? frame ?? [
                "x": 0,
                "y": 0,
                "width": 100,
                "height": 40,
            ],
            "text_values": textValues,
            "layout_evidence": [
                "intrinsic_size": "{100, 40}",
                "constraints": ["self.width = nil.notAnAttribute @1000"],
            ],
            "visual_evidence": [
                "hidden": false,
                "opacity": 1,
                "user_interaction_enabled": true,
                "masks_to_bounds": false,
                "background_color": [
                    "rgba_string": "(255, 0, 0)",
                    "hex_string": "#ff0000",
                    "components": [1, 0, 0, 1],
                ],
                "border_color": [
                    "rgba_string": "(0, 0, 0)",
                    "hex_string": "#000000",
                    "components": [0, 0, 0, 1],
                ],
                "border_width": 0,
                "corner_radius": 0,
                "shadow": [
                    "color": [
                        "rgba_string": "(0, 0, 0)",
                        "hex_string": "#000000",
                        "components": [0, 0, 0, 1],
                    ],
                    "opacity": 0,
                    "radius": 3,
                    "offset": [
                        "width": 0,
                        "height": -3,
                    ],
                ],
            ],
            "search_text": ([title, className, hostViewControllerName] + ivarNames + textValues)
                .filter { !$0.isEmpty }
                .joined(separator: " | "),
        ]
    }

    private func makeRelationFixtureNodes() -> [[String: Any]] {
        [
            sampleNode(
                nodeID: "oid:1",
                title: "UIWindow",
                className: "UIWindow",
                hostViewControllerName: "HomeViewController",
                childIDs: ["oid:2"],
                indentLevel: 0,
                frame: rect(x: 0, y: 0, width: 200, height: 200)
            ),
            sampleNode(
                nodeID: "oid:2",
                title: "UIView",
                className: "UIView",
                hostViewControllerName: "HomeViewController",
                ivarNames: ["topBar"],
                childIDs: ["oid:3", "oid:4"],
                parentID: "oid:1",
                indentLevel: 1,
                frame: rect(x: 10, y: 20, width: 180, height: 40)
            ),
            sampleNode(
                nodeID: "oid:3",
                title: "UIButton",
                className: "UIButton",
                hostViewControllerName: "HomeViewController",
                ivarNames: ["backButton"],
                childIDs: ["oid:5"],
                parentID: "oid:2",
                indentLevel: 2,
                frame: rect(x: 26, y: 24, width: 32, height: 32)
            ),
            sampleNode(
                nodeID: "oid:4",
                title: "UIButton",
                className: "UIButton",
                hostViewControllerName: "HomeViewController",
                ivarNames: ["moreButton"],
                parentID: "oid:2",
                indentLevel: 2,
                frame: rect(x: 142, y: 24, width: 32, height: 32)
            ),
            sampleNode(
                nodeID: "oid:5",
                title: "UIImageView",
                className: "UIImageView",
                hostViewControllerName: "HomeViewController",
                parentID: "oid:3",
                indentLevel: 3,
                frame: rect(x: 26, y: 24, width: 32, height: 32),
                bounds: rect(x: 0, y: 0, width: 32, height: 32)
            )
        ]
    }

    private func rect(x: Double, y: Double, width: Double, height: Double) -> [String: Any] {
        [
            "x": x,
            "y": y,
            "width": width,
            "height": height,
        ]
    }

    private func writeTestScreenshot(to url: URL, width: Int, height: Int) throws {
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()
        NSColor.systemBlue.setFill()
        NSBezierPath(rect: NSRect(x: 26, y: 24, width: 32, height: 32)).fill()
        NSColor.systemRed.setFill()
        NSBezierPath(rect: NSRect(x: 142, y: 24, width: 32, height: 32)).fill()
        image.unlockFocus()

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            XCTFail("无法生成测试 PNG")
            return
        }
        try pngData.write(to: url)
    }

    private func makeFakeLookinApp(in root: URL) throws -> URL {
        let appURL = root.appendingPathComponent("Lookin.app", isDirectory: true)
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        let macOSURL = contentsURL.appendingPathComponent("MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: macOSURL, withIntermediateDirectories: true)

        let executableURL = try makeExecutableScript(
            at: macOSURL.appendingPathComponent("Lookin"),
            body: "#!/bin/bash\nsleep 1\n"
        )
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: executableURL.path))

        let infoPlistURL = contentsURL.appendingPathComponent("Info.plist")
        let infoPlist: [String: Any] = [
            "CFBundleExecutable": "Lookin",
            "CFBundleIdentifier": "com.example.Lookin",
            "CFBundleName": "Lookin",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "1",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: infoPlist, format: .xml, options: 0)
        try data.write(to: infoPlistURL)
        return appURL
    }

    @discardableResult
    private func makeExecutableScript(at url: URL, body: String) throws -> URL {
        guard let data = body.data(using: .utf8) else {
            throw NSError(domain: "LookinMCPServerTests", code: 99, userInfo: [NSLocalizedDescriptionKey: "无法编码脚本文本"])
        }
        try data.write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    private func runProcess(executableURL: URL, arguments: [String]) throws {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let stderr = String(decoding: stderrPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            let stdout = String(decoding: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw NSError(
                domain: "LookinMCPServerTests",
                code: Int(process.terminationStatus),
                userInfo: [
                    NSLocalizedDescriptionKey: [stderr, stdout].filter { !$0.isEmpty }.joined(separator: "\n")
                ]
            )
        }
    }
}
