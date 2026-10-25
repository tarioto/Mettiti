import Foundation

enum LocationSelection: Sendable {
    case currentLocation
    /// `timeZone` is the city's, from geocoding. Nil for cities saved before it was stored.
    case custom(name: String, latitude: Double, longitude: Double, timeZone: TimeZone? = nil)
}

extension LocationSelection {
    /// `calendar` in the selection's time zone: the city's, or `calendar`'s own (the device's) for
    /// Current Location and for cities saved without one.
    func calendar(fallback calendar: Calendar) -> Calendar {
        guard case .custom(_, _, _, let timeZone?) = self else { return calendar }
        var selectionCalendar = calendar
        selectionCalendar.timeZone = timeZone
        return selectionCalendar
    }
}

/// The time zone isn't part of equality: a city saved before it was stored is still the same
/// location, so its saved plans keep showing.
extension LocationSelection: Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.currentLocation, .currentLocation):
            true
        case (.custom(let lName, let lLat, let lLon, _), .custom(let rName, let rLat, let rLon, _)):
            lName == rName && lLat == rLat && lLon == rLon
        default:
            false
        }
    }
}

/// Same shape as the synthesized coding, so earlier saves still decode; the time zone is stored as
/// its identifier and ignored when missing or unknown.
extension LocationSelection: Codable {
    private enum CodingKeys: String, CodingKey { case currentLocation, custom }
    private enum CustomKeys: String, CodingKey { case name, latitude, longitude, timeZone }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.custom) {
            let custom = try container.nestedContainer(keyedBy: CustomKeys.self, forKey: .custom)
            let identifier = try? custom.decodeIfPresent(String.self, forKey: .timeZone)
            self = .custom(
                name: try custom.decode(String.self, forKey: .name),
                latitude: try custom.decode(Double.self, forKey: .latitude),
                longitude: try custom.decode(Double.self, forKey: .longitude),
                timeZone: identifier.flatMap { TimeZone(identifier: $0) }
            )
        } else if container.contains(.currentLocation) {
            self = .currentLocation
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown location selection"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .currentLocation:
            _ = container.nestedContainer(keyedBy: CustomKeys.self, forKey: .currentLocation)
        case .custom(let name, let latitude, let longitude, let timeZone):
            var custom = container.nestedContainer(keyedBy: CustomKeys.self, forKey: .custom)
            try custom.encode(name, forKey: .name)
            try custom.encode(latitude, forKey: .latitude)
            try custom.encode(longitude, forKey: .longitude)
            try custom.encodeIfPresent(timeZone?.identifier, forKey: .timeZone)
        }
    }
}
