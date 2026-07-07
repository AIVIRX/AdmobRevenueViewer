import Foundation

protocol AdMobAPIClient {
    func fetchAccounts() async throws -> [AdMobAccount]
    func fetchReport(accountId: String, range: DateRange, timeZone: String?) async throws -> AdMobReport
    func fetchCountryReport(accountId: String, range: DateRange, timeZone: String?) async throws -> [AdMobCountrySummary]
    func fetchMonthlyEarnings(accountId: String, range: DateRange, timeZone: String?) async throws -> [AdMobMonthlyEarning]
    func fetchApps(accountId: String) async throws -> [AdMobApp]
    func fetchAdUnits(accountId: String) async throws -> [AdMobAdUnit]
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
            metrics: ["ESTIMATED_EARNINGS", "IMPRESSIONS", "CLICKS", "AD_REQUESTS", "MATCHED_REQUESTS", "IMPRESSION_RPM"],
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
            let date = DateParser.date(from: dateString, timeZone: timeZone) ?? range.endDate

            let appDimension = row.dimensionValues["APP"]
            let appName = appDimension?.displayLabel ?? appDimension?.value ?? "Unknown App"

            let adUnitDimension = row.dimensionValues["AD_UNIT"]
            let adUnitName = adUnitDimension?.displayLabel ?? adUnitDimension?.value ?? "Unknown Ad Unit"

            let earningsMicros = row.metricValues["ESTIMATED_EARNINGS"]?.microsValue ?? 0
            let earnings = Double(earningsMicros) / 1_000_000.0
            let impressions = row.metricValues["IMPRESSIONS"]?.intValue ?? 0
            let clicks = row.metricValues["CLICKS"]?.intValue ?? 0
            let eCPM = impressions > 0 ? (earnings / Double(impressions) * 1000.0) : 0
            let adRequests = row.metricValues["AD_REQUESTS"]?.intValue ?? 0
            let matchedRequests = row.metricValues["MATCHED_REQUESTS"]?.intValue ?? 0
            let impressionRpmMicros = row.metricValues["IMPRESSION_RPM"]?.microsValue ?? 0
            let observedECPM = Double(impressionRpmMicros) / 1_000_000.0

            let metrics = AdMobMetrics(
                estimatedEarnings: earnings,
                impressions: impressions,
                clicks: clicks,
                eCPM: eCPM,
                adRequests: adRequests,
                matchedRequests: matchedRequests,
                observedECPM: observedECPM
            )

