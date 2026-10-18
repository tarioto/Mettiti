import CoreLocation
import Foundation

extension CLLocationCoordinate2D {
    /// Latitude and longitude query items for weather API requests, rounded to
    /// 2 decimal places (~1 km). The forecast doesn't need more precision than that.
    var weatherAPIQueryItems: [URLQueryItem] {
        [
            URLQueryItem(name: "latitude", value: Self.reducedPrecision(latitude)),
            URLQueryItem(name: "longitude", value: Self.reducedPrecision(longitude)),
        ]
    }

    private static func reducedPrecision(_ degrees: Double) -> String {
        let rounded = (degrees * 100).rounded() / 100
        // Send -0.0 as 0.0 so both sides of zero share one value.
        return String(rounded == 0 ? 0 : rounded)
    }
}
