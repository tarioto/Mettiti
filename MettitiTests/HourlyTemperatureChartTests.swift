import Accessibility
import SwiftUI
import Testing
import UIKit
@testable import Mettiti

struct HourlyTemperatureChartTests {
    @Test func heatColoursAreResolvedForEachColourScheme() {
        // The system blue at the cold end is lighter in Dark mode.
        let light = UIColor(HeatPalette.light.color(atFraction: 0))
        let dark = UIColor(HeatPalette.dark.color(atFraction: 0))

        #expect(components(of: light) == components(of: UIColor.systemBlue.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))))
        #expect(components(of: dark) == components(of: UIColor.systemBlue.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))))
        #expect(components(of: light) != components(of: dark))
    }

    @Test func rangeIsInTheDisplayedUnitWithFifteenPercentPadding() {
        let scale = HourlyChartScale(points: [point(minF: 50, maxF: 59), point(minF: 59, maxF: 68)], unit: .celsius, palette: .light)

        // 10...20 °C, padded by 1.5 on each side.
        #expect(abs(scale.range.lowerBound - 8.5) < 0.0001)
        #expect(abs(scale.range.upperBound - 21.5) < 0.0001)
    }

    @Test func rainBarsSpanTheWholeRange() {
        let scale = HourlyChartScale(points: [point(minF: 50, maxF: 68)], unit: .fahrenheit, palette: .light)

        #expect(scale.precipitationBarValue(0) == scale.range.lowerBound)
        #expect(scale.precipitationBarValue(100) == scale.range.upperBound)
    }

    @Test func rainAxisLabelsReadTheChanceAtTheirBarHeight() {
        let scale = HourlyChartScale(points: [point(minF: 50, maxF: 68)], unit: .celsius, palette: .light)

        #expect(normalized(scale.percentageLabel(for: scale.precipitationBarValue(0))) == "0%")
        #expect(normalized(scale.percentageLabel(for: scale.precipitationBarValue(50))) == "50%")
        #expect(normalized(scale.percentageLabel(for: scale.precipitationBarValue(100))) == "100%")
    }

    @Test func audioGraphHasOneDataPointPerHourIndexedFromZero() throws {
        let descriptor = chartDescriptor(points: (0..<5).map { point(hour: $0, meanF: 60) }, unit: .fahrenheit).makeChartDescriptor()

        #expect(descriptor.series.count == 1)
        #expect(descriptor.series[0].dataPoints.count == 5)
        #expect(descriptor.series[0].isContinuous)
        let xAxis = try #require(descriptor.xAxis as? AXNumericDataAxisDescriptor)
        #expect(xAxis.range == 0...4)
    }

    @Test func audioGraphTemperaturesAreInTheDisplayedUnit() throws {
        let chart = chartDescriptor(points: [point(hour: 0, meanF: 50), point(hour: 1, meanF: 68)], unit: .celsius)
        let descriptor = chart.makeChartDescriptor()

        #expect(chart.hours.count == 2)
        #expect(abs(chart.hours[0].temperature - 10) < 0.0001)
        #expect(abs(chart.hours[1].temperature - 20) < 0.0001)

        let yAxis = try #require(descriptor.yAxis)
        #expect(yAxis.range == chart.temperatureRange)
        // Each hour reads the same as its mark, and so does any value in between.
        #expect(yAxis.valueDescriptionProvider(chart.hours[0].temperature) == TemperatureUnit.celsius.formatted(fahrenheit: 50, locale: Self.enUS))
        #expect(yAxis.valueDescriptionProvider(15) == TemperatureUnit.celsius.formatted(fahrenheit: 59, locale: Self.enUS))
    }

    @Test func audioGraphCarriesEachHoursChanceOfRain() throws {
        let chart = chartDescriptor(points: [point(hour: 0, meanF: 60, precipitationProbability: 40), point(hour: 1, meanF: 60)], unit: .fahrenheit)
        let descriptor = chart.makeChartDescriptor()

        #expect(chart.hours.map(\.precipitationProbability) == [40, 0])
        let rainAxis = try #require(descriptor.additionalAxes.first as? AXNumericDataAxisDescriptor)
        #expect(rainAxis.range == 0...100)
        #expect(rainAxis.valueDescriptionProvider(40) == "40%")
    }

    @Test func audioGraphHoursAreReadAsTheForecastsHourLabels() throws {
        // Berlin's clocks go from 03:00 CEST back to 02:00 CET, so two hours read "2 AM".
        let berlin = try #require(TimeZone(identifier: "Europe/Berlin"))
        let start = try Date("2026-10-25T00:00:00Z", strategy: .iso8601)
        let points = (0..<3).map { point(at: start.addingTimeInterval(Double($0) * 3600), meanF: 60) }
        let style = HourlyForecast(timeZone: berlin, points: points).hourFormat.locale(Self.enUS)
        let descriptor = chartDescriptor(points: points, unit: .fahrenheit, hourFormat: style).makeChartDescriptor()

        let xAxis = try #require(descriptor.xAxis as? AXNumericDataAxisDescriptor)
        let labels = (0..<3).map { normalized(xAxis.valueDescriptionProvider(Double($0))) }
        #expect(labels == ["2 AM", "2 AM", "3 AM"])
        #expect(descriptor.series[0].dataPoints.count == 3)
    }

