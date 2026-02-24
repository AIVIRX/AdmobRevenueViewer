import Foundation
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var user: AuthUserProfile?
    @Published var selectedAccount: AdMobAccount?
    @Published var dateRange: DateRange
    @Published var dateRangeOption: DateRangeOption

    init(dateRange: DateRange = .lastNDays(7), dateRangeOption: DateRangeOption = .last7Days) {
        self.dateRange = dateRange
        self.dateRangeOption = dateRangeOption
    }

    var isSignedIn: Bool {
        user != nil
    }
}

enum DateRangeOption: String, CaseIterable, Identifiable {
    case today = "Today"
    case last7Days = "7D"
    case last30Days = "30D"
    case last90Days = "90D"

    var id: String { rawValue }

    func range(calendar: Calendar = .current) -> DateRange {
        switch self {
        case .today:
            return .lastNDays(1, calendar: calendar)
        case .last7Days:
            return .lastNDays(7, calendar: calendar)
        case .last30Days:
            return .lastNDays(30, calendar: calendar)
        case .last90Days:
            return .lastNDays(90, calendar: calendar)
        }
    }
}
