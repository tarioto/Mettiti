import CoreLocation
import MapKit

enum PlaceNameLookup {
    /// The city at `coordinate`, such as "Bangkok", or nil if there's none to be found.
    static func cityName(at coordinate: CLLocationCoordinate2D) async -> String? {
        guard let request = MKReverseGeocodingRequest(location: CLLocation(coordinate)),
              let mapItem = try? await request.mapItems.first else { return nil }
        return mapItem.addressRepresentations?.cityName ?? mapItem.address?.shortAddress
    }
}
