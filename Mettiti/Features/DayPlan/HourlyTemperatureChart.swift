import SwiftUI
import Charts

struct HourlyTemperatureChart: View {
    let hourly: HourlyForecast
    @EnvironmentObject private var temperaturePreference: TemperaturePreferenceStore
    @Environment(\.colorScheme) private var colorScheme

    private static let halfHour: TimeInterval = 1800
    private static let hour: TimeInterval = 3600

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
        LinearGradient(colors: HeatPalette.stops, startPoint: .bottom, endPoint: .top)
    }

    /// The first and last hours padded by half an hour, so their bars aren't clipped.
    private var timeDomain: ClosedRange<Date> {
        guard let first = hourly.points.first?.date, let last = hourly.points.last?.date else {
            return Date.now...Date.now.addingTimeInterval(Self.hour)
        }
        return first.addingTimeInterval(-Self.halfHour)...last.addingTimeInterval(Self.halfHour)
    }

    var body: some View {
        // Computed once per body rather than per mark.
        let scale = HourlyChartScale(
            points: hourly.points,
            unit: temperaturePreference.unit.resolved(),
            palette: colorScheme == .dark ? .dark : .light
        )
        let hourFormat = hourly.hourFormat

        VStack(alignment: .leading, spacing: 4) {
            Chart {
                ForEach(hourly.points) { point in
                    hourMarks(for: point, scale: scale, hourFormat: hourFormat)
                }

                if let currentPoint {
                    currentHourMarks(for: currentPoint, scale: scale)
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
                        // Charts starts each date label at its gridline; with no extra spacing the
                        // label lines up with the line, and the first one stays inside the plot.
                        AxisValueLabel(horizontalSpacing: 0) {
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
    private func hourMarks(for point: HourlyTemperaturePoint, scale: HourlyChartScale, hourFormat: Date.FormatStyle) -> some ChartContent {
        let barHalfWidth = Self.halfHour * Self.barWidthFraction
        let hourLabel = point.date.formatted(hourFormat)
        let precipitation = point.precipitationProbability ?? 0

        RectangleMark(
            xStart: .value("Time", point.date.addingTimeInterval(-barHalfWidth)),
            xEnd: .value("Time", point.date.addingTimeInterval(barHalfWidth)),
            yStart: .value("RainBase", scale.range.lowerBound),
            yEnd: .value("Rain", scale.precipitationBarValue(precipitation))
        )
        .foregroundStyle(.blue.opacity(0.18))
        .cornerRadius(2)
        .accessibilityLabel(Text("Chance of rain at \(hourLabel)", comment: "VoiceOver label for an hour's rain bar in the hourly chart; the argument is the hour, e.g. 3 PM"))
        .accessibilityValue(Text((Double(precipitation) / 100).formatted(.percent.precision(.fractionLength(0)))))

        // The band repeats the line's hours, so VoiceOver reads just the line.
        AreaMark(
            x: .value("Time", point.date),
            yStart: .value("Low", scale.unit.convert(fromFahrenheit: point.minF)),
            yEnd: .value("High", scale.unit.convert(fromFahrenheit: point.maxF))
        )
        .foregroundStyle(heatGradient.opacity(0.15))
        .interpolationMethod(.catmullRom)
        .accessibilityHidden(true)

        LineMark(
            x: .value("Time", point.date),
            y: .value("Temperature", scale.unit.convert(fromFahrenheit: point.meanF))
        )
        .foregroundStyle(heatGradient)
        .interpolationMethod(.catmullRom)
        .lineStyle(StrokeStyle(lineWidth: 2))
        // The x value is a Date, which VoiceOver would read in the device's time zone.
        .accessibilityLabel(Text(hourLabel))
        .accessibilityValue(Text(scale.unit.formatted(fahrenheit: point.meanF)))
    }

    @ChartContentBuilder
    private func currentHourMarks(for point: HourlyTemperaturePoint, scale: HourlyChartScale) -> some ChartContent {
        let value = scale.unit.convert(fromFahrenheit: point.meanF)
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
            Text(scale.unit.formatted(fahrenheit: point.meanF))
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(color, in: Capsule())
        }
    }
}

/// The y-axis range, the resolved temperature unit and everything that depends on them,
/// computed once per body evaluation.
struct HourlyChartScale {
    /// Already resolved, so `.system` isn't looked up again for every mark.
    let unit: TemperatureUnit
    /// The full plotted range, shared by both the temperature line and the rain bars
    /// (bars span 0%...100% across this same range, drawn behind the line).
    let range: ClosedRange<Double>
    private let palette: HeatPalette

    init(points: [HourlyTemperaturePoint], unit: TemperatureUnit, palette: HeatPalette) {
        self.unit = unit
        self.palette = palette
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

    /// The heat colour at `displayedValue`'s height in the range.
    func color(for displayedValue: Double) -> Color {
        palette.color(atFraction: height > 0 ? (displayedValue - range.lowerBound) / height : 0)
    }
}

/// The chart's cold-to-hot colours as plain RGB, so picking one doesn't allocate `UIColor`s.
/// The stops are dynamic system colours, so there's one table per colour scheme.
struct HeatPalette {
    static let stops: [Color] = [.blue, .cyan, .green, .yellow, .orange, .red]

    static let light = HeatPalette(style: .light)
    static let dark = HeatPalette(style: .dark)

    private let components: [(r: Double, g: Double, b: Double)]

    private init(style: UIUserInterfaceStyle) {
        let traits = UITraitCollection(userInterfaceStyle: style)
        components = Self.stops.map { stop in
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            UIColor(stop).resolvedColor(with: traits).getRed(&r, green: &g, blue: &b, alpha: &a)
            return (Double(r), Double(g), Double(b))
        }
    }

    /// The colour `fraction` of the way from the coldest stop (0) to the hottest (1).
    func color(atFraction fraction: Double) -> Color {
        let clamped = min(max(fraction, 0), 1)
        let scaled = clamped * Double(components.count - 1)
        let lowerIndex = Int(scaled)
        let upperIndex = min(lowerIndex + 1, components.count - 1)
        let t = scaled - Double(lowerIndex)
        let from = components[lowerIndex]
        let to = components[upperIndex]
        return Color(
            red: from.r + (to.r - from.r) * t,
            green: from.g + (to.g - from.g) * t,
            blue: from.b + (to.b - from.b) * t
        )
    }
}
