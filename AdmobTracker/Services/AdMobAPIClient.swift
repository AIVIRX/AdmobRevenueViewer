import Foundation

protocol AdMobAPIClient {
    func fetchAccounts() async throws -> [AdMobAccount]
    func fetchReport(accountId: String, range: DateRange, timeZone: String?) async throws -> AdMobReport
}

final class LiveAdMobAPIClient: AdMobAPIClient {
    private let authManager: AuthManaging
    private let session: URLSession

    init(authManager: AuthManaging, session: URLSession = .shared) {
        self.authManager = authManager
        self.session = session
    }

    func fetchAccounts() async throws -> [AdMobAccount] {
        let url = URL(string: "https://admob.googleapis.com/v1/accounts")!
        let data = try await request(url: url, method: "GET")
        guard !data.isEmpty else {
            throw AdMobAPIError.emptyResponse
        }
        do {
            let response = try JSONDecoder().decode(ListPublisherAccountsResponse.self, from: data)
            return response.accounts.map {
                AdMobAccount(
                    id: $0.name,
                    publisherId: $0.publisherId,
                    displayName: $0.displayName,
                    currencyCode: $0.currencyCode ?? "USD",
                    reportingTimeZone: $0.reportingTimeZone
                )
            }
        } catch {
            if let fallback = try? parseAccountsLoosely(data: data) {
                return fallback
            }
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AdMobAPIError.decodingFailed(body: body, underlying: error)
        }
    }

    func fetchReport(accountId: String, range: DateRange, timeZone: String?) async throws -> AdMobReport {
        let url = URL(string: "https://admob.googleapis.com/v1/\(accountId)/networkReport:generate")!
        let apiTimeZone = (timeZone == "America/Los_Angeles") ? timeZone : nil
        let body = ReportRequest(reportSpec: ReportSpec(
            dateRange: ReportDateRange(startDate: range.startDate, endDate: range.endDate),
            dimensions: ["DATE", "APP", "AD_UNIT"],
            metrics: ["ESTIMATED_EARNINGS", "IMPRESSIONS", "CLICKS"],
            sortConditions: [ReportSortCondition(dimension: "DATE", order: "DESCENDING")],
            timeZone: apiTimeZone
        ))

        let data = try await request(url: url, method: "POST", body: body)
        let lines: [GenerateNetworkReportResponse]
        do {
            lines = try parseReportStream(data: data)
        } catch {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AdMobAPIError.decodingFailed(body: body, underlying: error)
        }

        let rows: [AdMobReportRow] = lines.compactMap { response in
            guard let row = response.row else { return nil }
            let dateString = row.dimensionValues["DATE"]?.value ?? ""
            let date = DateParser.date(from: dateString) ?? range.endDate

            let appDimension = row.dimensionValues["APP"]
            let appName = appDimension?.displayLabel ?? appDimension?.value ?? "Unknown App"

            let adUnitDimension = row.dimensionValues["AD_UNIT"]
            let adUnitName = adUnitDimension?.displayLabel ?? adUnitDimension?.value ?? "Unknown Ad Unit"

            let earningsMicros = row.metricValues["ESTIMATED_EARNINGS"]?.microsValue ?? 0
            let earnings = Double(earningsMicros) / 1_000_000.0
            let impressions = row.metricValues["IMPRESSIONS"]?.intValue ?? 0
            let clicks = row.metricValues["CLICKS"]?.intValue ?? 0
            let eCPM = impressions > 0 ? (earnings / Double(impressions) * 1000.0) : 0

            let metrics = AdMobMetrics(
                estimatedEarnings: earnings,
                impressions: impressions,
                clicks: clicks,
                eCPM: eCPM
            )

            return AdMobReportRow(
                id: UUID().uuidString,
                date: date,
                appName: appName,
                adUnitName: adUnitName,
                metrics: metrics
            )
        }

        let totals = rows.reduce(AdMobMetrics(estimatedEarnings: 0, impressions: 0, clicks: 0, eCPM: 0)) { partial, row in
            let earnings = partial.estimatedEarnings + row.metrics.estimatedEarnings
            let impressions = partial.impressions + row.metrics.impressions
            let clicks = partial.clicks + row.metrics.clicks
            let ecpm = impressions > 0 ? (earnings / Double(impressions) * 1000.0) : 0
            return AdMobMetrics(estimatedEarnings: earnings, impressions: impressions, clicks: clicks, eCPM: ecpm)
        }

        return AdMobReport(startDate: range.startDate, endDate: range.endDate, rows: rows, totals: totals)
    }

