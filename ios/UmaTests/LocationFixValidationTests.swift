// UmaTests/LocationFixValidationTests.swift
// Tests strict GPS fix validation: <= 10s age, <= 30m accuracy, spatial displacement

import XCTest
import CoreLocation
@testable import Uma

final class LocationFixValidationTests: XCTestCase {
    func testFreshAndAccurateFixPasses() {
        let loc = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 22.5726, longitude: 88.3639),
            altitude: 10,
            horizontalAccuracy: 15.0,
            verticalAccuracy: 5.0,
            timestamp: Date()
        )
        XCTAssertTrue(LocationService.isLocationValid(loc, maxAge: 10.0, maxAccuracy: 30.0))
    }

    func testStaleFixFails() {
        let staleDate = Date().addingTimeInterval(-25.0) // 25s old
        let loc = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 22.5726, longitude: 88.3639),
            altitude: 10,
            horizontalAccuracy: 10.0,
            verticalAccuracy: 5.0,
            timestamp: staleDate
        )
        XCTAssertFalse(LocationService.isLocationValid(loc, maxAge: 10.0, maxAccuracy: 30.0))
    }

    func testInaccurateFixFails() {
        let loc = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 22.5726, longitude: 88.3639),
            altitude: 10,
            horizontalAccuracy: 65.0, // > 30m jitter
            verticalAccuracy: 5.0,
            timestamp: Date()
        )
        XCTAssertFalse(LocationService.isLocationValid(loc, maxAge: 10.0, maxAccuracy: 30.0))
    }

    func testNegativeAccuracyFails() {
        let loc = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 22.5726, longitude: 88.3639),
            altitude: 10,
            horizontalAccuracy: -1.0, // Invalid fix
            verticalAccuracy: -1.0,
            timestamp: Date()
        )
        XCTAssertFalse(LocationService.isLocationValid(loc, maxAge: 10.0, maxAccuracy: 30.0))
    }

    func testNilLocationFails() {
        XCTAssertFalse(LocationService.isLocationValid(nil))
    }
}
