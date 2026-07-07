import Combine
import Foundation

@MainActor
final class TwelveMonthEarningsViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var earnings: [AdMobMonthlyEarning] = []
    @Published var errorMessage: String?

    private let apiClient: AdMobAPIClient
    private var loadedAccountId: String?

    init(apiClient: AdMobAPIClient) {
        self.apiClient = apiClient
    }

    func load(account: AdMobAccount, force: Bool = false) async {
        guard force || loadedAccountId != account.id || earnings.isEmpty else { return }
        isLoading = true
        errorMessage = nil

        do {
            let calendar = calendar(for: account.reportingTimeZone)
            let now = Date()
            let currentMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
            let startMonth = calendar.date(from: calendar.dateComponents([.year], from: currentMonth)) ?? currentMonth
            let range = DateRange(startDate: startMonth, endDate: calendar.startOfDay(for: now))
            let response = try await apiClient.fetchMonthlyEarnings(
                accountId: account.id,
                range: range,
                timeZone: account.reportingTimeZone
            )
            earnings = filledMonths(response, start: startMonth, calendar: calendar)
            loadedAccountId = account.id
        } catch is CancellationError {
            return
        } catch let urlError as URLError where urlError.code == .cancelled {
            return
        } catch {
            errorMessage = "Unable to load monthly earnings: \(ErrorMessageFormatter.message(for: error))"
        }

        isLoading = false
    }

    private func filledMonths(
        _ response: [AdMobMonthlyEarning],
        start: Date,
        calendar: Calendar
    ) -> [AdMobMonthlyEarning] {
        let valuesByMonth = Dictionary(uniqueKeysWithValues: response.map {
            (monthKey($0.month, calendar: calendar), $0.estimatedEarnings)
        })
        return (0..<12).compactMap { offset in
            guard let month = calendar.date(byAdding: .month, value: offset, to: start) else { return nil }
            return AdMobMonthlyEarning(
                month: month,
                estimatedEarnings: valuesByMonth[monthKey(month, calendar: calendar)] ?? 0
            )
        }
    }

    private func monthKey(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)"
    }

    private func calendar(for timeZoneIdentifier: String?) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? .current
        return calendar
    }
}