    private func request(url: URL, method: String) async throws -> Data {
        try await request(url: url, method: method, body: Optional<Data>.none)
    }

    private func request<T: Encodable>(url: URL, method: String, body: T?) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let token = try await authManager.accessToken()
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        if let body {
            request.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AdMobAPIError.httpError(statusCode: httpResponse.statusCode, body: body)
        }
        return data
    }

    private func parseReportStream(data: Data) throws -> [GenerateNetworkReportResponse] {
        guard let payload = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }

        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        let decoder = JSONDecoder()

        if trimmed.hasPrefix("[") {
            return try decoder.decode([GenerateNetworkReportResponse].self, from: data)
        }

        var responses: [GenerateNetworkReportResponse] = []

        for line in payload.split(separator: "\n") {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLine.isEmpty else { continue }
            let lineData = Data(trimmedLine.utf8)
            do {
                let response = try decoder.decode(GenerateNetworkReportResponse.self, from: lineData)
                responses.append(response)
            } catch {
                throw AdMobAPIError.decodingFailed(body: String(trimmedLine), underlying: error)
            }
        }

        if responses.isEmpty, let single = try? decoder.decode(GenerateNetworkReportResponse.self, from: data) {
            return [single]
        }

        return responses
    }

    private func parseAccountsLoosely(data: Data) throws -> [AdMobAccount] {
        let object = try JSONSerialization.jsonObject(with: data, options: [])
        guard let root = object as? [String: Any] else { return [] }
        let accountArray = (root["account"] ?? root["accounts"]) as? [Any] ?? []

        return accountArray.compactMap { item in
            guard let dict = item as? [String: Any] else { return nil }
            let normalized = normalizeKeys(dict)
            let name = normalized["name"] as? String ?? ""
            let publisherId = normalized["publisherid"] as? String ?? ""
            let displayName = normalized["displayname"] as? String ?? publisherId
            let currencyCode = normalized["currencycode"] as? String ?? "USD"
            let reportingTimeZone = normalized["reportingtimezone"] as? String
            guard !name.isEmpty, !publisherId.isEmpty else { return nil }
            return AdMobAccount(
                id: name,
                publisherId: publisherId,
                displayName: displayName,
                currencyCode: currencyCode,
                reportingTimeZone: reportingTimeZone
            )
        }
    }

    private func normalizeKeys(_ dict: [String: Any]) -> [String: Any] {
        var normalized: [String: Any] = [:]
        for (key, value) in dict {
            let normalizedKey = key
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "_", with: "")
                .lowercased()
                .replacingOccurrences(of: "publisherld", with: "publisherid")
            normalized[normalizedKey] = value
        }
        return normalized
    }
}

enum AdMobAPIError: LocalizedError {
    case httpError(statusCode: Int, body: String)
    case emptyResponse
    case decodingFailed(body: String, underlying: Error)

    var errorDescription: String? {
        switch self {
        case let .httpError(statusCode, body):
            if body.isEmpty {
                return "HTTP \(statusCode)"
            }
            return "HTTP \(statusCode): \(body)"
        case .emptyResponse:
            return "Empty response from AdMob API."
        case let .decodingFailed(body, underlying):
            if body.isEmpty {
                return "Unable to parse AdMob API response: \(underlying.localizedDescription)"
            }
            return "Unable to parse AdMob API response. Raw: \(body)"
        }
    }
}

final class MockAdMobAPIClient: AdMobAPIClient {
    func fetchAccounts() async throws -> [AdMobAccount] {
        [
            AdMobAccount(id: "accounts/pub-0000000000000000", publisherId: "pub-0000000000000000", displayName: "Main Publisher", currencyCode: "USD", reportingTimeZone: "America/Los_Angeles"),
            AdMobAccount(id: "accounts/pub-1111111111111111", publisherId: "pub-1111111111111111", displayName: "Backup Publisher", currencyCode: "USD", reportingTimeZone: "America/Los_Angeles")
        ]
    }

