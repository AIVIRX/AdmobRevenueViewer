import Foundation

struct AdMobAccount: Identifiable, Hashable {
    let id: String
    let publisherId: String
    let displayName: String
    let currencyCode: String
    let reportingTimeZone: String?
}

struct AdMobReport: Hashable {
    let startDate: Date
    let endDate: Date
    let rows: [AdMobReportRow]
    let totals: AdMobMetrics
}

struct AdMobReportRow: Identifiable, Hashable {
    let id: String
    let date: Date
    let appName: String
    let adUnitName: String
    let metrics: AdMobMetrics
}

struct AdMobMetrics: Hashable {
    let estimatedEarnings: Double
    let impressions: Int
    let clicks: Int
    let eCPM: Double
    let adRequests: Int
    let matchedRequests: Int
    let observedECPM: Double
}

struct AdMobApp: Hashable {
    let appId: String
    let displayName: String
    let appStoreId: String?
    let platform: String?
}

struct AdMobAdUnit: Hashable {
    let name: String
    let adUnitId: String
    let appId: String
    let displayName: String
    let adFormat: String
}

struct DateRange: Hashable {
    let startDate: Date
    let endDate: Date

    static func lastNDays(_ days: Int, calendar: Calendar = .current) -> DateRange {
        let end = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: -max(days - 1, 0), to: end) ?? end
        return DateRange(startDate: start, endDate: end)
    }
}
