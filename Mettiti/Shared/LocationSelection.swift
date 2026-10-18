import Foundation

enum LocationSelection: Codable, Equatable, Sendable {
    case currentLocation
    case custom(name: String, latitude: Double, longitude: Double)
}
