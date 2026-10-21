import CoreLocation
import Foundation

/// Einmalige Standortabfrage – nur wenn ATLAS den Standort für eine Antwort braucht.
@MainActor
final class LocationService: NSObject {
    static let shared = LocationService()

    private let manager = CLLocationManager()
    private var authorizationContinuation: CheckedContinuation<Void, Never>?
    private var locationContinuation: CheckedContinuation<CLLocation?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var authorized: Bool {
        switch manager.authorizationStatus {
        case .authorizedAlways: return true
        #if os(iOS)
        case .authorizedWhenInUse: return true
        #endif
        default: return false
        }
    }

    var notDetermined: Bool { manager.authorizationStatus == .notDetermined }

    func requestAccess() async -> Bool {
        if authorized { return true }
        guard notDetermined else { return false }
        await withCheckedContinuation { continuation in
            authorizationContinuation = continuation
            #if os(iOS)
            manager.requestWhenInUseAuthorization()
            #else
            manager.requestAlwaysAuthorization()
            #endif
        }
        return authorized
    }

    /// Liefert eine lesbare Beschreibung des aktuellen Standorts.
    func currentPlaceDescription() async -> String? {
        guard await requestAccess() else { return nil }
        let location: CLLocation? = await withCheckedContinuation { continuation in
            locationContinuation?.resume(returning: nil)
            locationContinuation = continuation
            manager.requestLocation()
        }
        guard let location else { return nil }

        let coordinate = String(format: "%.4f, %.4f", location.coordinate.latitude, location.coordinate.longitude)
        if let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first {
            let parts = [placemark.thoroughfare.map { street in
                             [street, placemark.subThoroughfare].compactMap { $0 }.joined(separator: " ")
                         },
                         [placemark.postalCode, placemark.locality].compactMap { $0 }.joined(separator: " "),
                         placemark.country]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
            return parts.joined(separator: ", ") + " (Koordinaten \(coordinate))"
        }
        return "Koordinaten \(coordinate)"
    }

    fileprivate func finishAuthorization() {
        authorizationContinuation?.resume()
        authorizationContinuation = nil
    }

    fileprivate func finishLocation(_ location: CLLocation?) {
        locationContinuation?.resume(returning: location)
        locationContinuation = nil
    }
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        guard status != .notDetermined else { return }
        Task { @MainActor in self.finishAuthorization() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations.last
        Task { @MainActor in self.finishLocation(location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finishLocation(nil) }
    }
}
