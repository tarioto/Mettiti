import SwiftUI
import Charts

struct HourlyTemperatureChart: View {
    let hourly: HourlyForecast
    @EnvironmentObject private var temperaturePreference: TemperaturePreferenceStore

    private static let heatStops: [Color] = [.blue, .cyan, .green, .yellow, .orange, .red]

    /// `heatStops` as RGB, resolved once so picking a colour doesn't allocate `UIColor`s.
    private static let heatStopComponents: [(r: Double, g: Double, b: Double)] = heatStops.map { stop in
        let components = UIColor(stop).rgbaComponents
        return (Double(components.r), Double(components.g), Double(components.b))
    }

    /// Each bar spans this share of its hour, centred on the hour it covers.
    private static let barWidthFraction = 0.6

    private var currentPoint: HourlyTemperaturePoint? {
        hourly.points.min { abs($0.date.timeIntervalSinceNow) < abs($1.date.timeIntervalSinceNow) }
    }

    /// True when the points carry an ensemble min/max spread (from Open-Meteo, including when layered onto Apple Weather).
    private var hasSpread: Bool {
        hourly.points.contains { $0.maxF > $0.minF }
    }

    private var heatGradient: LinearGradient {
        LinearGradient(colors: Self.heatStops, startPoint: .bottom, endPoint: .top)
    }

    /// The first and last hours padded by half an hour, so their bars aren't clipped.
    private var timeDomain: ClosedRange<Date> {
        guard let first = hourly.points.first?.date, let last = hourly.points.last?.date else {
            return Date.now...Date.now.addingTimeInterval(3600)
        }
        return first.addingTimeInterval(-1800)...last.addingTimeInterval(1800)
    }

    var body: some View {
        // Computed once per body rather than per mark.
        let unit = temperaturePreference.unit.resolved()
        let scale = ChartScale(points: hourly.points, unit: unit)
        let hourFormat = hourly.hourFormat

        VStack(alignment: .leading, spacing: 4) {
            Chart {
                ForEach(hourly.points) { point in
                    hourMarks(for: point, unit: unit, scale: scale)
                }

                if let currentPoint {
                    currentHourMarks(for: currentPoint, unit: unit, scale: scale)
                }
            }
            .chartXScale(domain: timeDomain)
            .chartYScale(domain: scale.range)
            .chartXAxis {
                // Labelled from the forecast's own hours, formatted in its time zone, so on a
                // fall-back day both "1 AM"s keep their own place on the axis.
                AxisMarks(values: hourly.axisDates) { value in
                    AxisGridLine()
                    if let date = value.as(Date.self) {
                        AxisValueLabel {
                            Text(date.formatted(hourFormat))
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading)
                AxisMarks(
                    position: .trailing,
                    values: [
                        scale.precipitationBarValue(0),
                        scale.precipitationBarValue(50),
                        scale.precipitationBarValue(100)
                    ]
                ) { value in
                    if let raw = value.as(Double.self) {
                        AxisValueLabel {
                            Text(scale.percentageLabel(for: raw))
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }
            .frame(height: 124)

            Text(hasSpread ? "Shaded band shows model spread · bars show chance of rain" : "Bars show chance of rain")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ChartContentBuilder
    private func hourMarks(for point: HourlyTemperaturePoint, unit: TemperatureUnit, scale: ChartScale) -> some ChartContent {
        let barHalfWidth = 1800 * Self.barWidthFraction

        RectangleMark(
            xStart: .value("Time", point.date.addingTimeInterval(-barHalfWidth)),
            xEnd: .value("Time", point.date.addingTimeInterval(barHalfWidth)),
            yStart: .value("RainBase", scale.range.lowerBound),
            yEnd: .value("Rain", scale.precipitationBarValue(point.precipitationProbability ?? 0))
        )
        .foregroundStyle(.blue.opacity(0.18))
        .cornerRadius(2)

        AreaMark(
            x: .value("Time", point.date),
            yStart: .value("Low", unit.convert(fromFahrenheit: point.minF)),
            yEnd: .value("High", unit.convert(fromFahrenheit: point.maxF))
        )
        .foregroundStyle(heatGradient.opacity(0.15))
        .interpolationMethod(.catmullRom)

        LineMark(
            x: .value("Time", point.date),
            y: .value("Temperature", unit.convert(fromFahrenheit: point.meanF))
        )
        .foregroundStyle(heatGradient)
        .interpolationMethod(.catmullRom)
        .lineStyle(StrokeStyle(lineWidth: 2))
    }

    @ChartContentBuilder
    private func currentHourMarks(for point: HourlyTemperaturePoint, unit: TemperatureUnit, scale: ChartScale) -> some ChartContent {
        let value = unit.convert(fromFahrenheit: point.meanF)
        let color = scale.color(for: value)

        RuleMark(x: .value("Time", point.date))
            .foregroundStyle(.secondary.opacity(0.4))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

        PointMark(
            x: .value("Time", point.date),
            y: .value("Current Temperature", value)
        )
        .foregroundStyle(color)
        .symbolSize(90)
        .annotation(
            position: .top,
            overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
        ) {
            Text(temperaturePreference.unit.formatted(fahrenheit: point.meanF))
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(color, in: Capsule())
        }
    }

    /// The y-axis range and what depends on it, computed once per body evaluation.
    private struct ChartScale {
        /// The full plotted range, shared by both the temperature line and the rain bars
        /// (bars span 0%...100% across this same range, drawn behind the line).
        let range: ClosedRange<Double>

        init(points: [HourlyTemperaturePoint], unit: TemperatureUnit) {
            let values = points.flatMap { [unit.convert(fromFahrenheit: $0.minF), unit.convert(fromFahrenheit: $0.maxF)] }
            let minValue = values.min() ?? 0
            let maxValue = values.max() ?? 100
            if maxValue > minValue {
                let padding = (maxValue - minValue) * 0.15
                range = (minValue - padding)...(maxValue + padding)
            } else {
                range = (minValue - 1)...(maxValue + 1)
            }
        }

        private var height: Double { range.upperBound - range.lowerBound }

        func precipitationBarValue(_ probability: Int) -> Double {
            range.lowerBound + (Double(probability) / 100.0) * height
        }

        func percentageLabel(for rawValue: Double) -> String {
            let fraction = height > 0 ? (rawValue - range.lowerBound) / height : 0
            return fraction.formatted(.percent.precision(.fractionLength(0)))
        }

        func color(for displayedValue: Double) -> Color {
            guard height > 0 else { return HourlyTemperatureChart.heatStops.first ?? .accentColor }
            return HourlyTemperatureChart.interpolatedColor(fraction: (displayedValue - range.lowerBound) / height)
        }
    }

    private static func interpolatedColor(fraction: Double) -> Color {
        let clamped = min(max(fraction, 0), 1)
        let scaled = clamped * Double(heatStopComponents.count - 1)
        let lowerIndex = Int(scaled)
        let upperIndex = min(lowerIndex + 1, heatStopComponents.count - 1)
        let t = scaled - Double(lowerIndex)
        let from = heatStopComponents[lowerIndex]
        let to = heatStopComponents[upperIndex]
        return Color(
            red: from.r + (to.r - from.r) * t,
            green: from.g + (to.g - from.g) * t,
            blue: from.b + (to.b - from.b) * t
        )
    }
}

private extension UIColor {
    var rgbaComponents: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b, a)
    }
}
