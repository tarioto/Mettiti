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
