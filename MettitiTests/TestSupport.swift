import Foundation
import Testing
@testable import Mettiti

let pacific = TimeZone(identifier: "America/Los_Angeles")!

func date(_ iso: String) -> Date {
    try! Date(iso, strategy: .iso8601)
}

func gregorianCalendar(in timeZone: TimeZone) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    return calendar
}

extension PlanSnapshot {
    static func generated(at date: Date) -> PlanSnapshot {
        PlanSnapshot(weather: .placeholder, recommendation: .placeholder, generatedAt: date, provider: .apple)
    }

    static func weatherOnly(at date: Date) -> PlanSnapshot {
        PlanSnapshot(weather: .placeholder, recommendation: nil, generatedAt: date, provider: .apple)
    }

    /// A full plan covering `window` from `date`, in Pacific time.
    static func generated(at date: Date, window: PlanWindow) -> PlanSnapshot {
        covering(window, from: date, recommendation: .placeholder)
    }

    /// A weather-only plan covering `window` from `date`, in Pacific time.
    static func weatherOnly(at date: Date, window: PlanWindow) -> PlanSnapshot {
        covering(window, from: date, recommendation: nil)
    }

    private static func covering(_ window: PlanWindow, from date: Date, recommendation: OutfitRecommendation?) -> PlanSnapshot {
        PlanSnapshot(weather: .placeholder, recommendation: recommendation, generatedAt: date, provider: .apple, span: PlanSpan(window: window, startingAt: date, timeZone: pacific))
    }
}

/// A throwaway defaults suite so preference tests never touch the app's real settings.
func isolatedDefaults() -> UserDefaults {
    UserDefaults(suiteName: "MettitiTests.\(UUID().uuidString)")!
}

private final class FixtureBundleToken {}

/// A hand-made API response in MettitiTests/Fixtures, in the shape the live API returns.
func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle(for: FixtureBundleToken.self).url(forResource: name, withExtension: "json"))
    return try Data(contentsOf: url)
}
