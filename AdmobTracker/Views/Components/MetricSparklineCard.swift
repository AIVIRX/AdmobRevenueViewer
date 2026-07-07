import Charts
import SwiftUI

struct MetricSparklineCard: View {
    let title: String
    let value: String
    let delta: Double?
    let values: [Double]

    private var points: [SparklinePoint] {
        values.enumerated().map { SparklinePoint(index: $0.offset, value: $0.element) }
    }

    private var deltaColor: Color {
        guard let delta else { return .secondary }
        return delta >= 0 ? .green : .red
    }

    private var chartDomain: ClosedRange<Double> {
        guard let minimum = values.min(), let maximum = values.max() else { return 0...1 }
        let span = maximum - minimum
        let padding = max(span * 0.15, max(abs(maximum), abs(minimum)) * 0.08, 0.01)
        return (minimum - padding)...(maximum + padding)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value)
                    .font(.system(size: 23, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .contentTransition(.numericText())

                if let delta {
                    Label(formatDelta(delta), systemImage: delta >= 0 ? "arrow.up" : "arrow.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(deltaColor)
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                }
            }

            Chart(points) { point in
                LineMark(
                    x: .value("Day", point.index),
                    y: .value(title, point.value)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(Color.accentColor)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                if points.count == 1 {
                    PointMark(
                        x: .value("Day", point.index),
                        y: .value(title, point.value)
                    )
                    .foregroundStyle(Color.accentColor)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: chartDomain)
            .frame(height: 68)
            .accessibilityHidden(true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 144, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color(uiColor: .tertiarySystemFill), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
    }

    private func formatDelta(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: abs(value))) ?? "0%"
    }
}

private struct SparklinePoint: Identifiable {
    let index: Int
    let value: Double

    var id: Int { index }
}
