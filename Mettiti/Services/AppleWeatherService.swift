import Foundation
import CoreLocation
import MapKit
import WeatherKit

enum AppleWeatherServiceError: Error, LocalizedError {
    case unavailable
    case missingForecast

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Couldn't reach Apple Weather. Check your connection, or switch to Open-Meteo in Settings."
        case .missingForecast:
            return "Apple Weather didn't return a forecast for today."
        }
    }
}

struct AppleWeatherService {
    func fetchForecast(for coordinate: CLLocationCoordinate2D) async throws -> (daily: DailyWeather, hourly: HourlyForecast) {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        async let timeZoneTask = timeZone(for: location)

        let dailyForecast: Forecast<DayWeather>
        let hourlyForecast: Forecast<HourWeather>
        do {
            (dailyForecast, hourlyForecast) = try await WeatherKit.WeatherService.shared.weather(for: location, including: .daily, .hourly)
        } catch {
            throw AppleWeatherServiceError.unavailable
        }

        let now = Date()
        guard let today = dailyForecast.first(where: { $0.date <= now && now < $0.date.addingTimeInterval(86_400) }) ?? dailyForecast.first else {
            throw AppleWeatherServiceError.missingForecast
        }

        let code = Self.wmoCode(for: today.condition)
        let daily = DailyWeather(
            date: today.date,
            highTemperatureF: today.highTemperature.converted(to: .fahrenheit).value,
            lowTemperatureF: today.lowTemperature.converted(to: .fahrenheit).value,
            precipitationProbability: Int((today.precipitationChance * 100).rounded()),
            uvIndex: Double(today.uvIndex.value),
            windSpeedMph: (today.highWindSpeed ?? today.wind.speed).converted(to: .milesPerHour).value,
            conditionCode: code,
            conditionDescription: today.condition.description
        )

        let timeZone = await timeZoneTask
        let labelFormatter = DateFormatter()
        labelFormatter.dateFormat = "h a"
        labelFormatter.timeZone = timeZone
        labelFormatter.locale = Locale(identifier: "en_US_POSIX")

        // Apple Weather gives a single deterministic value per hour, so min and max equal
        // the mean here. DayPlanViewModel layers Open-Meteo's ensemble spread on top.
        let cutoff = now.addingTimeInterval(-1800)
        let points = hourlyForecast
            .filter { $0.date >= cutoff }
            .prefix(24)
            .map { hour in
                let temperatureF = hour.temperature.converted(to: .fahrenheit).value
                return HourlyTemperaturePoint(
                    date: hour.date,
                    hourLabel: labelFormatter.string(from: hour.date),
                    meanF: temperatureF,
                    minF: temperatureF,
                    maxF: temperatureF,
                    precipitationProbability: Int((hour.precipitationChance * 100).rounded())
                )
            }

        guard !points.isEmpty else { throw AppleWeatherServiceError.missingForecast }

        return (daily, HourlyForecast(timeZone: timeZone, points: Array(points)))
    }

    /// WeatherKit doesn't report the location's time zone, so look it up for custom cities.
    private func timeZone(for location: CLLocation) async -> TimeZone {
        guard
            let request = MKReverseGeocodingRequest(location: location),
            let mapItem = try? await request.mapItems.first,
            let timeZone = mapItem.timeZone
        else {
            return .current
        }
        return timeZone
    }

    /// Maps Apple's conditions onto the WMO codes the rest of the app (and the widgets) use for icons.
    private static func wmoCode(for condition: WeatherCondition) -> Int {
        switch condition {
        case .clear, .hot, .frigid: return 0
        case .mostlyClear, .breezy, .windy: return 1
        case .partlyCloudy: return 2
        case .cloudy, .mostlyCloudy, .haze, .smoky, .blowingDust: return 3
        case .foggy: return 45
        case .drizzle: return 51
        case .freezingDrizzle: return 56
        case .rain, .sunShowers: return 61
        case .heavyRain, .tropicalStorm, .hurricane: return 65
        case .freezingRain, .sleet, .wintryMix, .hail: return 66
        case .flurries, .sunFlurries, .snow: return 71
        case .heavySnow, .blizzard, .blowingSnow: return 75
        case .isolatedThunderstorms, .scatteredThunderstorms, .thunderstorms, .strongStorms: return 95
        @unknown default: return 3
        }
    }
}
