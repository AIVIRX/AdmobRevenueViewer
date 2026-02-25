import Foundation

protocol AdSenseAPIClient {
    func fetchAccounts() async throws -> [AdSenseAccount]
    func fetchPayments(accountName: String) async throws -> [AdSensePayment]
}

struct AdSenseAccount: Hashable {
    let name: String
    let displayName: String?
}

struct AdSensePayment: Hashable {
    let name: String
    let amount: String
    let date: Date?
}

final class LiveAdSenseAPIClient: AdSenseAPIClient {
    private let authManager: AuthManaging
    private let session: URLSession

    init(authManager: AuthManaging, session: URLSession = .shared) {
        self.authManager = authManager
        self.session = session
    }

    func fetchAccounts() async throws -> [AdSenseAccount] {
        let url = URL(string: "https://adsense.googleapis.com/v2/accounts")!
        let data = try await request(url: url)
        let response = try JSONDecoder().decode(AdSenseAccountsResponse.self, from: data)
        return response.accounts?.map { AdSenseAccount(name: $0.name, displayName: $0.displayName) } ?? []
    }

    func fetchPayments(accountName: String) async throws -> [AdSensePayment] {
        let url = URL(string: "https://adsense.googleapis.com/v2/\(accountName)/payments")!
        let data = try await request(url: url)
        let response = try JSONDecoder().decode(AdSensePaymentsResponse.self, from: data)
        return response.payments?.map { payment in
            let date = payment.date.flatMap { AdSenseDateParser.date(from: $0) }
            let amount = payment.amount ?? "--"
            return AdSensePayment(name: payment.name, amount: amount, date: date)
        } ?? []
    }

    private func request(url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let token = try await authManager.accessToken()
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AdSenseAPIError.httpError(statusCode: httpResponse.statusCode, body: body)
        }
        return data
    }
}

enum AdSenseAPIError: LocalizedError {
    case httpError(statusCode: Int, body: String)

    var errorDescription: String? {
        switch self {
        case let .httpError(statusCode, body):
            if body.isEmpty {
                return "HTTP \(statusCode)"
            }
            return "HTTP \(statusCode): \(body)"
        }
    }
}

private struct AdSenseAccountsResponse: Decodable {
    let accounts: [AdSenseAccountResponse]?
}

private struct AdSenseAccountResponse: Decodable {
    let name: String
    let displayName: String?
}

private struct AdSensePaymentsResponse: Decodable {
    let payments: [AdSensePaymentResponse]?
}

private struct AdSensePaymentResponse: Decodable {
    let name: String
    let amount: String?
    let date: AdSenseDateResponse?
}

private struct AdSenseDateResponse: Decodable {
    let year: Int?
    let month: Int?
    let day: Int?
}

private enum AdSenseDateParser {
    static func date(from response: AdSenseDateResponse) -> Date? {
        guard let year = response.year, let month = response.month, let day = response.day else { return nil }
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        return components.date
    }
}

final class MockAdSenseAPIClient: AdSenseAPIClient {
    func fetchAccounts() async throws -> [AdSenseAccount] {
        [
            AdSenseAccount(name: "accounts/pub-0000000000000000", displayName: "Main Publisher")
        ]
    }

    func fetchPayments(accountName: String) async throws -> [AdSensePayment] {
        let calendar = Calendar.current
        let lastPaymentDate = calendar.date(byAdding: .day, value: -35, to: Date())
        return [
            AdSensePayment(name: "\(accountName)/payments/unpaid", amount: "USD 43.12", date: nil),
            AdSensePayment(name: "\(accountName)/payments/last", amount: "USD 128.45", date: lastPaymentDate)
        ]
    }
}
