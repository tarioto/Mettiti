import CoreLocation
import MapKit

/// Where the plan on screen is for, as the Location card shows it.
struct PlanLocation: Equatable, Sendable {
    /// The city's name; nil while Current Location's is being looked up, or when it couldn't be.
    var name: String?
    var latitude: Double
    var longitude: Double
    var isCurrentLocation: Bool

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Within a kilometer, the accuracy GPS fixes are asked for, so a new fix that close keeps
    /// the name already looked up.
    func isNear(_ other: CLLocationCoordinate2D) -> Bool {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: other.latitude, longitude: other.longitude)) < 1000
    }
}

enum PlaceNameLookup {
    /// The city at `coordinate`, such as "Bangkok", or nil if there's none to be found.
    static func cityName(at coordinate: CLLocationCoordinate2D) async -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let request = MKReverseGeocodingRequest(location: location),
              let mapItem = try? await request.mapItems.first else { return nil }
        return mapItem.addressRepresentations?.cityName ?? mapItem.address?.shortAddress
    }
}
