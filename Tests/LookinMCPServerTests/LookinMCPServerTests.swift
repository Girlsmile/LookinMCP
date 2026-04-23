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
        let capabilities = try XCTUnwrap(result["capabilities"] as? [String: Any])
        XCTAssertEqual(serverInfo["name"] as? String, "lookin-mcp")
        XCTAssertEqual(serverInfo["version"] as? String, "0.3.0")
        XCTAssertNotNil(capabilities["tools"] as? [String: Any])
        XCTAssertNotNil(capabilities["resources"] as? [String: Any])
        XCTAssertNotNil(capabilities["prompts"] as? [String: Any])
    }

    func testToolsListContainsUnifiedSurfaceTools() throws {
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
            "lookin.screen",
            "lookin.find",
            "lookin.inspect",
            "lookin.capture",
            "lookin.raw",
        ])
    }

    func testRawReturnsNoSnapshotErrorWhenEmpty() throws {
        let response = try invokeServer(
            with: [
                "jsonrpc": "2.0",
                "id": 1,
                "method": "tools/call",
                "params": [
                    "name": "lookin.raw",
                    "arguments": [:],
                ],
            ],
            snapshotRoot: makeTemporaryDirectory()
        )

        let error = try XCTUnwrap(response["error"] as? [String: Any])
        XCTAssertEqual(error["message"] as? String, "NO_SNAPSHOT_AVAILABLE: 未找到可读取的 snapshot.json。")
    }

    func testResourcesListReturnsSnapshotResources() throws {
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
                "method": "resources/list",
            ],
            snapshotRoot: root
        )

        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let resources = try XCTUnwrap(result["resources"] as? [[String: Any]])
        let uris = Set(resources.compactMap { $0["uri"] as? String })
        XCTAssertTrue(uris.contains("lookin://snapshots/current/summary"))
        XCTAssertTrue(uris.contains("lookin://snapshots/current/raw"))
        XCTAssertTrue(uris.contains("lookin://snapshots/current/screenshot"))
    }

    func testFindFiltersByVCAndIvar() throws {
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
                    "name": "lookin.find",
                    "arguments": [
                        "vc_name": "HomeViewController",
                        "ivar_name": "titleLabel",
                        "detail": "full",
                        "include": ["style"],
                    ],
                ],
            ],
            snapshotRoot: root
        )

        let payload = try parseToolPayload(response)
        XCTAssertEqual(payload["match_count"] as? Int, 1)
        XCTAssertEqual(payload["detail"] as? String, "full")

        let nodes = try XCTUnwrap(payload["nodes"] as? [[String: Any]])
        XCTAssertEqual(nodes.first?["class_name"] as? String, "UILabel")
        XCTAssertEqual(nodes.first?["host_view_controller_name"] as? String, "HomeViewController")
        let visualEvidence = try XCTUnwrap(nodes.first?["visual_evidence"] as? [String: Any])
        XCTAssertEqual(visualEvidence["masks_to_bounds"] as? Bool, false)
        let backgroundColor = try XCTUnwrap(visualEvidence["background_color"] as? [String: Any])
        XCTAssertEqual(backgroundColor["hex_string"] as? String, "#ff0000")
    }

    func testFindReturnsMatchedByReasons() throws {
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
                    "name": "lookin.find",
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

    func testInspectReturnsParentAndChildren() throws {
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
                    "name": "lookin.inspect",
                    "arguments": [
                        "node_id": "oid:2",
                        "detail": "full",
                        "include": ["relations", "children", "style"],
                    ],
                ],
            ],
            snapshotRoot: root
        )

        let payload = try parseToolPayload(response)
        let node = try XCTUnwrap(payload["node"] as? [String: Any])
        XCTAssertEqual(node["node_id"] as? String, "oid:2")
        XCTAssertEqual(node["class_name"] as? String, "UIView")

        let relations = try XCTUnwrap(payload["relations"] as? [String: Any])
        let parent = try XCTUnwrap(relations["parent"] as? [String: Any])
        let parentNode = try XCTUnwrap(parent["node"] as? [String: Any])
        XCTAssertEqual(parentNode["node_id"] as? String, "oid:1")

        let children = try XCTUnwrap(payload["children"] as? [[String: Any]])
        XCTAssertEqual(children.count, 2)
        XCTAssertEqual(Set(children.compactMap { $0["node_id"] as? String }), ["oid:3", "oid:4"])

        let visualEvidence = try XCTUnwrap(payload["visual_evidence"] as? [String: Any])
        XCTAssertEqual(visualEvidence["corner_radius"] as? Double, 0)
    }

    func testInspectReturnsInsetsAndSiblingMetrics() throws {
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
                    "name": "lookin.inspect",
                    "arguments": [
                        "node_id": "oid:3",
                        "detail": "standard",
                        "include": ["relations"],
                    ],
                ],
            ],
            snapshotRoot: root
        )

        let payload = try parseToolPayload(response)
        let relations = try XCTUnwrap(payload["relations"] as? [String: Any])
        let withinParentInsets = try XCTUnwrap(relations["within_parent_insets"] as? [String: Any])
        XCTAssertEqual(withinParentInsets["left"] as? Double, 16)
        XCTAssertEqual(withinParentInsets["top"] as? Double, 4)

        let parent = try XCTUnwrap(relations["parent"] as? [String: Any])
        let parentRelation = try XCTUnwrap(parent["relation"] as? [String: Any])
        XCTAssertEqual(parentRelation["relative_position"] as? String, "overlapping")

        let siblings = try XCTUnwrap(relations["siblings"] as? [[String: Any]])
        XCTAssertEqual(siblings.count, 1)
        let siblingNode = try XCTUnwrap(siblings.first?["node"] as? [String: Any])
        XCTAssertEqual(siblingNode["node_id"] as? String, "oid:4")
        let siblingRelation = try XCTUnwrap(siblings.first?["relation"] as? [String: Any])
        XCTAssertEqual(siblingRelation["relative_position"] as? String, "right")
        XCTAssertEqual(siblingRelation["horizontal_gap"] as? Double, 84)
    }

    func testResourceReadSubtreeReturnsFlatHierarchy() throws {
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
                "method": "resources/read",
                "params": [
                    "uri": "lookin://snapshots/current/nodes/oid:2/subtree?max_depth=2&max_nodes=80",
                ],
            ],
            snapshotRoot: root
        )

        let payload = try parseResourcePayload(response)
        XCTAssertEqual(payload["root_node_id"] as? String, "oid:2")
        XCTAssertEqual(payload["returned_node_count"] as? Int, 4)
        let nodes = try XCTUnwrap(payload["nodes"] as? [[String: Any]])
        XCTAssertEqual(nodes.first?["node_id"] as? String, "oid:2")
        XCTAssertEqual(nodes.first?["depth"] as? Int, 0)
        XCTAssertEqual(nodes.last?["node_id"] as? String, "oid:5")
        XCTAssertEqual(nodes.last?["depth"] as? Int, 2)
    }

    func testCaptureWritesPNG() throws {
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
                    "name": "lookin.capture",
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

    func testPromptListAndGetExposeUIAnalysisWorkflows() throws {
        let listResponse = try invokeServer(
            with: [
                "jsonrpc": "2.0",
                "id": 1,
                "method": "prompts/list",
            ],
            snapshotRoot: makeTemporaryDirectory()
        )

        let listResult = try XCTUnwrap(listResponse["result"] as? [String: Any])
        let prompts = try XCTUnwrap(listResult["prompts"] as? [[String: Any]])
        XCTAssertEqual(Set(prompts.compactMap { $0["name"] as? String }), [
            "analyze-node-layout",
            "analyze-node-visual-style",
            "diagnose-spacing-and-alignment",
        ])

        let getResponse = try invokeServer(
            with: [
                "jsonrpc": "2.0",
                "id": 2,
                "method": "prompts/get",
                "params": [
                    "name": "analyze-node-layout",
                    "arguments": [
                        "node_id": "oid:topBar",
                        "focus": "左右间距",
                    ],
                ],
            ],
            snapshotRoot: makeTemporaryDirectory()
        )

        let getResult = try XCTUnwrap(getResponse["result"] as? [String: Any])
        let messages = try XCTUnwrap(getResult["messages"] as? [[String: Any]])
        let content = try XCTUnwrap(messages.first?["content"] as? [String: Any])
        let text = try XCTUnwrap(content["text"] as? String)
        XCTAssertTrue(text.contains("lookin.inspect"))
        XCTAssertTrue(text.contains("oid:topBar"))
        XCTAssertTrue(text.contains("左右间距"))
        XCTAssertTrue(text.contains("mode=brief"))
        XCTAssertTrue(text.contains("/layout"))
    }

    func testInspectCompactAndFullDetailBehaviors() throws {
        let root = try makeSnapshotRoot()
        try writeSnapshot(
            at: root.appendingPathComponent("current/snapshot.json"),
            snapshotID: "20260401T125000Z",
            capturedAt: "2026-04-01T12:50:00Z",
            appName: "Demo",
            bundleID: "com.demo.app",
            nodes: makeRelationFixtureNodes()
        )

        let compactResponse = try invokeServer(
            with: [
                "jsonrpc": "2.0",
                "id": 1,
                "method": "tools/call",
                "params": [
                    "name": "lookin.inspect",
                    "arguments": [
                        "node_id": "oid:2",
                    ],
                ],
            ],
            snapshotRoot: root
        )
        let compactPayload = try parseToolPayload(compactResponse)
        XCTAssertNotNil(compactPayload["layout_evidence"] as? [String: Any])
        XCTAssertNil(compactPayload["visual_evidence"])
        XCTAssertNil(compactPayload["children"])

        let fullResponse = try invokeServer(
            with: [
                "jsonrpc": "2.0",
                "id": 2,
                "method": "tools/call",
                "params": [
                    "name": "lookin.inspect",
                    "arguments": [
                        "node_id": "oid:2",
                        "detail": "full",
                        "include": ["style", "children"],
                    ],
                ],
            ],
            snapshotRoot: root
        )
        let fullPayload = try parseToolPayload(fullResponse)
        XCTAssertNotNil(fullPayload["visual_evidence"] as? [String: Any])
        let children = try XCTUnwrap(fullPayload["children"] as? [[String: Any]])
        XCTAssertEqual(children.count, 2)
    }

    func testFindIDsModeReturnsOnlyIdentifiers() throws {
        let root = try makeSnapshotRoot()
        try writeSnapshot(
            at: root.appendingPathComponent("current/snapshot.json"),
            snapshotID: "20260401T125100Z",
            capturedAt: "2026-04-01T12:51:00Z",
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
                    "name": "lookin.find",
                    "arguments": [
                        "ivar_name": "topBar",
                        "mode": "ids",
                    ],
                ],
            ],
            snapshotRoot: root
        )

        let payload = try parseToolPayload(response)
        XCTAssertEqual(payload["sid"] as? String, "20260401T125100Z")
        XCTAssertEqual(payload["total"] as? Int, 1)
        XCTAssertEqual(payload["ids"] as? [String], ["oid:2"])
        XCTAssertNil(payload["nodes"])
        XCTAssertNil(payload["resource_links"])
        XCTAssertNil(payload["layout_evidence"])
        XCTAssertNil(payload["style"])
    }

    func testInspectBriefModeReturnsShortStableFields() throws {
        let root = try makeSnapshotRoot()
        try writeSnapshot(
            at: root.appendingPathComponent("current/snapshot.json"),
            snapshotID: "20260401T125200Z",
            capturedAt: "2026-04-01T12:52:00Z",
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
                    "name": "lookin.inspect",
                    "arguments": [
                        "node_id": "oid:2",
                        "mode": "brief",
                    ],
                ],
            ],
            snapshotRoot: root
        )

        let payload = try parseToolPayload(response)
        XCTAssertEqual(payload["sid"] as? String, "20260401T125200Z")
        let node = try XCTUnwrap(payload["node"] as? [String: Any])
        XCTAssertEqual(node["id"] as? String, "oid:2")
        XCTAssertEqual(node["cls"] as? String, "UIView")
        XCTAssertEqual(node["raw"] as? String, "UIView")
        XCTAssertEqual(node["vc"] as? String, "HomeViewController")
        XCTAssertEqual(node["ch"] as? Int, 2)
        let frame = try XCTUnwrap(node["f"] as? [Double])
        XCTAssertEqual(frame, [10, 20, 180, 40])
        XCTAssertNil(payload["resource_links"])
        XCTAssertNil(payload["layout_evidence"])
    }

    func testSectionResourcesReturnFocusedEvidenceAndPaginatedChildren() throws {
        let root = try makeSnapshotRoot()
        try writeSnapshot(
            at: root.appendingPathComponent("current/snapshot.json"),
            snapshotID: "20260401T125300Z",
            capturedAt: "2026-04-01T12:53:00Z",
            appName: "Demo",
            bundleID: "com.demo.app",
            nodes: makeRelationFixtureNodes()
        )

        let layout = try parseResourcePayload(invokeServer(
            with: [
                "jsonrpc": "2.0",
                "id": 1,
                "method": "resources/read",
                "params": [
                    "uri": "lookin://snapshots/current/nodes/oid:2/layout",
                ],
            ],
            snapshotRoot: root
        ))
        XCTAssertEqual(layout["sid"] as? String, "20260401T125300Z")
        XCTAssertEqual(layout["id"] as? String, "oid:2")
        XCTAssertNotNil(layout["layout"] as? [String: Any])
        XCTAssertNil(layout["style"])

        let style = try parseResourcePayload(invokeServer(
            with: [
                "jsonrpc": "2.0",
                "id": 2,
                "method": "resources/read",
                "params": [
                    "uri": "lookin://snapshots/current/nodes/oid:2/style",
                ],
            ],
            snapshotRoot: root
        ))
        XCTAssertNotNil(style["style"] as? [String: Any])
        XCTAssertNil(style["layout"])

        let relations = try parseResourcePayload(invokeServer(
            with: [
                "jsonrpc": "2.0",
                "id": 3,
                "method": "resources/read",
                "params": [
                    "uri": "lookin://snapshots/current/nodes/oid:3/relations",
                ],
            ],
            snapshotRoot: root
        ))
        let relationSection = try XCTUnwrap(relations["relations"] as? [String: Any])
        XCTAssertNotNil(relationSection["parent"] as? [String: Any])
        XCTAssertNotNil(relationSection["siblings"] as? [[String: Any]])

        let firstChildrenPage = try parseResourcePayload(invokeServer(
            with: [
                "jsonrpc": "2.0",
                "id": 4,
                "method": "resources/read",
                "params": [
                    "uri": "lookin://snapshots/current/nodes/oid:2/children?limit=1",
                ],
            ],
            snapshotRoot: root
        ))
        let firstNodes = try XCTUnwrap(firstChildrenPage["n"] as? [[String: Any]])
        XCTAssertEqual(firstNodes.count, 1)
        XCTAssertEqual(firstNodes.first?["id"] as? String, "oid:3")
        XCTAssertEqual(firstChildrenPage["next"] as? String, "1")

        let secondChildrenPage = try parseResourcePayload(invokeServer(
            with: [
                "jsonrpc": "2.0",
                "id": 5,
                "method": "resources/read",
                "params": [
                    "uri": "lookin://snapshots/current/nodes/oid:2/children?limit=1&cursor=1",
                ],
            ],
            snapshotRoot: root
        ))
        let secondNodes = try XCTUnwrap(secondChildrenPage["n"] as? [[String: Any]])
        XCTAssertEqual(secondNodes.first?["id"] as? String, "oid:4")
        XCTAssertNil(secondChildrenPage["next"])
    }

    func testLowTokenQueryPathIsSmallerThanCompactPath() throws {
        let root = try makeSnapshotRoot()
        try writeSnapshot(
            at: root.appendingPathComponent("current/snapshot.json"),
            snapshotID: "20260401T125400Z",
            capturedAt: "2026-04-01T12:54:00Z",
            appName: "Demo",
            bundleID: "com.demo.app",
            nodes: makeRelationFixtureNodes()
        )

        let compactFind = try parseToolText(invokeServer(
            with: [
                "jsonrpc": "2.0",
                "id": 1,
                "method": "tools/call",
                "params": [
                    "name": "lookin.find",
                    "arguments": [
                        "ivar_name": "topBar",
                    ],
                ],
            ],
            snapshotRoot: root
        ))
        let compactInspect = try parseToolText(invokeServer(
            with: [
                "jsonrpc": "2.0",
                "id": 2,
                "method": "tools/call",
                "params": [
                    "name": "lookin.inspect",
                    "arguments": [
                        "node_id": "oid:2",
                    ],
                ],
            ],
            snapshotRoot: root
        ))
        let lowTokenFind = try parseToolText(invokeServer(
            with: [
                "jsonrpc": "2.0",
                "id": 3,
                "method": "tools/call",
                "params": [
                    "name": "lookin.find",
                    "arguments": [
                        "ivar_name": "topBar",
                        "mode": "ids",
                    ],
                ],
            ],
            snapshotRoot: root
        ))
        let lowTokenInspect = try parseToolText(invokeServer(
            with: [
                "jsonrpc": "2.0",
                "id": 4,
                "method": "tools/call",
                "params": [
                    "name": "lookin.inspect",
                    "arguments": [
                        "node_id": "oid:2",
                        "mode": "brief",
                    ],
                ],
            ],
            snapshotRoot: root
        ))

        let compactBytes = compactFind.utf8.count + compactInspect.utf8.count
        let lowTokenBytes = lowTokenFind.utf8.count + lowTokenInspect.utf8.count
        XCTAssertLessThan(lowTokenBytes, compactBytes / 2)
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
                    "name": "lookin.find",
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
                    "name": "lookin.raw",
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
        let text = try parseToolText(response)
        let data = Data(text.utf8)
        let json = try JSONSerialization.jsonObject(with: data, options: [])
        return try XCTUnwrap(json as? [String: Any])
    }

    private func parseToolText(_ response: [String: Any]) throws -> String {
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let content = try XCTUnwrap(result["content"] as? [[String: Any]])
        return try XCTUnwrap(content.first?["text"] as? String)
    }

    private func parseResourcePayload(_ response: [String: Any]) throws -> [String: Any] {
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let contents = try XCTUnwrap(result["contents"] as? [[String: Any]])
        let text = try XCTUnwrap(contents.first?["text"] as? String)
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
