// UmaTests/GroupVideoApiTests.swift
// Tests GroupVideoApi URL resolution and the authenticated backend response shape.

import XCTest
@testable import Uma

final class GroupVideoApiTests: XCTestCase {
    func testDefaultHostedUrlIsRenderService() {
        let defaultUrl = GroupVideoApi.defaultHostedUrl
        XCTAssertEqual(defaultUrl, "https://uma-group-calling.onrender.com")
    }

    func testEffectiveBaseUrlDefaultsToHostedFallback() {
        let api = GroupVideoApi.shared
        UserDefaults.standard.removeObject(forKey: "uma.videoApiUrl")
        XCTAssertTrue(api.effectiveBaseUrl.contains("onrender.com"))
    }

    func testDecodesSessionIssuedBySquadVideoBackend() throws {
        let data = Data("""
        {
          "apiKey": "public-key",
          "userId": "firebase-uid",
          "callType": "uma_squad",
          "callId": "squad_abc123",
          "token": "server-issued-token",
          "expiresIn": 300
        }
        """.utf8)

        let session = try JSONDecoder().decode(GroupVideoSession.self, from: data)
        XCTAssertEqual(session.userId, "firebase-uid")
        XCTAssertEqual(session.callId, "squad_abc123")
        XCTAssertEqual(session.callType, "uma_squad")
        XCTAssertEqual(session.token, "server-issued-token")
    }
}
