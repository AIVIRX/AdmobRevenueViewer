import Foundation
import AppIntents

struct WidgetRevenueSnapshot: Codable, Hashable {
    let amount: Double
    let currencyCode: String
    let rangeLabel: String
    let updatedAt: Date
    let values: [Double]
}

enum WidgetTimeRange: String, CaseIterable, Codable, Hashable, AppEnum {
    case today
    case yesterday
    case last7Days
    case thisMonth
    case lastMonth

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        "Revenue Range"
    }

    static var caseDisplayRepresentations: [WidgetTimeRange: DisplayRepresentation] {
        [
            .today: "Today",
            .yesterday: "Yesterday",
            .last7Days: "Last 7 Days",
            .thisMonth: "This Month",
            .lastMonth: "Last Month"
        ]
    }
}

enum WidgetRevenueStore {
    static let widgetKind = "RevenueWidget"
    private static let appGroupId = "group.com.Maicol.AdmobTracker"
    private static func snapshotKey(for range: WidgetTimeRange) -> String {
        "latestRevenueSnapshot.\(range.rawValue)"
    }

    static func load(for range: WidgetTimeRange) -> WidgetRevenueSnapshot? {
        guard let data = defaults.data(forKey: snapshotKey(for: range)) else { return nil }
        return try? JSONDecoder().decode(WidgetRevenueSnapshot.self, from: data)
    }

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupId) ?? .standard
    }
}
