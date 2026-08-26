import BackgroundTasks
import Foundation
import WidgetKit

@MainActor
enum WidgetBackgroundRefreshCoordinator {
    static let taskIdentifier = "com.Maicol.AdmobTracker.widget-refresh"
    private static let refreshInterval: TimeInterval = 30 * 60

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(refreshTask)
        }
    }

    static func schedule() {
        guard WidgetRevenueStore.loadRefreshConfiguration() != nil else { return }

        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: refreshInterval)
        try? BGTaskScheduler.shared.submit(request)
    }

    static func disable() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
        WidgetRevenueStore.clearAll()
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetRevenueStore.widgetKind)
    }

    private static func handle(_ backgroundTask: BGAppRefreshTask) {
        schedule()

        let refreshTask = Task { @MainActor in
            guard let configuration = WidgetRevenueStore.loadRefreshConfiguration() else {
                return false
            }

            let authManager = AuthManager()
            await authManager.restorePreviousSignIn()
            guard authManager.currentUser != nil else { return false }

            let apiClient = LiveAdMobAPIClient(authManager: authManager)
            return await WidgetSnapshotRefresher.refresh(
                configuration: configuration,
                apiClient: apiClient
            )
        }

        backgroundTask.expirationHandler = {
            refreshTask.cancel()
        }

        Task {
            let success = await refreshTask.value
            backgroundTask.setTaskCompleted(success: success)
        }
    }
}

@MainActor
enum WidgetSnapshotRefresher {
    static func refresh(account: AdMobAccount, apiClient: AdMobAPIClient) async -> Bool {
        let configuration = WidgetRefreshConfiguration(
            accountId: account.id,
            currencyCode: account.currencyCode,
            reportingTimeZone: account.reportingTimeZone
        )
        WidgetRevenueStore.saveRefreshConfiguration(configuration)
        return await refresh(configuration: configuration, apiClient: apiClient)
    }

    static func refresh(
        configuration: WidgetRefreshConfiguration,
        apiClient: AdMobAPIClient
    ) async -> Bool {
        let calendar = calendar(timeZoneIdentifier: configuration.reportingTimeZone)
        let ranges: [(WidgetTimeRange, DateRange)] = [
            (.today, DateRangeOption.today.range(calendar: calendar)),
            (.yesterday, DateRangeOption.yesterday.range(calendar: calendar)),
            (.last7Days, DateRangeOption.last7Days.range(calendar: calendar)),
            (.thisMonth, DateRangeOption.thisMonth.range(calendar: calendar)),
            (.lastMonth, DateRangeOption.lastMonth.range(calendar: calendar))
        ]

        var reports: [WidgetTimeRange: AdMobReport] = [:]
        for (range, dateRange) in ranges {
            guard !Task.isCancelled else { return false }
            if let report = try? await apiClient.fetchReport(
                accountId: configuration.accountId,
                range: dateRange,
                timeZone: configuration.reportingTimeZone
            ) {
                reports[range] = report
            }
        }

        guard !reports.isEmpty else { return false }
        let lastSevenDaysRange = ranges.first { $0.0 == .last7Days }!.1

        for (range, dateRange) in ranges {
            guard let report = reports[range] else { continue }
            let seriesRange = (range == .today || range == .yesterday) ? lastSevenDaysRange : dateRange
            let seriesReport = (range == .today || range == .yesterday) ? reports[.last7Days] : report
            let values = seriesReport.map {
                seriesValues(for: $0, range: seriesRange, calendar: calendar)
            } ?? [report.totals.estimatedEarnings]

            WidgetRevenueStore.save(WidgetRevenueSnapshot(
                amount: report.totals.estimatedEarnings,
                currencyCode: configuration.currencyCode,
                rangeLabel: rangeLabel(for: range),
                updatedAt: Date(),
                values: values
            ), for: range)
        }

        WidgetCenter.shared.reloadTimelines(ofKind: WidgetRevenueStore.widgetKind)
        return true
    }

    private static func calendar(timeZoneIdentifier: String?) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        if let timeZoneIdentifier, let timeZone = TimeZone(identifier: timeZoneIdentifier) {
            calendar.timeZone = timeZone
        } else {
            calendar.timeZone = .current
        }
        return calendar
    }

    private static func seriesValues(for report: AdMobReport, range: DateRange, calendar: Calendar) -> [Double] {
        let groupedRows = Dictionary(grouping: report.rows) { calendar.startOfDay(for: $0.date) }
        let start = calendar.startOfDay(for: range.startDate)
        let end = calendar.startOfDay(for: range.endDate)
        let dayCount = max(calendar.dateComponents([.day], from: start, to: end).day ?? 0, 0) + 1

        return (0..<dayCount).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            return (groupedRows[date] ?? []).reduce(0) { $0 + $1.metrics.estimatedEarnings }
        }
    }

    private static func rangeLabel(for range: WidgetTimeRange) -> String {
        switch range {
        case .today: return "Today"
        case .yesterday: return "Yesterday"
        case .last7Days: return "Last 7 Days"
        case .thisMonth: return "This Month"
        case .lastMonth: return "Last Month"
        }
    }
}
