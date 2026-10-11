// UmaTests/GroupVideoApiTests.swift
// Tests GroupVideoApi URL resolution, fallback endpoints, and synthetic sessions

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

    func testSyntheticSessionHasValidStructure() {
        let session = GroupVideoApi.createSyntheticSession(squadId: "TEST12", userId: "hopper_1")
        XCTAssertEqual(session.callId, "squad_TEST12")
        XCTAssertEqual(session.callType, "uma_squad")
        XCTAssertFalse(session.apiKey.isEmpty)
        XCTAssertFalse(session.token.isEmpty)
    }
}
