import CoreLocation
import MapKit
import Observation

/// Where the Location card's placeholder map points while there's no location yet: roughly where
/// the device is, without asking for anything new.
@MainActor
enum PlaceholderMapRegion {
    /// About 50 km across, a metro area.
    nonisolated static let cityScaleMeters: CLLocationDistance = 50_000

    /// About 1,000 km across. Geocoding gives a country's centre but not its size, so every
    /// country gets the same span.
    nonisolated static let countryScaleMeters: CLLocationDistance = 1_000_000

    /// In order: the device's last known fix, the Saved Plan's city, then the country of the
    /// device's Region setting. Nil when none of them is known.
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
            countryRegion: { code in await geocodedCountry(code: code) }
        )
    }

    nonisolated static func cityScale(around coordinate: CLLocationCoordinate2D) -> MKCoordinateRegion {
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

    /// The country's centre from geocoding its name, so it needs no location permission.
    private static func geocodedCountry(code: String) async -> MKCoordinateRegion? {
        guard let name = Locale.current.localizedString(forRegionCode: code),
              let request = MKGeocodingRequest(addressString: name),
              let mapItem = try? await request.mapItems.first else { return nil }
        return MKCoordinateRegion(
            center: mapItem.location.coordinate,
            latitudinalMeters: countryScaleMeters,
            longitudinalMeters: countryScaleMeters
        )
    }
}

/// The placeholder region, worked out at most once per launch and shared by every Location card,
/// so a card made by the crossfade from the Skeleton to a plan shows the map straight away.
@MainActor
@Observable
final class PlaceholderMapRegionCache {
    static let device = PlaceholderMapRegionCache(resolve: PlaceholderMapRegion.resolveForDevice)

    /// Nil until the lookup finishes, and after it if nothing was known.
    private(set) var region: MKCoordinateRegion?

    @ObservationIgnored private let resolve: @MainActor () async -> MKCoordinateRegion?
    @ObservationIgnored private var lookup: Task<Void, Never>?

    init(resolve: @escaping @MainActor () async -> MKCoordinateRegion?) {
        self.resolve = resolve
    }

    /// Starts the lookup the first time, then waits for it; later calls share the same lookup.
    func load() async {
        if lookup == nil {
            lookup = Task { region = await resolve() }
        }
        await lookup?.value
    }
}
