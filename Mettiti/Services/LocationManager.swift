import CoreLocation

/// What `DayPlanViewModel` needs from a location source, so tests can drive it without CoreLocation.
@MainActor
protocol LocationProviding: AnyObject {
    /// Called with each fix.
    var onCoordinate: ((CLLocationCoordinate2D) -> Void)? { get set }
    /// Called with a message to show when there's no fix to be had.
    var onError: ((String) -> Void)? { get set }
    func requestLocation()
}

/// Not `@Observable`: no view reads its state, so it reports fixes and failures through callbacks.
@MainActor
final class LocationManager: NSObject, LocationProviding {
    var onCoordinate: ((CLLocationCoordinate2D) -> Void)?
    var onError: ((String) -> Void)?

    private let manager = CLLocationManager()
    private var unknownLocationRetries = 0
    private static let maxUnknownLocationRetries = 2
    private static var deniedMessage: String { String(localized: "Location access is off. Enable it in Settings to get weather for your area.") }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func requestLocation() {
        unknownLocationRetries = 0
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            onError?(Self.deniedMessage)
        @unknown default:
            break
        }
    }
}

extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            guard let self else { return }
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                self.manager.requestLocation()
            } else if status == .denied || status == .restricted {
                onError?(Self.deniedMessage)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            onCoordinate?(location.coordinate)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let code = (error as? CLError)?.code
        Task { @MainActor in
            handleFailure(code: code)
        }
    }
}

private extension LocationManager {
    func handleFailure(code: CLError.Code?) {
        // locationUnknown is usually transient (no fix yet), so try again before giving up.
        if code == .locationUnknown, unknownLocationRetries < Self.maxUnknownLocationRetries {
            unknownLocationRetries += 1
            Task {
                try? await Task.sleep(for: .seconds(2))
                manager.requestLocation()
            }
            return
        }

        switch code {
        case .denied:
            onError?(Self.deniedMessage)
        case .network:
            onError?(String(localized: "Couldn't determine your location. Check your connection and try again."))
        default:
            onError?(String(localized: "Couldn't find your location right now. Try again, or set a location in Settings."))
        }
    }
}
