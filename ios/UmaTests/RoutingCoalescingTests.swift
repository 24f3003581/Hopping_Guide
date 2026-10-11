// UmaTests/RoutingCoalescingTests.swift
// Tests RoutingService directions request coalescing and cache

import XCTest
import CoreLocation
@testable import Uma

final class RoutingCoalescingTests: XCTestCase {
    func testSimultaneousIdenticalRouteRequestsCoalesce() async {
        let router = RoutingService.shared
        await router.clearCache()
        await router.resetCircuitBreaker()

        let start = CLLocationCoordinate2D(latitude: 22.5200, longitude: 88.3500)
        let end = CLLocationCoordinate2D(latitude: 22.5250, longitude: 88.3550)

        // Launch two simultaneous identical requests
        async let route1 = router.getWalkingRoute(start: start, destination: end, destinationName: "Test 1")
        async let route2 = router.getWalkingRoute(start: start, destination: end, destinationName: "Test 2")

        let (r1, r2) = await (route1, route2)

        XCTAssertEqual(r1.distanceMeters, r2.distanceMeters, accuracy: 0.1)
        XCTAssertEqual(r1.points.count, r2.points.count)
    }

    func testDistinctEndpointsCalculateIndependently() async {
        let router = RoutingService.shared
        await router.clearCache()

        let start = CLLocationCoordinate2D(latitude: 22.5200, longitude: 88.3500)
        let endA = CLLocationCoordinate2D(latitude: 22.5250, longitude: 88.3550)
        let endB = CLLocationCoordinate2D(latitude: 22.5900, longitude: 88.3700)

        async let routeA = router.getWalkingRoute(start: start, destination: endA, destinationName: "Target A")
        async let routeB = router.getWalkingRoute(start: start, destination: endB, destinationName: "Target B")

        let (rA, rB) = await (routeA, routeB)

        XCTAssertNotEqual(rA.distanceMeters, rB.distanceMeters)
    }
}