    func fetchReport(accountId: String, range: DateRange, timeZone: String?) async throws -> AdMobReport {
        let calendar = Calendar.current
        let rows = (0..<7).map { index in
            let date = calendar.date(byAdding: .day, value: -index, to: range.endDate) ?? range.endDate
            let appName = index % 2 == 0 ? "Puzzle Quest" : "Notes Pro"
            let adUnitName = index % 2 == 0 ? "Banner Home" : "Interstitial Level"
            let earnings = Double(arc4random_uniform(600)) / 100.0 + 2.0
            let impressions = 1200 + index * 180
            let clicks = 30 + index * 4
            let eCPM = 4.5 + Double(index) * 0.2
            let metrics = AdMobMetrics(
                estimatedEarnings: earnings,
                impressions: impressions,
                clicks: clicks,
                eCPM: eCPM
            )
            return AdMobReportRow(
                id: "row-\(index)",
                date: date,
                appName: appName,
                adUnitName: adUnitName,
                metrics: metrics
            )
        }

        let totals = rows.reduce(AdMobMetrics(estimatedEarnings: 0, impressions: 0, clicks: 0, eCPM: 0)) { partial, row in
            let earnings = partial.estimatedEarnings + row.metrics.estimatedEarnings
            let impressions = partial.impressions + row.metrics.impressions
            let clicks = partial.clicks + row.metrics.clicks
            let ecpm = impressions > 0 ? (earnings / Double(impressions) * 1000.0) : 0
            return AdMobMetrics(estimatedEarnings: earnings, impressions: impressions, clicks: clicks, eCPM: ecpm)
        }

        return AdMobReport(startDate: range.startDate, endDate: range.endDate, rows: rows, totals: totals)
    }
}

private struct ListPublisherAccountsResponse: Decodable {
    let accounts: [PublisherAccount]

    private enum CodingKeys: String, CodingKey {
        case account
        case accounts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let account = try container.decodeIfPresent([PublisherAccount].self, forKey: .account) {
            accounts = account
        } else if let accounts = try container.decodeIfPresent([PublisherAccount].self, forKey: .accounts) {
            self.accounts = accounts
        } else {
            accounts = []
        }
    }
}

private struct PublisherAccount: Decodable {
    let name: String
    let publisherId: String
    let displayName: String
    let reportingTimeZone: String?
    let currencyCode: String?
}

private struct GenerateNetworkReportResponse: Decodable {
    let header: ReportHeader?
    let row: ReportRow?
    let footer: ReportFooter?
}

private struct ReportHeader: Decodable {
    let dateRange: ReportDateRangeResponse?
}

private struct ReportFooter: Decodable {
    let matchingRowCount: String?
}

private struct ReportRow: Decodable {
    let dimensionValues: [String: DimensionValue]
    let metricValues: [String: MetricValue]
}

private struct DimensionValue: Decodable {
    let value: String?
    let displayLabel: String?
}

private struct MetricValue: Decodable {
    let integerValue: String?
    let doubleValue: Double?
    let microsValueString: String?
    
    private enum CodingKeys: String, CodingKey {
        case integerValue
        case doubleValue
        case microsValueString = "microsValue"
    }

    var intValue: Int {
        Int(integerValue ?? "") ?? 0
    }

    var microsValue: Int {
        Int(microsValueString ?? "") ?? 0
    }
}

private struct ReportRequest: Encodable {
    let reportSpec: ReportSpec
}

private struct ReportSpec: Encodable {
    let dateRange: ReportDateRange
    let dimensions: [String]
    let metrics: [String]
    let sortConditions: [ReportSortCondition]?
    let timeZone: String?
}

private struct ReportSortCondition: Encodable {
    let dimension: String
    let order: String
}

private struct ReportDateRange: Encodable {
    let startDate: ReportDate
    let endDate: ReportDate

    init(startDate: Date, endDate: Date) {
        self.startDate = ReportDate(date: startDate)
        self.endDate = ReportDate(date: endDate)
    }
}

private struct ReportDate: Encodable {
    let year: Int
    let month: Int
    let day: Int

    init(date: Date) {
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        year = components.year ?? 0
        month = components.month ?? 0
        day = components.day ?? 0
    }
}

private enum DateParser {
    static func date(from string: String) -> Date? {
        guard string.count == 8 else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.date(from: string)
    }
}

private struct ReportDateRangeResponse: Decodable {
    let startDate: ReportDateResponse?
    let endDate: ReportDateResponse?
}

private struct ReportDateResponse: Decodable {
    let year: Int?
    let month: Int?
    let day: Int?
}
