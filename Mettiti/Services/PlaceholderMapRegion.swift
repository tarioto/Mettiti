import CoreLocation
import MapKit

/// Where the Location card's placeholder map points while there's no location yet: roughly where
/// the device is, without asking for anything new.
enum PlaceholderMapRegion {
    /// About 50 km across, a metro area.
    static let cityScaleMeters: CLLocationDistance = 50_000

    /// In order: the device's last known fix, the Saved Plan's city, then the country of the
    /// device's Region setting, zoomed to fit. Nil when none of them is known.
    static func resolve(
        lastFix: CLLocationCoordinate2D?,
        savedPlan: LocationSelection?,
        countryCode: String?,
        countryRegion: (String) async -> MKCoordinateRegion?
    ) async -> MKCoordinateRegion? {
        if let lastFix {
            return cityScale(around: lastFix)
        }
        if case .custom(_, let latitude, let longitude, _)? = savedPlan {
            return cityScale(around: CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
        }
        guard let countryCode else { return nil }
        return await countryRegion(countryCode)
    }

    /// The real sources: the system's cached fix (only if location access is already granted), the
    /// Saved Plan, and the Region setting.
    static func resolveForDevice() async -> MKCoordinateRegion? {
        await resolve(
            lastFix: cachedFix(),
            savedPlan: SharedStore.load()?.location,
            countryCode: Locale.current.region?.identifier,
            countryRegion: geocodedCountry
        )
    }

    static func cityScale(around coordinate: CLLocationCoordinate2D) -> MKCoordinateRegion {
        MKCoordinateRegion(center: coordinate, latitudinalMeters: cityScaleMeters, longitudinalMeters: cityScaleMeters)
    }

    private static func cachedFix() -> CLLocationCoordinate2D? {
        let manager = CLLocationManager()
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return manager.location?.coordinate
        default:
            return nil
        }
    }

    /// The country's bounds from geocoding its name, so it needs no location permission.
    private static func geocodedCountry(code: String) async -> MKCoordinateRegion? {
        guard let name = Locale.current.localizedString(forRegionCode: code) else { return nil }
        let placemarks = try? await CLGeocoder().geocodeAddressString(name)
        guard let circle = placemarks?.first?.region as? CLCircularRegion else { return nil }
        let diameter = circle.radius * 2
        return MKCoordinateRegion(center: circle.center, latitudinalMeters: diameter, longitudinalMeters: diameter)
    }
}