    @Test func audioGraphSummaryGivesTheHighAndLowAndTheirHours() throws {
        let points = [point(hour: 0, meanF: 60), point(hour: 1, meanF: 55), point(hour: 2, meanF: 72), point(hour: 3, meanF: 72)]
        let descriptor = chartDescriptor(points: points, unit: .fahrenheit).makeChartDescriptor()

        let summary = normalized(try #require(descriptor.summary))
        // Ties go to the first hour to reach the high.
        let highHour = normalized(points[2].date.formatted(hourFormat))
        let lowHour = normalized(points[1].date.formatted(hourFormat))
        #expect(summary == "High 72° at \(highHour), low 55° at \(lowHour)")
        #expect(descriptor.title == "Hourly forecast")
    }

    @Test func audioGraphSummaryNamesTheShadedPlanWindow() throws {
        let points = [point(hour: 0, meanF: 60), point(hour: 1, meanF: 55)]
        let span = PlanSpan(window: .threeHours, startingAt: date("2026-10-09T21:20:00Z"), timeZone: pacific)
        let descriptor = chartDescriptor(points: points, unit: .fahrenheit, span: span).makeChartDescriptor()

        let summary = normalized(try #require(descriptor.summary))
        #expect(summary.hasSuffix(". Shaded: Next 3 hours, from 2:20 PM to 5:20 PM"))
    }

    @Test func audioGraphSummaryLeavesOutAPlanWindowTheChartDoesntShow() throws {
        let points = [point(hour: 0, meanF: 60), point(hour: 1, meanF: 55)]
        // The day before the chart's hours.
        let span = PlanSpan(window: .threeHours, startingAt: date("2026-10-08T21:20:00Z"), timeZone: pacific)
        let descriptor = chartDescriptor(points: points, unit: .fahrenheit, span: span).makeChartDescriptor()

        let summary = try #require(descriptor.summary)
        #expect(!summary.contains("Shaded"))
    }

    @Test func audioGraphWithNoHoursIsEmpty() throws {
        let descriptor = chartDescriptor(points: [], unit: .celsius).makeChartDescriptor()

        #expect(descriptor.series[0].dataPoints.isEmpty)
        #expect(descriptor.summary == nil)
        let xAxis = try #require(descriptor.xAxis as? AXNumericDataAxisDescriptor)
        #expect(xAxis.range == 0...0)
        #expect(xAxis.valueDescriptionProvider(0) == "")
    }

    private static let enUS = Locale(identifier: "en_US")

    private var hourFormat: Date.FormatStyle {
        HourlyForecast(timeZone: TimeZone(identifier: "America/Los_Angeles")!, points: []).hourFormat.locale(Self.enUS)
    }

    private func chartDescriptor(points: [HourlyTemperaturePoint], unit: TemperatureUnit, hourFormat: Date.FormatStyle? = nil, span: PlanSpan? = nil) -> HourlyChartDescriptor {
        HourlyChartDescriptor(
            points: points,
            hourFormat: hourFormat ?? self.hourFormat,
            scale: HourlyChartScale(points: points, unit: unit, palette: .light),
            span: span,
            locale: Self.enUS
        )
    }

    private func point(hour: Int, meanF: Double, precipitationProbability: Int? = nil) -> HourlyTemperaturePoint {
        point(at: Date(timeIntervalSince1970: 1_791_590_400 + Double(hour) * 3600), meanF: meanF, precipitationProbability: precipitationProbability)
    }

    private func point(at date: Date, meanF: Double, precipitationProbability: Int? = nil) -> HourlyTemperaturePoint {
        HourlyTemperaturePoint(date: date, meanF: meanF, minF: meanF - 2, maxF: meanF + 2, precipitationProbability: precipitationProbability)
    }

    /// Hour labels separate the number and "AM"/"PM" with a narrow no-break space.
    private func normalized(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{202F}", with: " ")
    }

    private func point(minF: Double, maxF: Double) -> HourlyTemperaturePoint {
        HourlyTemperaturePoint(date: .now, meanF: (minF + maxF) / 2, minF: minF, maxF: maxF, precipitationProbability: nil)
    }

    private func components(of color: UIColor) -> [Double] {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        // Rounded so tiny colour-space round trips don't count as differences.
        return [r, g, b].map { (Double($0) * 1000).rounded() / 1000 }
    }
}
