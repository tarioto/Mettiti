import SwiftUI
import Charts

struct HourlyTemperatureChart: View {
    let hourly: HourlyForecast
    @EnvironmentObject private var temperaturePreference: TemperaturePreferenceStore

    private static let heatStops: [Color] = [.blue, .cyan, .green, .yellow, .orange, .red]

    private var currentPoint: HourlyTemperaturePoint? {
        hourly.points.min { abs($0.date.timeIntervalSinceNow) < abs($1.date.timeIntervalSinceNow) }
    }

    /// The full plotted range, shared by both the temperature line and the rain bars
    /// (bars span 0%...100% across this same range, drawn behind the line).
    private var displayedRange: ClosedRange<Double> {
        let values = hourly.points.flatMap { [convert($0.minF), convert($0.maxF)] }
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 100
        guard maxValue > minValue else { return (minValue - 1)...(maxValue + 1) }
        let padding = (maxValue - minValue) * 0.15
        return (minValue - padding)...(maxValue + padding)
    }

    /// True when the points carry an ensemble min/max spread (from Open-Meteo, including when layered onto Apple Weather).
    private var hasSpread: Bool {
        hourly.points.contains { $0.maxF > $0.minF }
    }

    private var heatGradient: LinearGradient {
        LinearGradient(colors: Self.heatStops, startPoint: .bottom, endPoint: .top)
    }

    private func precipitationBarValue(_ probability: Int) -> Double {
        let range = displayedRange
        let height = range.upperBound - range.lowerBound
        return range.lowerBound + (Double(probability) / 100.0) * height
    }

    private func percentageLabel(for rawValue: Double) -> String {
        let range = displayedRange
        let height = range.upperBound - range.lowerBound
        guard height > 0 else { return "0%" }
        let fraction = (rawValue - range.lowerBound) / height
        return "\(Int((fraction * 100).rounded()))%"
    }

    /// Exactly 4 evenly-spaced hour labels, rendered manually below the chart.
    /// (Swift Charts' AxisMarks tick-thinning is unreliable for a categorical/String
    /// x-axis once a BarMark is present, so we don't rely on it for label text.)
    private var sampledLabels: [String] {
        guard !hourly.points.isEmpty else { return [] }
        let count = hourly.points.count
        let indices = [0, count / 4, count / 2, (count * 3) / 4]
        return indices.map { hourly.points[min($0, count - 1)].hourLabel }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Chart {
                ForEach(hourly.points) { point in
                    BarMark(
                        x: .value("Time", point.hourLabel),
                        yStart: .value("RainBase", displayedRange.lowerBound),
                        yEnd: .value("Rain", precipitationBarValue(point.precipitationProbability)),
                        width: .ratio(0.6)
                    )
                    .foregroundStyle(.blue.opacity(0.18))
                    .cornerRadius(2)

                    AreaMark(
                        x: .value("Time", point.hourLabel),
                        yStart: .value("Low", convert(point.minF)),
                        yEnd: .value("High", convert(point.maxF))
                    )
                    .foregroundStyle(heatGradient.opacity(0.15))
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("Time", point.hourLabel),
                        y: .value("Temperature", convert(point.meanF))
                    )
                    .foregroundStyle(heatGradient)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }

                if let currentPoint {
                    RuleMark(x: .value("Time", currentPoint.hourLabel))
                        .foregroundStyle(.secondary.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

                    PointMark(
                        x: .value("Time", currentPoint.hourLabel),
                        y: .value("Current Temperature", convert(currentPoint.meanF))
                    )
                    .foregroundStyle(color(for: convert(currentPoint.meanF)))
                    .symbolSize(90)
                    .annotation(
                        position: .top,
                        overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                    ) {
                        Text(temperaturePreference.unit.displayString(fromFahrenheit: currentPoint.meanF))
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(color(for: convert(currentPoint.meanF)), in: Capsule())
                    }
                }
            }
            .chartYScale(domain: displayedRange)
            .chartXAxis {
                AxisMarks(values: .automatic) { _ in
                    AxisGridLine()
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading)
                AxisMarks(
                    position: .trailing,
                    values: [
                        precipitationBarValue(0),
                        precipitationBarValue(50),
                        precipitationBarValue(100)
                    ]
                ) { value in
                    if let raw = value.as(Double.self) {
                        AxisValueLabel {
                            Text(percentageLabel(for: raw))
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }
            .frame(height: 110)

            HStack {
                ForEach(Array(sampledLabels.enumerated()), id: \.offset) { index, label in
                    Text(label)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    if index < sampledLabels.count - 1 {
                        Spacer()
                    }
                }
            }

            Text(hasSpread ? "Shaded band shows model spread · bars show chance of rain" : "Bars show chance of rain")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func convert(_ fahrenheit: Double) -> Double {
        temperaturePreference.unit.convert(fromFahrenheit: fahrenheit)
    }

    private func color(for displayedValue: Double) -> Color {
        let range = displayedRange
        guard range.upperBound > range.lowerBound else { return Self.heatStops.first ?? .accentColor }
        let fraction = (displayedValue - range.lowerBound) / (range.upperBound - range.lowerBound)
        return Self.interpolatedColor(fraction: fraction)
    }

    private static func interpolatedColor(fraction: Double) -> Color {
        let clamped = min(max(fraction, 0), 1)
        let scaled = clamped * Double(heatStops.count - 1)
        let lowerIndex = Int(scaled)
        let upperIndex = min(lowerIndex + 1, heatStops.count - 1)
        let localFraction = scaled - Double(lowerIndex)
        return lerp(heatStops[lowerIndex], heatStops[upperIndex], localFraction)
    }

    private static func lerp(_ from: Color, _ to: Color, _ fraction: Double) -> Color {
        let fromComponents = UIColor(from).rgbaComponents
        let toComponents = UIColor(to).rgbaComponents
        let t = CGFloat(fraction)
        return Color(
            red: Double(fromComponents.r + (toComponents.r - fromComponents.r) * t),
            green: Double(fromComponents.g + (toComponents.g - fromComponents.g) * t),
            blue: Double(fromComponents.b + (toComponents.b - fromComponents.b) * t)
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