            return AdMobReportRow(
                id: UUID().uuidString,
                date: date,
                appName: appName,
                adUnitName: adUnitName,
                metrics: metrics
            )
        }

        let totals = rows.reduce(AdMobMetrics(estimatedEarnings: 0, impressions: 0, clicks: 0, eCPM: 0, adRequests: 0, matchedRequests: 0, observedECPM: 0)) { partial, row in
            let earnings = partial.estimatedEarnings + row.metrics.estimatedEarnings
            let impressions = partial.impressions + row.metrics.impressions
            let clicks = partial.clicks + row.metrics.clicks
            let ecpm = impressions > 0 ? (earnings / Double(impressions) * 1000.0) : 0
            let adRequests = partial.adRequests + row.metrics.adRequests
            let matchedRequests = partial.matchedRequests + row.metrics.matchedRequests
            let observedECPM = impressions > 0 ? (earnings / Double(impressions) * 1000.0) : 0
            return AdMobMetrics(
                estimatedEarnings: earnings,
                impressions: impressions,
                clicks: clicks,
                eCPM: ecpm,
                adRequests: adRequests,
                matchedRequests: matchedRequests,
                observedECPM: observedECPM
            )
        }

        return AdMobReport(startDate: range.startDate, endDate: range.endDate, rows: rows, totals: totals)
    }

    func fetchCountryReport(accountId: String, range: DateRange, timeZone: String?) async throws -> [AdMobCountrySummary] {
        let url = URL(string: "https://admob.googleapis.com/v1/\(accountId)/networkReport:generate")!
        let apiTimeZone = (timeZone == "America/Los_Angeles") ? timeZone : nil
        let body = ReportRequest(reportSpec: ReportSpec(
            dateRange: ReportDateRange(startDate: range.startDate, endDate: range.endDate),
            dimensions: ["COUNTRY"],
            metrics: ["ESTIMATED_EARNINGS", "IMPRESSIONS", "CLICKS", "AD_REQUESTS", "MATCHED_REQUESTS"],
            sortConditions: [ReportSortCondition(dimension: "COUNTRY", order: "ASCENDING")],
            timeZone: apiTimeZone
        ))
        let data = try await request(url: url, method: "POST", body: body)
        let lines = try parseReportStream(data: data)
        return lines.compactMap { response in
            guard let row = response.row else { return nil }
            let country = row.dimensionValues["COUNTRY"]
            let name = country?.displayLabel ?? country?.value ?? "Unknown"
            let code = country?.value
            let micros = row.metricValues["ESTIMATED_EARNINGS"]?.microsValue ?? 0
            let earnings = Double(micros) / 1_000_000
            let impressions = row.metricValues["IMPRESSIONS"]?.intValue ?? 0
            return AdMobCountrySummary(
                id: code ?? name,
                name: name,
                code: code,
                earnings: earnings,
                impressions: impressions,
                clicks: row.metricValues["CLICKS"]?.intValue ?? 0,
                adRequests: row.metricValues["AD_REQUESTS"]?.intValue ?? 0,
                matchedRequests: row.metricValues["MATCHED_REQUESTS"]?.intValue ?? 0,
                eCPM: impressions > 0 ? earnings / Double(impressions) * 1_000 : 0
            )
        }
    }

    func fetchMonthlyEarnings(accountId: String, range: DateRange, timeZone: String?) async throws -> [AdMobMonthlyEarning] {
        let url = URL(string: "https://admob.googleapis.com/v1/\(accountId)/networkReport:generate")!
        let apiTimeZone = (timeZone == "America/Los_Angeles") ? timeZone : nil
        let body = ReportRequest(reportSpec: ReportSpec(
            dateRange: ReportDateRange(startDate: range.startDate, endDate: range.endDate),
            dimensions: ["MONTH"],
            metrics: ["ESTIMATED_EARNINGS"],
            sortConditions: [ReportSortCondition(dimension: "MONTH", order: "ASCENDING")],
            timeZone: apiTimeZone
        ))
        let data = try await request(url: url, method: "POST", body: body)
        let lines = try parseReportStream(data: data)
        return lines.compactMap { response in
            guard let row = response.row,
                  let monthValue = row.dimensionValues["MONTH"]?.value,
                  let month = DateParser.month(from: monthValue, timeZone: timeZone) else { return nil }
            let micros = row.metricValues["ESTIMATED_EARNINGS"]?.microsValue ?? 0
            return AdMobMonthlyEarning(month: month, estimatedEarnings: Double(micros) / 1_000_000)
        }
    }

    func fetchApps(accountId: String) async throws -> [AdMobApp] {
        let url = URL(string: "https://admob.googleapis.com/v1/\(accountId)/apps")!
        let data = try await request(url: url, method: "GET")
        let response = try JSONDecoder().decode(ListAppsResponse.self, from: data)
        return response.apps?.compactMap { app in
            let displayName = app.linkedAppInfo?.displayName ?? app.manualAppInfo?.displayName
            guard let displayName else { return nil }
            return AdMobApp(
                appId: app.appId ?? app.name ?? "",
                displayName: displayName,
                appStoreId: app.linkedAppInfo?.appStoreId,
                platform: app.platform
            )
        } ?? []
    }

    func fetchAdUnits(accountId: String) async throws -> [AdMobAdUnit] {
        let url = URL(string: "https://admob.googleapis.com/v1/\(accountId)/adUnits")!
        let data = try await request(url: url, method: "GET")
        let response = try JSONDecoder().decode(ListAdUnitsResponse.self, from: data)
        return response.adUnits?.map {
            AdMobAdUnit(
                name: $0.name,
                adUnitId: $0.adUnitId,
                appId: $0.appId,
                displayName: $0.displayName,
                adFormat: $0.adFormat
            )
        } ?? []
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

    var userMessage: String? {
        switch self {
        case let .httpError(statusCode, body):
            let normalizedBody = body.lowercased()
            let unauthenticated = Self.isUnauthenticatedPublisher(statusCode: statusCode, body: normalizedBody)
            if unauthenticated {
                return "This Google account doesn't have AdMob access. Sign in with an AdMob-enabled account or create an AdMob account."
            }
            if statusCode == 403 {
                return "This Google account doesn't have permission to access AdMob data."
            }
            return nil
        case .emptyResponse, .decodingFailed:
            return nil
        }
    }

    static func isUnauthenticatedPublisher(statusCode: Int, body: String) -> Bool {
        guard statusCode == 401 else { return false }
        return body.contains("unauthenticated")
            || body.contains("could not be authenticated")
            || body.contains("publisher could not be authenticated")
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
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone.flatMap(TimeZone.init(identifier:)) ?? .current
        let start = calendar.startOfDay(for: range.startDate)
        let end = calendar.startOfDay(for: range.endDate)
        let dayCount = max((calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1, 1)
        let placements = [
            (app: "Crypto Profit Loss Calculator", adUnit: "Banner Home", scale: 1.0),
            (app: "Notes Pro", adUnit: "Interstitial Level", scale: 0.72),
            (app: "Focus Timer", adUnit: "Rewarded Bonus", scale: 0.48)
        ]
        var generator = SeededMockGenerator(seed: mockSeed(accountId: accountId, range: range, calendar: calendar))
        var rows: [AdMobReportRow] = []

        for dayOffset in 0..<dayCount {
            let date = calendar.date(byAdding: .day, value: dayOffset, to: start) ?? start
            for (placementIndex, placement) in placements.enumerated() {
                let adRequests = Int(Double(generator.int(in: 1_500...4_800)) * placement.scale)
                let matchRate = generator.double(in: 0.62...0.94)
                let matchedRequests = Int(Double(adRequests) * matchRate)
                let showRate = generator.double(in: 0.48...0.88)
                let impressions = Int(Double(matchedRequests) * showRate)
                let ctr = generator.double(in: 0.012...0.075)
                let clicks = Int(Double(impressions) * ctr)
                let eCPM = generator.double(in: 1.8...8.5)
                let earnings = Double(impressions) * eCPM / 1_000
                let metrics = AdMobMetrics(
                    estimatedEarnings: earnings,
                    impressions: impressions,
                    clicks: clicks,
                    eCPM: eCPM,
                    adRequests: adRequests,
                    matchedRequests: matchedRequests,
                    observedECPM: eCPM
                )
                rows.append(AdMobReportRow(
                    id: "mock-\(dayOffset)-\(placementIndex)",
                    date: date,
                    appName: placement.app,
                    adUnitName: placement.adUnit,
                    metrics: metrics
                ))
            }
        }

        let totals = rows.reduce(AdMobMetrics(estimatedEarnings: 0, impressions: 0, clicks: 0, eCPM: 0, adRequests: 0, matchedRequests: 0, observedECPM: 0)) { partial, row in
            let earnings = partial.estimatedEarnings + row.metrics.estimatedEarnings
            let impressions = partial.impressions + row.metrics.impressions
            let clicks = partial.clicks + row.metrics.clicks
            let ecpm = impressions > 0 ? (earnings / Double(impressions) * 1000.0) : 0
            let adRequests = partial.adRequests + row.metrics.adRequests
            let matchedRequests = partial.matchedRequests + row.metrics.matchedRequests
            let observedECPM = impressions > 0 ? (earnings / Double(impressions) * 1000.0) : 0
            return AdMobMetrics(
                estimatedEarnings: earnings,
                impressions: impressions,
                clicks: clicks,
                eCPM: ecpm,
                adRequests: adRequests,
                matchedRequests: matchedRequests,
                observedECPM: observedECPM
            )
        }

        return AdMobReport(startDate: range.startDate, endDate: range.endDate, rows: rows, totals: totals)
    }

    func fetchCountryReport(accountId: String, range: DateRange, timeZone: String?) async throws -> [AdMobCountrySummary] {
        [
            AdMobCountrySummary(id: "US", name: "United States", code: "US", earnings: 42.15, impressions: 18_250, clicks: 520, adRequests: 28_500, matchedRequests: 23_200, eCPM: 2.31),
            AdMobCountrySummary(id: "GB", name: "United Kingdom", code: "GB", earnings: 18.70, impressions: 7_400, clicks: 210, adRequests: 11_800, matchedRequests: 9_500, eCPM: 2.53),
            AdMobCountrySummary(id: "CA", name: "Canada", code: "CA", earnings: 11.90, impressions: 5_100, clicks: 140, adRequests: 8_100, matchedRequests: 6_550, eCPM: 2.33),
            AdMobCountrySummary(id: "DE", name: "Germany", code: "DE", earnings: 9.40, impressions: 4_200, clicks: 118, adRequests: 6_900, matchedRequests: 5_400, eCPM: 2.24),
            AdMobCountrySummary(id: "AU", name: "Australia", code: "AU", earnings: 7.80, impressions: 3_100, clicks: 86, adRequests: 5_200, matchedRequests: 4_100, eCPM: 2.52)
        ]
    }

    private func mockSeed(accountId: String, range: DateRange, calendar: Calendar) -> UInt64 {
        let start = calendar.dateComponents([.year, .month, .day], from: range.startDate)
        let end = calendar.dateComponents([.year, .month, .day], from: range.endDate)
        var seed = UInt64(start.year ?? 0) * 10_000 + UInt64(start.month ?? 0) * 100 + UInt64(start.day ?? 0)
        seed = seed &* 31 &+ UInt64(end.year ?? 0) * 10_000 + UInt64(end.month ?? 0) * 100 + UInt64(end.day ?? 0)
        for byte in accountId.utf8 {
            seed = seed &* 109 &+ UInt64(byte)
        }
        return seed
    }

    func fetchMonthlyEarnings(accountId: String, range: DateRange, timeZone: String?) async throws -> [AdMobMonthlyEarning] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone.flatMap(TimeZone.init(identifier:)) ?? .current
        let startComponents = calendar.dateComponents([.year, .month], from: range.startDate)
        let start = calendar.date(from: startComponents) ?? range.startDate
        let endComponents = calendar.dateComponents([.year, .month], from: range.endDate)
        let end = calendar.date(from: endComponents) ?? range.endDate
        let monthCount = max((calendar.dateComponents([.month], from: start, to: end).month ?? 0) + 1, 1)
        var generator = SeededMockGenerator(seed: mockSeed(accountId: accountId, range: range, calendar: calendar))
        let baseline = generator.double(in: 480...1_250)

        return (0..<monthCount).compactMap { offset in
            guard let month = calendar.date(byAdding: .month, value: offset, to: start) else { return nil }
            let trend = 1 + Double(offset) * generator.double(in: 0.008...0.035)
            let variation = generator.double(in: 0.78...1.24)
            return AdMobMonthlyEarning(month: month, estimatedEarnings: baseline * trend * variation)
        }
    }

    func fetchApps(accountId: String) async throws -> [AdMobApp] {
        [
            AdMobApp(appId: "apps/1", displayName: "Crypto Profit Loss Calculator", appStoreId: "1234567890", platform: "IOS"),
            AdMobApp(appId: "apps/2", displayName: "Notes Pro", appStoreId: "0987654321", platform: "IOS"),
            AdMobApp(appId: "apps/3", displayName: "Focus Timer", appStoreId: "com.focustimer.app", platform: "ANDROID")
        ]
    }

    func fetchAdUnits(accountId: String) async throws -> [AdMobAdUnit] {
        [
            AdMobAdUnit(name: "adUnits/1", adUnitId: "ca-app-pub-xxx/111", appId: "apps/1", displayName: "Banner Home", adFormat: "BANNER"),
            AdMobAdUnit(name: "adUnits/2", adUnitId: "ca-app-pub-xxx/222", appId: "apps/1", displayName: "Interstitial Level", adFormat: "INTERSTITIAL"),
            AdMobAdUnit(name: "adUnits/3", adUnitId: "ca-app-pub-xxx/333", appId: "apps/2", displayName: "Rewarded Bonus", adFormat: "REWARDED")
        ]
    }
}

