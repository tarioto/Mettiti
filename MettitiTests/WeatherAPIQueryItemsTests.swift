import CoreLocation
import Foundation
import Testing
@testable import Mettiti

struct WeatherAPIQueryItemsTests {
    @Test func sendsCoordinatesRoundedToTwoDecimalPlaces() {
        let coordinate = CLLocationCoordinate2D(latitude: 47.606209123, longitude: -122.332069876)

        #expect(coordinate.weatherAPIQueryItems == [
            URLQueryItem(name: "latitude", value: "47.61"),
            URLQueryItem(name: "longitude", value: "-122.33"),
        ])
    }

    @Test func sendsTheSameValueForTinyNegativeAndPositiveOffsetsFromZero() {
        let coordinate = CLLocationCoordinate2D(latitude: -0.001, longitude: 0.004)

        #expect(coordinate.weatherAPIQueryItems == [
            URLQueryItem(name: "latitude", value: "0.0"),
            URLQueryItem(name: "longitude", value: "0.0"),
        ])
    }
}
