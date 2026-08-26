import Foundation
import AppIntents

struct WidgetRevenueSnapshot: Codable, Hashable {
    let amount: Double
    let currencyCode: String
    let rangeLabel: String
    let updatedAt: Date
    let values: [Double]
}

struct WidgetRefreshConfiguration: Codable, Hashable {
    let accountId: String
    let currencyCode: String
    let reportingTimeZone: String?
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
    private static let refreshConfigurationKey = "widgetRefreshConfiguration"
    private static func snapshotKey(for range: WidgetTimeRange) -> String {
        "latestRevenueSnapshot.\(range.rawValue)"
    }

    static func save(_ snapshot: WidgetRevenueSnapshot, for range: WidgetTimeRange) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: snapshotKey(for: range))
    }

    static func load(for range: WidgetTimeRange) -> WidgetRevenueSnapshot? {
        guard let data = defaults.data(forKey: snapshotKey(for: range)) else { return nil }
        return try? JSONDecoder().decode(WidgetRevenueSnapshot.self, from: data)
    }

    static func saveRefreshConfiguration(_ configuration: WidgetRefreshConfiguration) {
        guard let data = try? JSONEncoder().encode(configuration) else { return }
        defaults.set(data, forKey: refreshConfigurationKey)
    }

    static func loadRefreshConfiguration() -> WidgetRefreshConfiguration? {
        guard let data = defaults.data(forKey: refreshConfigurationKey) else { return nil }
        return try? JSONDecoder().decode(WidgetRefreshConfiguration.self, from: data)
    }

    static func clearAll() {
        defaults.removeObject(forKey: refreshConfigurationKey)
        for range in WidgetTimeRange.allCases {
            defaults.removeObject(forKey: snapshotKey(for: range))
        }
    }

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupId) ?? .standard
    }
}
