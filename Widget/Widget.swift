//
//  Widget.swift
//  Widget
//
//  Created by Maicol Cabreja on 6/26/26.
//

import WidgetKit
import SwiftUI
import AppIntents

struct RevenueWidgetConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Revenue Range"
    static var description = IntentDescription("Choose which AdMob revenue range the widget should show.")

    @Parameter(title: "Time Range", default: .today)
    var timeRange: WidgetTimeRange
}

struct RevenueProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> RevenueEntry {
        RevenueEntry(date: .now, snapshot: .placeholder, timeRange: .today)
    }

    func snapshot(for configuration: RevenueWidgetConfigurationIntent, in context: Context) async -> RevenueEntry {
        RevenueEntry(
            date: .now,
            snapshot: WidgetRevenueStore.load(for: configuration.timeRange) ?? .placeholder,
            timeRange: configuration.timeRange
        )
    }

    func timeline(for configuration: RevenueWidgetConfigurationIntent, in context: Context) async -> Timeline<RevenueEntry> {
        var snapshot = WidgetRevenueStore.load(for: configuration.timeRange)
        if let refreshConfiguration = WidgetRevenueStore.loadRefreshConfiguration(),
           let refreshedSnapshot = try? await WidgetAdMobClient.fetchSnapshot(
               configuration: refreshConfiguration,
               range: configuration.timeRange
           ) {
            WidgetRevenueStore.save(refreshedSnapshot, for: configuration.timeRange)
            snapshot = refreshedSnapshot
        }

        let entry = RevenueEntry(
            date: .now,
            snapshot: snapshot,
            timeRange: configuration.timeRange
        )
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now.addingTimeInterval(1_800)
        return Timeline(entries: [entry], policy: .after(nextRefresh))
    }
}

struct RevenueEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetRevenueSnapshot?
    let timeRange: WidgetTimeRange
}

struct RevenueWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RevenueProvider.Entry

    var body: some View {
        if let snapshot = entry.snapshot {
            if family == .systemSmall {
                smallRevenueView(snapshot)
            } else {
                mediumRevenueView(snapshot)
            }
        } else {
            emptyView
        }
    }

    private func smallRevenueView(_ snapshot: WidgetRevenueSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Revenue")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 2)
                Text(snapshot.rangeLabel)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(formatCurrency(snapshot.amount, currencyCode: snapshot.currencyCode))
                .font(.system(size: 31, weight: .semibold, design: .rounded))
                .minimumScaleFactor(0.72)
                .lineLimit(1)

            RevenueSparkline(values: snapshot.values)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                .frame(height: 38)
                .padding(.top, 1)
        }
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func mediumRevenueView(_ snapshot: WidgetRevenueSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Revenue")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text(snapshot.rangeLabel)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(formatCurrency(snapshot.amount, currencyCode: snapshot.currencyCode))
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .minimumScaleFactor(0.72)
                .lineLimit(1)

            RevenueSparkline(values: snapshot.values)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                .frame(height: 48)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var emptyView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Revenue")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("--")
                .font(.system(size: family == .systemSmall ? 34 : 44, weight: .semibold, design: .rounded))
            Text("Open the app to load your latest AdMob earnings.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func formatCurrency(_ value: Double, currencyCode: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.maximumFractionDigits = value >= 100 ? 0 : 2
        return formatter.string(from: NSNumber(value: value)) ?? "\(currencyCode) \(value)"
    }
}

struct RevenueSparkline: Shape {
    let values: [Double]

    func path(in rect: CGRect) -> Path {
        let cleanedValues = values.isEmpty ? [0] : values
        guard cleanedValues.count > 1 else {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return path
        }

        let minValue = cleanedValues.min() ?? 0
        let maxValue = cleanedValues.max() ?? 1
        let range = max(maxValue - minValue, 0.01)
        let step = rect.width / CGFloat(cleanedValues.count - 1)

        var path = Path()
        for (index, value) in cleanedValues.enumerated() {
            let x = rect.minX + CGFloat(index) * step
            let progress = (value - minValue) / range
            let y = rect.maxY - CGFloat(progress) * rect.height
            let point = CGPoint(x: x, y: y)
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        return path
    }
}

struct RevenueWidget: Widget {
    let kind = WidgetRevenueStore.widgetKind

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: RevenueWidgetConfigurationIntent.self, provider: RevenueProvider()) { entry in
            if #available(iOS 17.0, *) {
                RevenueWidgetEntryView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                RevenueWidgetEntryView(entry: entry)
                    .padding()
                    .background(Color(uiColor: .secondarySystemBackground))
            }
        }
        .configurationDisplayName("AdMob Revenue")
        .description("See your latest estimated revenue.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private extension WidgetRevenueSnapshot {
    static let placeholder = WidgetRevenueSnapshot(
        amount: 42.15,
        currencyCode: "USD",
        rangeLabel: "Today",
        updatedAt: .now,
        values: [28, 34, 30, 39, 45, 42]
    )
}

#Preview(as: .systemSmall) {
    RevenueWidget()
} timeline: {
    RevenueEntry(date: .now, snapshot: .placeholder, timeRange: .today)
}

#Preview(as: .systemMedium) {
    RevenueWidget()
} timeline: {
    RevenueEntry(date: .now, snapshot: .placeholder, timeRange: .today)
}
