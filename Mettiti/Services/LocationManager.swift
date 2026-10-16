import CoreLocation
import Combine

/// What `DayPlanViewModel` needs from a location source, so tests can drive it without CoreLocation.
@MainActor
protocol LocationProviding: AnyObject {
    var coordinatePublisher: AnyPublisher<CLLocationCoordinate2D?, Never> { get }
    var errorMessagePublisher: AnyPublisher<String?, Never> { get }
    func requestLocation()
}

@MainActor
final class LocationManager: NSObject, ObservableObject {
    @Published var coordinate: CLLocationCoordinate2D?
    @Published var authorizationStatus: CLAuthorizationStatus
    @Published var errorMessage: String?

    private let manager = CLLocationManager()
    private var unknownLocationRetries = 0
    private static let maxUnknownLocationRetries = 2
    private static let deniedMessage = "Location access is off. Enable it in Settings to get weather for your area."

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func requestLocation() {
        errorMessage = nil
        unknownLocationRetries = 0
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            errorMessage = Self.deniedMessage
        @unknown default:
            break
        }
    }
}

extension LocationManager: LocationProviding {
    var coordinatePublisher: AnyPublisher<CLLocationCoordinate2D?, Never> { $coordinate.eraseToAnyPublisher() }
    var errorMessagePublisher: AnyPublisher<String?, Never> { $errorMessage.eraseToAnyPublisher() }
}

extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            guard let self else { return }
            authorizationStatus = status
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                self.manager.requestLocation()
            } else if status == .denied || status == .restricted {
                errorMessage = Self.deniedMessage
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            coordinate = location.coordinate
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
            errorMessage = Self.deniedMessage
        case .network:
            errorMessage = "Couldn't determine your location. Check your connection and try again."
        default:
            errorMessage = "Couldn't find your location right now. Try again, or set a location in Settings."
        }
    }
}
