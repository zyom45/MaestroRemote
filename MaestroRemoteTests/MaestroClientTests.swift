import XCTest
@testable import MaestroRemote

@MainActor
final class MaestroClientTests: XCTestCase {

    var client: MaestroClient!

    override func setUp() {
        super.setUp()
        client = MaestroClient()
        client.baseURL = "http://localhost:27182"
        // テスト用 URLSession に差し替え
        MaestroClient.urlSession = MockURLProtocol.makeSession()
    }

    override func tearDown() {
        client.stopPolling()
        client = nil
        MockURLProtocol.requestHandler = nil
        MaestroClient.urlSession = .shared
        super.tearDown()
    }

    // MARK: - fetchPending

    func test_fetchPending_setsIsConnected() async throws {
        MockURLProtocol.requestHandler = { _ in
            let json = """
            {"pending":[],"alwaysYes":false,"autoPilot":false}
            """.data(using: .utf8)!
            return (200, json)
        }
        await client.fetchPending()
        XCTAssertTrue(client.isConnected)
        XCTAssertTrue(client.pendingPermissions.isEmpty)
    }

    func test_fetchPending_parsesPermissions() async throws {
        let permID = UUID()
        MockURLProtocol.requestHandler = { _ in
            let json = """
            {
              "pending": [{
                "id": "\(permID.uuidString)",
                "toolName": "Bash",
                "toolInput": "{\\"command\\":\\"ls -la\\"}",
                "label": "myproject",
                "cwd": "/tmp/myproject",
                "sessionId": "sess-1",
                "enqueuedAt": "2025-01-01T00:00:00Z"
              }],
              "alwaysYes": false,
              "autoPilot": true
            }
            """.data(using: .utf8)!
            return (200, json)
        }
        await client.fetchPending()
        XCTAssertEqual(client.pendingPermissions.count, 1)
        XCTAssertEqual(client.pendingPermissions[0].toolName, "Bash")
        XCTAssertEqual(client.pendingPermissions[0].id, permID)
        XCTAssertTrue(client.autoPilot)
    }

    func test_fetchPending_on404_setsDisconnected() async {
        MockURLProtocol.requestHandler = { _ in (404, Data()) }
        await client.fetchPending()
        XCTAssertFalse(client.isConnected)
    }

    func test_fetchPending_onError_setsDisconnected() async {
        MockURLProtocol.requestHandler = { _ in throw URLError(.notConnectedToInternet) }
        await client.fetchPending()
        XCTAssertFalse(client.isConnected)
        XCTAssertNotNil(client.errorMessage)
    }

    // MARK: - respond

    func test_respond_yes_removesPermission() async {
        let permID = UUID()
        // キューにアイテムを入れておく
        MockURLProtocol.requestHandler = { _ in
            let json = """
            {"pending":[{
                "id":"\(permID.uuidString)","toolName":"Edit",
                "toolInput":"{}","label":"proj","cwd":"/tmp","sessionId":"s",
                "enqueuedAt":"2025-01-01T00:00:00Z"
            }],"alwaysYes":false,"autoPilot":false}
            """.data(using: .utf8)!
            return (200, json)
        }
        await client.fetchPending()
        XCTAssertEqual(client.pendingPermissions.count, 1)

        // respond をモック
        MockURLProtocol.requestHandler = { req in
            if let body = req.httpBody,
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                XCTAssertEqual(json["action"] as? String, "yes")
            }
            return (200, #"{"ok":true}"#.data(using: .utf8)!)
        }
        let ok = await client.respond(id: permID, action: "yes")
        XCTAssertTrue(ok)
        XCTAssertTrue(client.pendingPermissions.isEmpty)
    }

    func test_respond_no_ok() async {
        let id = UUID()
        MockURLProtocol.requestHandler = { _ in (200, #"{"ok":true}"#.data(using: .utf8)!) }
        let ok = await client.respond(id: id, action: "no")
        XCTAssertTrue(ok)
    }

    // MARK: - Permission helpers

    func test_permission_toolEmoji_bash() {
        let p = makePerm(toolName: "Bash")
        XCTAssertEqual(p.toolEmoji, "⌨️")
    }

    func test_permission_primaryArg_command() {
        let p = makePerm(toolName: "Bash", toolInput: #"{"command":"npm test"}"#)
        XCTAssertEqual(p.primaryArg, "npm test")
    }

    func test_permission_primaryArg_filePath() {
        let p = makePerm(toolName: "Edit", toolInput: #"{"file_path":"/src/main.swift"}"#)
        XCTAssertEqual(p.primaryArg, "/src/main.swift")
    }

    // MARK: - Helper

    private func makePerm(toolName: String, toolInput: String = "{}") -> MaestroClient.Permission {
        MaestroClient.Permission(
            id: UUID(), toolName: toolName, toolInput: toolInput,
            label: "proj", cwd: "/tmp/proj", sessionId: "s",
            enqueuedAt: "2025-01-01T00:00:00Z"
        )
    }
}
