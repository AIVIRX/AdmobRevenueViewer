import Foundation
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var user: AuthUserProfile?
    @Published var selectedAccount: AdMobAccount?
    @Published var dateRange: DateRange
    @Published var dateRangeOption: DateRangeOption
    @Published var isGuest = false

    init(dateRange: DateRange? = nil, dateRangeOption: DateRangeOption = .today) {
        self.dateRangeOption = dateRangeOption
        self.dateRange = dateRange ?? .lastNDays(1)
    }

    var isSignedIn: Bool {
        user != nil
    }
}

enum DateRangeOption: String, CaseIterable, Identifiable {
    case today = "Today"
    case yesterday = "Yesterday"
    case last7Days = "Last 7 days"
    case thisMonth = "This Month"
    case lastMonth = "Last Month"

    var id: String { rawValue }

    func range(calendar: Calendar = .current) -> DateRange {
        switch self {
        case .today:
            return .lastNDays(1, calendar: calendar)
        case .yesterday:
            let todayStart = calendar.startOfDay(for: Date())
            let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart
            return DateRange(startDate: yesterdayStart, endDate: yesterdayStart)
        case .last7Days:
            return .lastNDays(7, calendar: calendar)
        case .thisMonth:
            return currentMonthRange(calendar: calendar)
        case .lastMonth:
            return previousMonthRange(calendar: calendar)
        }
    }

    func comparisonRange(for range: DateRange, calendar: Calendar = .current) -> DateRange {
        switch self {
        case .today, .yesterday:
            let compareDate = calendar.date(byAdding: .day, value: -7, to: range.startDate) ?? range.startDate
            let start = calendar.startOfDay(for: compareDate)
            return DateRange(startDate: start, endDate: start)
        case .last7Days:
            return previousRange(days: 7, currentStart: range.startDate, calendar: calendar)
        case .thisMonth:
            return previousMonthToDateRange(currentRange: range, calendar: calendar)
        case .lastMonth:
            return monthBeforeLastRange(calendar: calendar)
        }
    }

    private func previousRange(days: Int, currentStart: Date, calendar: Calendar) -> DateRange {
        let currentStartDay = calendar.startOfDay(for: currentStart)
        let end = calendar.date(byAdding: .day, value: -1, to: currentStartDay) ?? currentStartDay
        let start = calendar.date(byAdding: .day, value: -max(days - 1, 0), to: end) ?? end
        return DateRange(startDate: start, endDate: end)
    }

    private func currentMonthRange(calendar: Calendar) -> DateRange {
        let now = Date()
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let start = calendar.startOfDay(for: startOfMonth)
        let end = calendar.startOfDay(for: now)
        return DateRange(startDate: start, endDate: end)
    }

    private func previousMonthRange(calendar: Calendar) -> DateRange {
        let now = Date()
        guard let startOfThisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)),
              let startOfLastMonth = calendar.date(byAdding: .month, value: -1, to: startOfThisMonth),
              let endOfLastMonth = calendar.date(byAdding: .day, value: -1, to: startOfThisMonth) else {
            let fallback = calendar.startOfDay(for: now)
            return DateRange(startDate: fallback, endDate: fallback)
        }
        return DateRange(startDate: calendar.startOfDay(for: startOfLastMonth),
                         endDate: calendar.startOfDay(for: endOfLastMonth))
    }

    private func previousMonthToDateRange(currentRange: DateRange, calendar: Calendar) -> DateRange {
        guard let startOfThisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: currentRange.startDate)),
              let startOfLastMonth = calendar.date(byAdding: .month, value: -1, to: startOfThisMonth) else {
            return currentRange
        }
        let days = max(calendar.dateComponents([.day], from: calendar.startOfDay(for: currentRange.startDate), to: calendar.startOfDay(for: currentRange.endDate)).day ?? 0, 0)
        let end = calendar.date(byAdding: .day, value: days, to: startOfLastMonth) ?? startOfLastMonth
        return DateRange(startDate: calendar.startOfDay(for: startOfLastMonth),
                         endDate: calendar.startOfDay(for: end))
    }

    private func monthBeforeLastRange(calendar: Calendar) -> DateRange {
        let now = Date()
        guard let startOfThisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)),
              let startOfLastMonth = calendar.date(byAdding: .month, value: -1, to: startOfThisMonth),
              let startOfMonthBefore = calendar.date(byAdding: .month, value: -1, to: startOfLastMonth),
              let endOfMonthBefore = calendar.date(byAdding: .day, value: -1, to: startOfLastMonth) else {
            let fallback = calendar.startOfDay(for: now)
            return DateRange(startDate: fallback, endDate: fallback)
        }
        return DateRange(startDate: calendar.startOfDay(for: startOfMonthBefore),
                         endDate: calendar.startOfDay(for: endOfMonthBefore))
    }
}
