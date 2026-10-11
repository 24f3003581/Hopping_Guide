// UmaTests/DouglasPeuckerTests.swift

import XCTest
import CoreLocation
@testable import Uma

final class DouglasPeuckerTests: XCTestCase {
    func test_straightLineSimplifiesToTwoPoints() {
        let points = (0..<1000).map { i in
            CLLocationCoordinate2D(latitude: 22.5 + Double(i) * 0.0001,
                                   longitude: 88.3 + Double(i) * 0.0001)
        }
        let simplified = simplifyRoute(points, tolerance: 0.00005)
        XCTAssertEqual(simplified.count, 2)
    }

    func test_arcPreservesEndpoints() {
        let points = (0..<50).map { i in
            CLLocationCoordinate2D(latitude: 22.5 + sin(Double(i) * 0.1) * 0.01,
                                   longitude: 88.3 + cos(Double(i) * 0.1) * 0.01)
        }
        let simplified = simplifyRoute(points, tolerance: 0.0001)
        XCTAssertEqual(simplified.first?.latitude, points.first?.latitude)
        XCTAssertEqual(simplified.first?.longitude, points.first?.longitude)
        XCTAssertEqual(simplified.last?.latitude, points.last?.latitude)
        XCTAssertEqual(simplified.last?.longitude, points.last?.longitude)
        XCTAssertLessThan(simplified.count, points.count)
    }

    func test_fewerThan3ReturnsInput() {
        let points = [
            CLLocationCoordinate2D(latitude: 22.5, longitude: 88.3),
            CLLocationCoordinate2D(latitude: 22.6, longitude: 88.4),
        ]
        let s = simplifyRoute(points)
        XCTAssertEqual(s.count, 2)
    }
}
