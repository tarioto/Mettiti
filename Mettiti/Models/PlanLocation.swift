import CoreLocation

/// Where the plan on screen is for, as the Location card shows it.
struct PlanLocation: Equatable, Sendable {
    /// The city's name; nil while Current Location's is being looked up, or when it couldn't be.
    var name: String?
    var latitude: Double
    var longitude: Double
    var isCurrentLocation: Bool

    init(name: String?, coordinate: CLLocationCoordinate2D, isCurrentLocation: Bool) {
        self.name = name
        latitude = coordinate.latitude
        longitude = coordinate.longitude
        self.isCurrentLocation = isCurrentLocation
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Within a kilometer, the accuracy GPS fixes are asked for, so a new fix that close keeps
    /// the name already looked up.
    func isNear(_ other: CLLocationCoordinate2D) -> Bool {
        CLLocation(coordinate).distance(from: CLLocation(other)) < 1000
    }
}

extension CLLocation {
    convenience init(_ coordinate: CLLocationCoordinate2D) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}