private struct SeededMockGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func int(in range: ClosedRange<Int>) -> Int {
        let width = UInt64(range.upperBound - range.lowerBound + 1)
        return range.lowerBound + Int(next() % width)
    }

    mutating func double(in range: ClosedRange<Double>) -> Double {
        let unit = Double(next() >> 11) / Double(1 << 53)
        return range.lowerBound + unit * (range.upperBound - range.lowerBound)
    }

    private mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
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

private struct ListAppsResponse: Decodable {
    let apps: [AdMobAppResponse]?
}

private struct AdMobAppResponse: Decodable {
    let appId: String?
    let name: String?
    let platform: String?
    let linkedAppInfo: LinkedAppInfoResponse?
    let manualAppInfo: ManualAppInfoResponse?

    private enum CodingKeys: String, CodingKey {
        case appId
        case name
        case platform
        case linkedAppInfo
        case manualAppInfo
    }
}

private struct LinkedAppInfoResponse: Decodable {
    let appStoreId: String?
    let displayName: String?
}

private struct ManualAppInfoResponse: Decodable {
    let displayName: String?
}

private struct ListAdUnitsResponse: Decodable {
    let adUnits: [AdMobAdUnitResponse]?
}

private struct AdMobAdUnitResponse: Decodable {
    let name: String
    let adUnitId: String
    let appId: String
    let displayName: String
    let adFormat: String
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
    static func date(from string: String, timeZone: String?) -> Date? {
        guard string.count == 8 else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        if let timeZone, let resolved = TimeZone(identifier: timeZone) {
            formatter.timeZone = resolved
        } else {
            formatter.timeZone = TimeZone.current
        }
        return formatter.date(from: string)
    }

    static func month(from string: String, timeZone: String?) -> Date? {
        guard string.count == 6 else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMM"
        formatter.timeZone = timeZone.flatMap(TimeZone.init(identifier:)) ?? .current
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
