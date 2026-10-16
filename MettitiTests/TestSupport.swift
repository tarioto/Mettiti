import Foundation
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
}
