// Services/LocationService.swift — CLLocationManager wrapper (foreground whenInUse)

import Foundation
import CoreLocation
import Observation

@MainActor
@Observable
final class LocationService: NSObject {
    static let shared = LocationService()

    private let manager = CLLocationManager()
    private(set) var lastCoordinate: CLLocationCoordinate2D?
    private(set) var lastLocation: CLLocation?
    private(set) var lastAccuracyMeters: Double?
    private(set) var lastLocationTimestamp: Date?
    private(set) var lastHeading: Double = 0
    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    private(set) var isTracking = false
    var onUpdate: ((CLLocationCoordinate2D) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.activityType = .fitness
        authorizationStatus = manager.authorizationStatus
    }

    func requestPermission() {
        if authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    func startLiveTracking() {
        requestPermission()
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
            if CLLocationManager.headingAvailable() {
                manager.startUpdatingHeading()
            }
            isTracking = true
        }
    }

    func stopLiveTracking() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
        isTracking = false
    }

    /// Returns true if the latest GPS fix is strictly fresh (<= maxAge, default 10s)
    /// and accurate (<= maxAccuracy, default 30m), rejecting noise and jitter.
    func isFixValid(maxAge: TimeInterval = 10.0, maxAccuracy: Double = 30.0) -> Bool {
        Self.isLocationValid(lastLocation, maxAge: maxAge, maxAccuracy: maxAccuracy)
    }

    /// Validates whether a CLLocation satisfies strict trail progress requirements.
    nonisolated static func isLocationValid(_ location: CLLocation?, maxAge: TimeInterval = 10.0, maxAccuracy: Double = 30.0) -> Bool {
        guard let location = location else { return false }
        guard location.horizontalAccuracy >= 0 && location.horizontalAccuracy <= maxAccuracy else {
            return false
        }
        let age = abs(location.timestamp.timeIntervalSinceNow)
        return age <= maxAge
    }

    /// Determines if the current coordinate represents a genuine spatial displacement from a baseline.
    func hasMeaningfulDisplacement(from previous: CLLocationCoordinate2D?, thresholdMeters: Double = 20.0) -> Bool {
        guard let current = lastCoordinate else { return false }
        guard let prev = previous else { return true }
        return haversineMeters(current, prev) >= thresholdMeters
    }

    /// Returns the most recent coordinate, or nil if unavailable.
    func currentPosition() -> CLLocationCoordinate2D? { lastCoordinate }
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in self.authorizationStatus = status }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            self.lastLocation = loc
            self.lastCoordinate = loc.coordinate
            self.lastAccuracyMeters = loc.horizontalAccuracy
            self.lastLocationTimestamp = loc.timestamp
            self.onUpdate?(loc.coordinate)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let h = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        Task { @MainActor in self.lastHeading = h }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Permission denied / disabled — non-fatal in demo mode.
    }
}
