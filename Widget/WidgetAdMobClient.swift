import Foundation
@preconcurrency import GoogleSignIn

@MainActor
enum WidgetAdMobClient {
    static func fetchSnapshot(
        configuration: WidgetRefreshConfiguration,
        range: WidgetTimeRange
    ) async throws -> WidgetRevenueSnapshot {
        guard let savedUser = try SharedGoogleCredentialStore.load() else {
            throw WidgetFetchError.missingCredentials
        }

        let user = try await refreshedUser(savedUser)
        try SharedGoogleCredentialStore.save(user)

        let calendar = reportingCalendar(configuration.reportingTimeZone)
        let requestedRange = dateRange(for: range, calendar: calendar)
        let reportRange = (range == .today || range == .yesterday)
            ? lastSevenDays(calendar: calendar)
            : requestedRange
        let dailyValues = try await fetchDailyRevenue(
            configuration: configuration,
            range: reportRange,
            calendar: calendar,
            accessToken: user.accessToken.tokenString
        )

        let requestedDays = days(in: requestedRange, calendar: calendar)
        let amount = requestedDays.reduce(0) { $0 + (dailyValues[$1] ?? 0) }
        let seriesDays = days(in: reportRange, calendar: calendar)

        return WidgetRevenueSnapshot(
            amount: amount,
            currencyCode: configuration.currencyCode,
            rangeLabel: range.label,
            updatedAt: .now,
            values: seriesDays.map { dailyValues[$0] ?? 0 }
        )
    }

    private static func refreshedUser(_ user: GIDGoogleUser) async throws -> GIDGoogleUser {
        try await withCheckedThrowingContinuation { continuation in
            user.refreshTokensIfNeeded { refreshedUser, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: refreshedUser ?? user)
                }
            }
        }
    }

    private static func fetchDailyRevenue(
        configuration: WidgetRefreshConfiguration,
        range: ClosedRange<Date>,
        calendar: Calendar,
        accessToken: String
    ) async throws -> [Date: Double] {
        guard let url = URL(string: "https://admob.googleapis.com/v1/\(configuration.accountId)/networkReport:generate") else {
            throw WidgetFetchError.invalidURL
        }

        var reportSpec: [String: Any] = [
            "dateRange": [
                "startDate": reportDate(range.lowerBound, calendar: calendar),
                "endDate": reportDate(range.upperBound, calendar: calendar)
            ],
            "dimensions": ["DATE"],
            "metrics": ["ESTIMATED_EARNINGS"],
            "sortConditions": [["dimension": "DATE", "order": "ASCENDING"]]
        ]
        if configuration.reportingTimeZone == "America/Los_Angeles" {
            reportSpec["timeZone"] = configuration.reportingTimeZone
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["reportSpec": reportSpec])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode) else {
            throw WidgetFetchError.requestFailed
        }

        return try parseDailyRevenue(data, calendar: calendar)
    }

    private static func parseDailyRevenue(_ data: Data, calendar: Calendar) throws -> [Date: Double] {
        let object = try JSONSerialization.jsonObject(with: data)
        let responses: [[String: Any]]
        if let array = object as? [[String: Any]] {
            responses = array
        } else if let dictionary = object as? [String: Any] {
            responses = [dictionary]
        } else {
            throw WidgetFetchError.invalidResponse
        }

        var result: [Date: Double] = [:]
        for response in responses {
            guard let row = response["row"] as? [String: Any],
                  let dimensions = row["dimensionValues"] as? [String: Any],
                  let dateDimension = dimensions["DATE"] as? [String: Any],
                  let dateString = dateDimension["value"] as? String,
                  let date = parseDate(dateString, calendar: calendar),
                  let metrics = row["metricValues"] as? [String: Any],
                  let earnings = metrics["ESTIMATED_EARNINGS"] as? [String: Any] else { continue }

            let micros = doubleValue(earnings["microsValue"])
            result[calendar.startOfDay(for: date), default: 0] += micros / 1_000_000
        }
        return result
    }

    private static func doubleValue(_ value: Any?) -> Double {
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) ?? 0 }
        return 0
    }

    private static func reportingCalendar(_ identifier: String?) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = identifier.flatMap(TimeZone.init(identifier:)) ?? .current
        return calendar
    }

    private static func dateRange(for range: WidgetTimeRange, calendar: Calendar) -> ClosedRange<Date> {
        let today = calendar.startOfDay(for: .now)
        switch range {
        case .today:
            return today...today
        case .yesterday:
            let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
            return yesterday...yesterday
        case .last7Days:
            return lastSevenDays(calendar: calendar)
        case .thisMonth:
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) ?? today
            return start...today
        case .lastMonth:
            let thisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) ?? today
            let start = calendar.date(byAdding: .month, value: -1, to: thisMonth) ?? thisMonth
            let end = calendar.date(byAdding: .day, value: -1, to: thisMonth) ?? start
            return start...end
        }
    }

    private static func lastSevenDays(calendar: Calendar) -> ClosedRange<Date> {
        let end = calendar.startOfDay(for: .now)
        let start = calendar.date(byAdding: .day, value: -6, to: end) ?? end
        return start...end
    }

    private static func days(in range: ClosedRange<Date>, calendar: Calendar) -> [Date] {
        let count = max(calendar.dateComponents([.day], from: range.lowerBound, to: range.upperBound).day ?? 0, 0)
        return (0...count).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: range.lowerBound).map(calendar.startOfDay(for:))
        }
    }

    private static func reportDate(_ date: Date, calendar: Calendar) -> [String: Int] {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return ["year": components.year ?? 0, "month": components.month ?? 0, "day": components.day ?? 0]
    }

    private static func parseDate(_ string: String, calendar: Calendar) -> Date? {
        guard string.count == 8,
              let year = Int(string.prefix(4)),
              let month = Int(string.dropFirst(4).prefix(2)),
              let day = Int(string.suffix(2)) else { return nil }
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }
}

private enum WidgetFetchError: Error {
    case missingCredentials
    case invalidURL
    case requestFailed
    case invalidResponse
}
